//
//  PresenceCoordinator.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Foundation
import os

nonisolated struct BroadcastKey: Equatable {
    let title, artist: String, album: String?, isPlaying: Bool, coverURL: URL?

    init(_ info: GenericPlaybackInfo) {
        (title, artist, album, isPlaying, coverURL) = (info.title, info.artist, info.album, info.isPlaying, info.coverURL)
    }
}

#if os(macOS)
protocol DiscordSink: AnyObject { func start(); func stop(); func update(for info: GenericPlaybackInfo?, coverURL: URL?) }
protocol RemoteSink: AnyObject { func start(username: String, pushKey: String); func stop() }
extension DiscordPresence: DiscordSink {}
extension RemotePresenceClient: RemoteSink {}

struct RelayState {
    var info: GenericPlaybackInfo?, device: String?, updatedAt: Date?
    var trackInfo: EpistolaresTrackInfo?, trackInfoID: String?

    static let empty = RelayState()

    func driftCorrected(at now: Date) -> GenericPlaybackInfo? {
        guard let info, let updatedAt else { return info }
        return info.adjustedForRelayDrift(since: updatedAt, now: now)
    }
}
#endif

@Observable
final class PresenceCoordinator {
    private(set) var current: GenericPlaybackInfo?
    private(set) var coverURL: URL?

    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let lastFM: LastFMScrobbler
    @ObservationIgnored private var last: BroadcastKey?

    private var readyToBroadcast: GenericPlaybackInfo? {
        guard let current, current.isPlaying, let coverURL else { return nil }
        return current.withCoverURL(coverURL)
    }

    var isLocalIdle: Bool { current?.isPlaying != true }

    func broadcast(current: GenericPlaybackInfo?, coverURL: URL?) {
        self.current = current
        self.coverURL = coverURL
        update()
    }

    #if os(macOS)
    private(set) var relay = RelayState.empty

    @ObservationIgnored private let discord: any DiscordSink
    @ObservationIgnored private let remote: any RemoteSink
    @ObservationIgnored private let trackInfo: any EpistolaresAPI
    @ObservationIgnored private let now: () -> Date

    init(settings: Settings, discord: any DiscordSink, remote: any RemoteSink, lastFM: LastFMScrobbler, trackInfo: any EpistolaresAPI, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.discord = discord
        self.remote = remote
        self.lastFM = lastFM
        self.trackInfo = trackInfo
        self.now = now
        update()
    }

    static func live(settings: Settings, discord: DiscordPresence, lastFM: LastFMScrobbler, trackInfo: any EpistolaresAPI) -> PresenceCoordinator {
        let remote = RemotePresenceClient()
        let coordinator = PresenceCoordinator(settings: settings, discord: discord, remote: remote, lastFM: lastFM, trackInfo: trackInfo)
        // the closure lives on remote, so remote outlives every call
        remote.onUpdate = { [weak coordinator, unowned remote] in
            coordinator?.relayUpdated(info: remote.latest, device: remote.latestDevice, updatedAt: remote.latestUpdatedAt)
        }
        return coordinator
    }

    var displayInfo: GenericPlaybackInfo? {
        guard isLocalIdle else { return current }
        return settings.receiveCrossDevicePresenceEnabled ? relay.info : nil
    }

    var displayCoverURL: URL? { isLocalIdle ? displayInfo?.coverURL : coverURL }

    var isDisplayingFromRelay: Bool { isLocalIdle && displayInfo != nil }

    var displayDeviceName: String? {
        guard isDisplayingFromRelay, let device = relay.device else { return nil }
        switch device.lowercased() {
        case "ios": return "iPhone"
        case "mac", "macos": return "Mac"
        default: return device.capitalized
        }
    }

    func relayUpdated(info: GenericPlaybackInfo?, device: String?, updatedAt: Date?) {
        (relay.info, relay.device, relay.updatedAt) = (info, device, updatedAt)
        Task.immediate { [weak self] in await self?.fetchRelayTrackInfo() }
        update()
    }

    private func update() {
        guard settings.discordPresenceEnabled else {
            discord.stop()
            remote.stop()
            relay = .empty
            last = nil
            return
        }
        discord.start()

        if settings.receiveCrossDevicePresenceEnabled, let username = lastFM.username, let pushKey = lastFM.pushKey {
            remote.start(username: username, pushKey: pushKey)
        } else {
            remote.stop()
            relay = .empty
        }

        let info = readyToBroadcast ?? (isLocalIdle ? relay.driftCorrected(at: now()) : nil)
        let key = info.map(BroadcastKey.init)
        guard key != last else { return }
        last = key
        discord.update(for: info, coverURL: info?.coverURL)
    }

    func fetchRelayTrackInfo() async {
        guard relay.trackInfoID != relay.info?.id else { return }
        (relay.trackInfoID, relay.trackInfo) = (relay.info?.id, nil)
        guard let info = relay.info else { return }
        do {
            let fetched = try await trackInfo.trackInfo(track: info.title, artist: info.artist, album: info.album, username: lastFM.username)
            guard relay.trackInfoID == info.id else { return }
            relay.trackInfo = fetched
        } catch {
            Logger.epistolares.error("Couldn't fetch relay track info: \(error.localizedDescription, privacy: .public)")
        }
    }
    #else
    init(settings: Settings, lastFM: LastFMScrobbler) {
        self.settings = settings
        self.lastFM = lastFM
    }

    private func update() {
        guard settings.crossDevicePresenceEnabled, isLocalIdle || coverURL != nil else { return }
        let key = readyToBroadcast.map(BroadcastKey.init)
        guard key != last else { return }
        last = key
        lastFM.pushPresence(readyToBroadcast, device: "ios")
    }
    #endif
}
