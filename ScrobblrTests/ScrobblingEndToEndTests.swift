//
//  ScrobblingEndToEndTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
import Foundation
import SwiftData
import LastFM
@testable import Scrobblr

@Suite @MainActor struct ScrobblingEndToEndTests {
    let container: ModelContainer
    let settings: Settings
    let transport = FakeLastFMTransport()
    let epistolares = FakeEpistolares()
    let credentials = MemoryCredentials(LastFMScrobblerTests.signedIn)
    let sleeper = ManualSleeper()
    let queueSleeper = ManualSleeper()
    let lastFM: LastFMScrobbler

    init() throws {
        container = try makeContainer()
        Correction.seedDefaultsIfNeeded(in: container.mainContext)
        settings = Settings.shared(in: container.mainContext)
        settings.useArtistFix = false
        lastFM = LastFMScrobbler(transport: transport, epistolares: epistolares, credentials: credentials.store)
    }

    var context: ModelContext { container.mainContext }
    var items: [QueuedScrobble] { (try? context.fetch(FetchDescriptor<QueuedScrobble>())) ?? [] }
    var scrobbled: [Scrobble] { transport.state.value.scrobbled.map(\.scrobble) }

    func make() -> ScrobblerManager {
        let queue = ScrobbleQueue(modelContainer: container, services: { [lastFM] in [lastFM] }, sleep: queueSleeper.sleep)
        return ScrobblerManager(
            modelContainer: container, settings: settings, lastFM: lastFM, trackInfo: epistolares,
            queue: queue, presence: fakePresence(settings: settings, lastFM: lastFM), sleep: sleeper.sleep, now: { Date(timeIntervalSince1970: 1_000_000) }
        )
    }

    func playToThreshold(_ manager: ScrobblerManager, _ value: GenericPlaybackInfo = info(duration: 200)) async {
        manager.update(value)
        await manager.settle()
        _ = await waitUntil { sleeper.waiting == 1 }
        sleeper.advance()
        _ = await waitUntil { scrobbled.count == 1 }
    }

    func failThenQueue(_ error: Error) async -> ScrobblerManager {
        transport.state.mutate { $0.scrobbleError = error }
        let manager = make()
        await playToThreshold(manager)
        _ = await waitUntil { items.count == 1 && queueSleeper.waiting == 1 }
        return manager
    }

    func retryNow(_ manager: ScrobblerManager) async -> TimeInterval? {
        items.forEach { $0.nextAttempt = .distantPast }
        return await manager.queue.processDue()
    }

    @Test func playToThresholdCallsTransportScrobble() async {
        await playToThreshold(make())
        let call = transport.state.value.scrobbled.first
        #expect(call?.scrobble.track == "Song")
        #expect(call?.scrobble.timestamp == Date(timeIntervalSince1970: 1_000_000))
        #expect(call?.sessionKey == "sk")
        #expect(items.isEmpty)
    }

    @Test func nowPlayingReachesTransport() async {
        let manager = make()
        manager.update(info(duration: 200))
        await manager.settle()
        #expect(transport.state.value.nowPlaying.map(\.scrobble.track) == ["Song"])
        #expect(transport.state.value.nowPlaying.first?.sessionKey == "sk")
    }

    @Test func serviceOfflineQueuesThenRetrySucceeds() async {
        let manager = await failThenQueue(LastFMError.LastFMServiceError(.ServiceOffline, "offline"))
        #expect(items.count == 1)
        transport.state.mutate { $0.scrobbleError = nil }
        #expect(await retryNow(manager) == nil)
        #expect(items.isEmpty)
        #expect(scrobbled.count == 2)
    }

    @Test func rateLimitRetriesWithBackoff() async throws {
        let manager = await failThenQueue(LastFMError.LastFMServiceError(.RateLimitExceeded, "slow down"))
        let delay = try #require(await retryNow(manager))
        #expect(abs(delay - 60) < 5)
        #expect(items.first?.attempt == 1)
        transport.state.mutate { $0.scrobbleError = nil }
        #expect(await retryNow(manager) == nil)
        #expect(items.isEmpty)
        #expect(scrobbled.count == 3)
    }

    @Test func invalidSessionKeyDropsWithoutQueue() async {
        transport.state.mutate { $0.scrobbleError = LastFMError.LastFMServiceError(.InvalidSessionKey, "bad key") }
        let manager = make()
        await playToThreshold(manager)
        #expect(scrobbled.count == 1)
        #expect(!(await waitUntil(timeout: .milliseconds(200)) { !items.isEmpty }))
    }

    @Test func noDataQueues() async {
        _ = await failThenQueue(LastFMError.NoData)
        #expect(items.count == 1)
    }

    @Test func urlErrorQueues() async {
        _ = await failThenQueue(URLError(.notConnectedToInternet))
        #expect(items.count == 1)
    }

    @Test func givesUpAfterMaxAttempts() async {
        let manager = await failThenQueue(URLError(.timedOut))
        for _ in 0..<ScrobbleQueue.maxAttempts {
            _ = await retryNow(manager)
        }
        #expect(items.isEmpty)
        #expect(scrobbled.count == 1 + ScrobbleQueue.maxAttempts)
    }

    @Test func queueSurvivesManagerRecreation() async {
        _ = await failThenQueue(LastFMError.NoData)
        transport.state.mutate { $0.scrobbleError = nil }
        items.forEach { $0.nextAttempt = .distantPast }
        let recreated = ScrobblerManager(modelContainer: container, settings: settings, lastFM: lastFM, trackInfo: epistolares, presence: fakePresence(settings: settings, lastFM: lastFM), sleep: sleeper.sleep)
        #expect(await waitUntil { scrobbled.count == 2 && items.isEmpty })
        #expect(transport.state.value.scrobbled.last?.sessionKey == "sk")
        withExtendedLifetime(recreated) {}
    }

    @Test func signOutDuringInFlightCommitDoesNotEnqueueFailure() async {
        let manager = make()
        manager.update(info(duration: 200))
        await manager.settle()
        let gate = Gate()
        transport.state.mutate {
            $0.scrobbleError = URLError(.timedOut)
            $0.gate = { await gate.wait() }
        }
        _ = await waitUntil { sleeper.waiting == 1 }
        sleeper.advance()
        #expect(await waitUntil { scrobbled.count == 1 })
        manager.signOut()
        gate.open()
        #expect(!(await waitUntil(timeout: .milliseconds(200)) { !items.isEmpty }))
    }

    @Test func signOutThenSignInDoesNotReplayOldQueue() async throws {
        let manager = await failThenQueue(URLError(.timedOut))
        manager.signOut()
        #expect(items.isEmpty)
        #expect(!lastFM.isAuthenticated)
        try await lastFM.completeAuthentication(token: "token")
        #expect(lastFM.isAuthenticated)
        transport.state.mutate { $0.scrobbleError = nil }
        #expect(await retryNow(manager) == nil)
        #expect(scrobbled.count == 1)
    }

    @Test func correctedMetadataIsWhatReachesTransport() async {
        await playToThreshold(make(), info("Song (Remastered 2011)", album: "Album (Remastered)", duration: 200))
        #expect(transport.state.value.nowPlaying.first?.scrobble.track == "Song")
        #expect(scrobbled.first?.track == "Song")
        #expect(scrobbled.first?.album == "Album")
    }
}
