//
//  PresenceCoordinatorTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
import Foundation
import SwiftData
@testable import Scrobblr

private let cover = URL(string: "https://example.com/a.jpg")!

#if os(macOS)
@Suite @MainActor struct PresenceCoordinatorTests {
    let container: ModelContainer
    let settings: Settings
    let discord = FakeDiscord()
    let remote = FakeRemote()
    let epistolares = FakeEpistolares()
    let clock = Locked(Date(timeIntervalSince1970: 1_000_000))
    let lastFM: LastFMScrobbler

    init() throws {
        container = try makeContainer()
        settings = Settings.shared(in: container.mainContext)
        lastFM = LastFMScrobbler(transport: FakeLastFMTransport(), epistolares: FakeEpistolares(), credentials: MemoryCredentials(LastFMScrobblerTests.signedIn).store)
    }

    func make() -> PresenceCoordinator {
        PresenceCoordinator(settings: settings, discord: discord, remote: remote, lastFM: lastFM, trackInfo: epistolares, now: { [clock] in clock.value })
    }

    func relay(_ presence: PresenceCoordinator, _ value: GenericPlaybackInfo? = info("Remote", elapsed: 10), device: String = "ios", ago: TimeInterval = 0) {
        presence.relayUpdated(info: value, device: device, updatedAt: clock.value.addingTimeInterval(-ago))
    }

    static func trackInfo(_ name: String) throws -> EpistolaresTrackInfo {
        try JSONDecoder().decode(EpistolaresTrackInfo.self, from: Data(#"{"track":{"name":"\#(name)","listeners":1,"scrobbles":2,"tags":[]},"artist":{"name":"A","listeners":1,"scrobbles":2}}"#.utf8))
    }

    @Test func identicalBroadcastsSentOnce() {
        let presence = make()
        presence.broadcast(current: info(elapsed: 10), coverURL: cover)
        presence.broadcast(current: info(elapsed: 20), coverURL: cover)
        #expect(discord.updates.count == 1)
        #expect(discord.updates.first?.coverURL == cover)
    }

    @Test func changedCoverResends() {
        let presence = make()
        let other = URL(string: "https://example.com/b.jpg")!
        presence.broadcast(current: info(), coverURL: cover)
        presence.broadcast(current: info(), coverURL: other)
        #expect(discord.updates.map(\.coverURL) == [cover, other])
    }

    @Test func disablingDiscordStopsSinksAndClearsRelay() {
        let presence = make()
        relay(presence)
        presence.broadcast(current: info(), coverURL: cover)
        #expect(presence.relay.info != nil)
        let updates = discord.updates.count

        settings.discordPresenceEnabled = false
        presence.broadcast(current: info(), coverURL: cover)
        #expect(discord.stops == 1)
        #expect(remote.stops == 1)
        #expect(presence.relay.info == nil)
        #expect(presence.relay.device == nil)
        #expect(presence.relay.updatedAt == nil)

        settings.discordPresenceEnabled = true
        presence.broadcast(current: info(), coverURL: cover)
        #expect(discord.updates.count == updates + 1)
    }

    @Test func relayShownOnlyWhenLocalIdleAndReceiveEnabled() {
        let presence = make()
        relay(presence)
        #expect(presence.displayInfo?.title == "Remote")
        #expect(presence.isDisplayingFromRelay)
        #expect(discord.updates.last?.info?.title == "Remote")

        presence.broadcast(current: info(), coverURL: cover)
        #expect(presence.displayInfo?.title == "Song")
        #expect(presence.displayCoverURL == cover)
        #expect(!presence.isDisplayingFromRelay)
        #expect(presence.displayDeviceName == nil)

        presence.broadcast(current: info(playing: false), coverURL: cover)
        #expect(presence.displayInfo?.title == "Remote")
        settings.receiveCrossDevicePresenceEnabled = false
        #expect(presence.displayInfo == nil)
        #expect(presence.displayCoverURL == nil)
        #expect(!presence.isDisplayingFromRelay)
    }

    @Test func relayDriftAdvancesElapsed() {
        let presence = make()
        relay(presence, info("Remote", elapsed: 10), ago: 30)
        #expect(discord.updates.last?.info?.elapsedTimeSeconds == 40)
        #expect(presence.displayInfo?.elapsedTimeSeconds == 10)
    }

    @Test func relayPastDurationNotBroadcast() {
        let presence = make()
        relay(presence, info("Remote", duration: 200, elapsed: 190), ago: 30)
        #expect(presence.relay.info != nil)
        #expect(discord.updates.allSatisfy { $0.info == nil })
    }

    @Test func receiveDisabledStopsRemote() {
        settings.receiveCrossDevicePresenceEnabled = false
        let presence = make()
        #expect(remote.starts.isEmpty)
        #expect(remote.stops == 1)

        settings.receiveCrossDevicePresenceEnabled = true
        presence.broadcast(current: nil, coverURL: nil)
        #expect(remote.starts == ["tester:pk"])
    }

    @Test func playingWithoutCoverNotBroadcast() {
        let presence = make()
        relay(presence)
        let updates = discord.updates.count
        presence.broadcast(current: info(), coverURL: nil)
        #expect(discord.updates.count == updates + 1)
        #expect(discord.updates.last?.info == nil)
        presence.broadcast(current: info(), coverURL: nil)
        #expect(discord.updates.count == updates + 1)
    }

    @Test(arguments: [("ios", "iPhone"), ("mac", "Mac"), ("macos", "Mac"), ("other", "Other")])
    func deviceNameMapping(device: String, name: String) {
        let presence = make()
        relay(presence, device: device)
        #expect(presence.displayDeviceName == name)
    }

    @Test func relayTrackInfoFetchedOncePerID() async throws {
        let result = try Self.trackInfo("Remote")
        epistolares.state.mutate { $0.trackInfoHandler = { _ in result } }
        let presence = make()
        relay(presence, info("Remote", elapsed: 10))
        relay(presence, info("Remote", elapsed: 20))
        #expect(await waitUntil { presence.relay.trackInfo != nil })
        #expect(epistolares.state.value.trackInfoCalls == ["Remote"])

        relay(presence, info("Other"))
        #expect(presence.relay.trackInfo == nil)
        #expect(await waitUntil { epistolares.state.value.trackInfoCalls == ["Remote", "Other"] })
    }

    @Test func staleRelayTrackInfoDiscarded() async throws {
        let gate = Gate()
        let one = try Self.trackInfo("One"), two = try Self.trackInfo("Two")
        epistolares.state.mutate {
            $0.trackInfoHandler = { track in
                guard track == "One" else { return two }
                await gate.wait()
                return one
            }
        }
        let presence = make()
        relay(presence, info("One"))
        relay(presence, info("Two"))
        #expect(await waitUntil { presence.relay.trackInfo?.track.name == "Two" })
        gate.open()
        #expect(await !waitUntil(timeout: .milliseconds(200)) { presence.relay.trackInfo?.track.name == "One" })
    }
}
#endif

#if os(iOS)
@Suite @MainActor struct PresenceCoordinatorIOSTests {
    let container: ModelContainer
    let settings: Settings
    let epistolares = FakeEpistolares()
    let lastFM: LastFMScrobbler

    init() throws {
        container = try makeContainer()
        settings = Settings.shared(in: container.mainContext)
        lastFM = LastFMScrobbler(transport: FakeLastFMTransport(), epistolares: epistolares, credentials: MemoryCredentials(LastFMScrobblerTests.signedIn).store)
    }

    var pushes: [GenericPlaybackInfo?] { epistolares.state.value.pushes }

    func noPushBeyond(_ count: Int) async -> Bool {
        await !waitUntil(timeout: .milliseconds(150)) { pushes.count > count }
    }

    @Test func pushOnlyWhenKeyChanges() async {
        let presence = PresenceCoordinator(settings: settings, lastFM: lastFM)
        presence.broadcast(current: info(elapsed: 10), coverURL: cover)
        #expect(await waitUntil { pushes.count == 1 })
        presence.broadcast(current: info(elapsed: 20), coverURL: cover)
        #expect(await noPushBeyond(1))
        presence.broadcast(current: info(playing: false), coverURL: cover)
        #expect(await waitUntil { pushes.count == 2 })
        #expect(pushes.first??.coverURL == cover)
        #expect(pushes.last! == nil)
    }

    @Test func playingWithoutCoverDoesNotPush() async {
        let presence = PresenceCoordinator(settings: settings, lastFM: lastFM)
        presence.broadcast(current: info(), coverURL: nil)
        #expect(await noPushBeyond(0))
        presence.broadcast(current: info(), coverURL: cover)
        #expect(await waitUntil { pushes.count == 1 })
        #expect(pushes.first??.coverURL == cover)
    }

    @Test func pushDisabledSettingSkips() async {
        settings.crossDevicePresenceEnabled = false
        let presence = PresenceCoordinator(settings: settings, lastFM: lastFM)
        presence.broadcast(current: info(), coverURL: cover)
        #expect(await noPushBeyond(0))
    }
}
#endif
