//
//  ScrobblerManagerTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
import Foundation
import SwiftData
@testable import Scrobblr

@Suite @MainActor struct ScrobblerManagerTests {
    let container: ModelContainer
    let settings: Settings
    let fake = FakeScrobbler()
    let sleeper = ManualSleeper()
    let clock = Locked(Date(timeIntervalSince1970: 1_000_000))
    let credentials = MemoryCredentials(LastFMScrobblerTests.signedIn)
    let lastFM: LastFMScrobbler

    init() throws {
        container = try makeContainer()
        settings = Settings.shared(in: container.mainContext)
        settings.useArtistFix = false
        lastFM = LastFMScrobbler(transport: FakeLastFMTransport(), epistolares: FakeEpistolares(), credentials: credentials.store)
    }

    var context: ModelContext { container.mainContext }
    var queued: Int { (try? context.fetchCount(FetchDescriptor<QueuedScrobble>())) ?? 0 }

    func make(services: [any Scrobbable]? = nil, corrector: ScrobbleCorrector? = nil) -> ScrobblerManager {
        ScrobblerManager(
            modelContainer: container, settings: settings, lastFM: lastFM, services: services ?? [fake],
            trackInfo: FakeEpistolares(), corrector: corrector, presence: fakePresence(settings: settings, lastFM: lastFM), sleep: sleeper.sleep, now: { [clock] in clock.value }
        )
    }

    func gatedCorrector(_ gate: Gate) -> ScrobbleCorrector {
        settings.useArtistFix = true
        return ScrobbleCorrector(context: context, settings: settings, fixArtist: { artist in
            await gate.wait()
            return CorrectedEntity(originalTitle: artist, correctedTitle: artist, reason: nil, shouldScrobble: true)
        })
    }

    func play(_ manager: ScrobblerManager, _ value: GenericPlaybackInfo?) async {
        manager.update(value)
        await manager.settle()
    }

    func scheduled(_ count: Int) async -> Bool {
        await waitUntil { sleeper.requested.count == count }
    }

    func tick(_ seconds: TimeInterval) {
        clock.value = clock.value.addingTimeInterval(seconds)
    }

    @Test func displayFollowsPlaybackThroughPresence() async {
        let manager = make()
        await play(manager, info(duration: 200))
        #expect(manager.presence.current?.title == "Song")
        #if os(macOS)
        #expect(manager.displayInfo?.title == "Song")
        #endif
        #expect(manager.displayTrackInfo == nil)
        await play(manager, nil)
        #expect(manager.presence.current == nil)
    }

    @Test func scrobblesOnceAtThreshold() async {
        let manager = make()
        await play(manager, info(duration: 200))
        #expect(fake.nowPlaying.map(\.track) == ["Song"])
        #expect(await scheduled(1))
        #expect(sleeper.requested == [.seconds(100)])
        sleeper.advance()
        #expect(await waitUntil { fake.scrobbled.count == 1 })
        #expect(fake.scrobbled.first?.timestamp == Date(timeIntervalSince1970: 1_000_000))
        tick(105)
        await play(manager, info(duration: 200, elapsed: 105))
        tick(5)
        await play(manager, info(duration: 200, elapsed: 110, playing: false))
        await play(manager, info(duration: 200, elapsed: 110))
        #expect(sleeper.requested.count == 1)
        #expect(fake.scrobbled.count == 1)
    }

    @Test func maxScrobbleSecondsCapsThreshold() async {
        settings.maxScrobbleSeconds = 240
        let manager = make()
        await play(manager, info(duration: 1000))
        #expect(await scheduled(1))
        #expect(sleeper.requested == [.seconds(240)])
    }

    @Test func shortTrackNeverScheduled() async {
        let manager = make()
        await play(manager, info(duration: 20))
        #expect(fake.nowPlaying.count == 1)
        #expect(sleeper.requested.isEmpty)
    }

    @Test func zeroDurationSendsNowPlayingOnly() async {
        let manager = make()
        await play(manager, info(duration: 0))
        #expect(fake.nowPlaying.count == 1)
        #expect(sleeper.requested.isEmpty)
    }

    @Test func zeroDurationNeverSchedulesEvenWithMinTrackZero() async {
        settings.minTrackSeconds = 0
        let manager = make()
        await play(manager, info(duration: 0))
        #expect(fake.nowPlaying.count == 1)
        #expect(sleeper.requested.isEmpty)
    }

    @Test func slowCorrectionDoesNotCauseFalseRestart() async {
        let gate = Gate()
        gate.open()
        let manager = make(corrector: gatedCorrector(gate))
        await play(manager, info(duration: 200))
        #expect(await scheduled(1))
        sleeper.advance()
        #expect(await waitUntil { fake.scrobbled.count == 1 })
        gate.close()
        tick(100)
        manager.refreshCurrentTrackCorrections()
        manager.update(info(duration: 200, elapsed: 100))
        #expect(await waitUntil { gate.entered == 2 })
        tick(60)
        gate.open()
        await manager.settle()
        #expect(fake.nowPlaying.count == 1)
        #expect(sleeper.requested.count == 1)
        #expect(fake.scrobbled.count == 1)
    }

    @Test func pauseCancelsAndResumeReschedulesRemaining() async {
        let manager = make()
        await play(manager, info(duration: 200))
        #expect(await scheduled(1))
        tick(40)
        await play(manager, info(duration: 200, elapsed: 40, playing: false))
        #expect(sleeper.waiting == 0)
        #expect(manager.current?.isPlaying == false)
        tick(300)
        await play(manager, info(duration: 200, elapsed: 40))
        #expect(await scheduled(2))
        #expect(sleeper.requested.last == .seconds(60))
        sleeper.advance()
        #expect(await waitUntil { fake.scrobbled.count == 1 })
        #expect(fake.nowPlaying.count == 2)
    }

    @Test func slowCorrectionKeepsEventTimestamp() async {
        let gate = Gate()
        let manager = make(corrector: gatedCorrector(gate))
        manager.update(info(duration: 200, elapsed: 10))
        #expect(await waitUntil { gate.entered == 1 })
        tick(30)
        gate.open()
        await manager.settle()
        #expect(await scheduled(1))
        sleeper.advance()
        #expect(await waitUntil { fake.scrobbled.count == 1 })
        #expect(fake.scrobbled.first?.timestamp == Date(timeIntervalSince1970: 999_990))
    }

    @Test func newTrackResetsAndUsesNewTimestamp() async {
        let manager = make()
        await play(manager, info("A", duration: 200))
        #expect(await scheduled(1))
        tick(50)
        await play(manager, info("B", duration: 200, elapsed: 3))
        #expect(await scheduled(2))
        #expect(sleeper.waiting == 1)
        #expect(sleeper.requested.last == .seconds(97))
        #expect(manager.current?.title == "B")
        sleeper.advance()
        #expect(await waitUntil { fake.scrobbled.count == 1 })
        #expect(fake.scrobbled.map(\.track) == ["B"])
        #expect(fake.scrobbled.first?.timestamp == Date(timeIntervalSince1970: 1_000_047))
    }

    @Test func stoppedClearsStateAndCancelsSchedule() async {
        let manager = make()
        await play(manager, info(duration: 200))
        #expect(await scheduled(1))
        await play(manager, nil)
        #expect(manager.current == nil && manager.rawCurrent == nil)
        #expect(sleeper.waiting == 0)
        await play(manager, info(duration: 200))
        #expect(fake.nowPlaying.count == 2)
        #expect(await scheduled(2))
    }

    @Test func repeatOneScrobblesAgain() async {
        let manager = make()
        await play(manager, info(duration: 200))
        #expect(await scheduled(1))
        sleeper.advance()
        #expect(await waitUntil { fake.scrobbled.count == 1 })
        tick(200)
        await play(manager, info(duration: 200, elapsed: 0))
        #expect(fake.nowPlaying.count == 2)
        #expect(await scheduled(2))
        #expect(sleeper.requested.last == .seconds(100))
        sleeper.advance()
        #expect(await waitUntil { fake.scrobbled.count == 2 })
        #expect(fake.scrobbled.last?.timestamp == Date(timeIntervalSince1970: 1_000_200))
    }

    @Test func seekForwardShortensDelay() async {
        let manager = make()
        await play(manager, info(duration: 200))
        #expect(await scheduled(1))
        tick(10)
        await play(manager, info(duration: 200, elapsed: 70))
        #expect(await scheduled(2))
        #expect(sleeper.requested.last == .seconds(30))
        #expect(sleeper.waiting == 1)
    }

    @Test func seekBackwardLengthensDelay() async {
        let manager = make()
        await play(manager, info(duration: 200, elapsed: 60))
        #expect(await scheduled(1))
        #expect(sleeper.requested == [.seconds(40)])
        tick(5)
        await play(manager, info(duration: 200, elapsed: 0))
        #expect(await scheduled(2))
        #expect(sleeper.requested.last == .seconds(100))
        #expect(sleeper.waiting == 1)
        #expect(fake.nowPlaying.count == 1)
    }

    @Test func skipDuringInFlightCommitStillDeliversAndDoesNotPoisonNextTrack() async {
        let gate = Gate()
        fake.gate = { await gate.wait() }
        let manager = make()
        await play(manager, info("A", duration: 200))
        #expect(await scheduled(1))
        sleeper.advance()
        #expect(await waitUntil { gate.entered == 1 })
        await play(manager, info("B", duration: 200))
        #expect(await scheduled(2))
        gate.open()
        #expect(await waitUntil { fake.scrobbled.map(\.track) == ["A"] })
        tick(10)
        await play(manager, info("B", duration: 200, elapsed: 10, playing: false))
        await play(manager, info("B", duration: 200, elapsed: 10))
        #expect(await scheduled(3))
        #expect(sleeper.requested.last == .seconds(90))
        sleeper.advance()
        #expect(await waitUntil { fake.scrobbled.map(\.track) == ["A", "B"] })
    }

    @Test func pauseDuringCorrectionAppliedInOrder() async {
        let gate = Gate()
        let manager = make(corrector: gatedCorrector(gate))
        manager.update(info(duration: 200))
        manager.update(info(duration: 200, playing: false))
        #expect(await waitUntil { gate.entered == 1 })
        gate.open()
        await manager.settle()
        #expect(manager.current?.isPlaying == false)
        #expect(sleeper.waiting == 0)
        #expect(fake.scrobbled.isEmpty)
    }

    @Test func resumeDuringCorrectionNotDropped() async {
        let gate = Gate()
        let manager = make(corrector: gatedCorrector(gate))
        manager.update(info(duration: 200, playing: false))
        manager.update(info(duration: 200))
        #expect(await waitUntil { gate.entered == 1 })
        gate.open()
        await manager.settle()
        #expect(manager.current?.isPlaying == true)
        #expect(fake.nowPlaying.count == 1)
        #expect(await scheduled(1))
        sleeper.advance()
        #expect(await waitUntil { fake.scrobbled.count == 1 })
    }

    @Test func unauthenticatedServiceGetsNothing() async {
        let signedOut = FakeScrobbler()
        signedOut.isAuthenticated = false
        let manager = make(services: [signedOut, fake])
        await play(manager, info(duration: 200))
        #expect(await scheduled(1))
        sleeper.advance()
        #expect(await waitUntil { fake.scrobbled.count == 1 })
        #expect(signedOut.nowPlaying.isEmpty && signedOut.scrobbled.isEmpty)
    }

    @Test func skippedByRuleSendsNothing() async {
        context.insert(ManualCorrection(kind: .track, trackName: "Song", albumName: "Album", artistName: "Artist", replacement: nil))
        let manager = make()
        await play(manager, info(duration: 200))
        #expect(manager.current?.title == "Song")
        #expect(fake.nowPlaying.isEmpty)
        #expect(sleeper.requested.isEmpty)
    }

    @Test func refreshCurrentTrackCorrectionsReschedules() async {
        let manager = make()
        await play(manager, info(duration: 200))
        #expect(await scheduled(1))
        context.insert(ManualCorrection(kind: .track, trackName: "Song", albumName: "Album", artistName: "Artist", replacement: "Renamed"))
        tick(10)
        manager.refreshCurrentTrackCorrections()
        await manager.settle()
        #expect(manager.current?.title == "Renamed")
        #expect(fake.nowPlaying.map(\.track) == ["Song", "Renamed"])
        #expect(await scheduled(2))
        #expect(sleeper.requested.last == .seconds(90))
        #expect(sleeper.waiting == 1)
        sleeper.advance()
        #expect(await waitUntil { fake.scrobbled.count == 1 })
        #expect(fake.scrobbled.first?.track == "Renamed")
        #expect(fake.scrobbled.first?.timestamp == Date(timeIntervalSince1970: 1_000_000))
    }

    @Test func signOutClearsQueueAndCredentials() async throws {
        let manager = make()
        manager.queue.enqueue(Scrobble(artist: "A", track: "T", album: nil, durationSeconds: 200, timestamp: .now), for: "Last.fm")
        #expect(queued == 1)
        manager.signOut()
        #expect(queued == 0)
        #expect(!lastFM.isAuthenticated)
        #expect(credentials.values.isEmpty)
    }
}
