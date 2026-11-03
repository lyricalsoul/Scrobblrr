//
//  MediaModel (iOS).swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//

#if os(iOS)
import MusicKit
import Combine
import SwiftData
import UIKit
import MediaPlayer
import Sentry
import os

@Observable
@MainActor
final class MediaModel {
    private(set) var authorizationStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus

    var isAuthorized: Bool { authorizationStatus == .authorized }

    var accessDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }

    @ObservationIgnored private let keeper = SilentAudioKeeper()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    @ObservationIgnored private var currentSongID: MusicItemID?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var expandedArtistName: String?

    private static let heartbeatInterval: Duration = .seconds(15)

    @ObservationIgnored private var staleMonitor = StaleEntryMonitor()

    @ObservationIgnored private var isBackgrounded = false
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
    private(set) var isObserving = false
    var observerCount: Int { lifecycleObservers.count + cancellables.count }

    private let manager: ScrobblerManager
    @ObservationIgnored private let modelContainer: ModelContainer
    @ObservationIgnored private let settings: Settings

    init(manager: ScrobblerManager, settings: Settings, modelContainer: ModelContainer) {
        self.manager = manager
        self.modelContainer = modelContainer
        self.settings = settings
    }

    deinit {
        heartbeatTask?.cancel()
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func start() async {
        authorizationStatus = await MusicAuthorization.request()
        guard isAuthorized else {
            Logger.auth.error("MusicKit authorization denied: \(String(describing: self.authorizationStatus), privacy: .public)")
            return
        }

        Task {
            attachObservers()
            await startHeartbeat()
            await publishCurrent()
        }
    }

    func attachObservers() {
        guard !isObserving else { return }
        isObserving = true
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isBackgrounded = true
                self?.backgroundedAt = Date()
                self?.keeper.start()
            }
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isBackgrounded = false
                self?.backgroundedAt = nil
                self?.keeper.stop()
            }
        })

        let player = SystemMusicPlayer.shared
        player.queue.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in await self?.publishCurrent() }
            }
            .store(in: &cancellables)
        player.state.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in await self?.publishCurrent() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Heartbeat

    // TODO: is this the right thing?
    private func startHeartbeat() async {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard !Task.isCancelled, let self else { return }
                self.authorizationStatus = MusicAuthorization.currentStatus
                if self.isBackgrounded {
                    self.keeper.ensurePlaying()
                }
                let entry = SystemMusicPlayer.shared.queue.currentEntry
                Logger.musicKit.debug("Heartbeat tick: currentEntry=\(entry?.id ?? "nil", privacy: .public) status=\(String(describing: SystemMusicPlayer.shared.state.playbackStatus), privacy: .public)")
                self.trackStaleness(entry: entry)
                await self.publishCurrent()
            }
        }
    }

    private func trackStaleness(entry: MusicKit.MusicPlayer.Queue.Entry?) {
        let backgroundedFor = backgroundedAt.map { Int(Date().timeIntervalSince($0)) } ?? -1
        let nowPlayingAlive = (isBackgrounded || entry == nil) ? MPMusicPlayerController.systemMusicPlayer.nowPlayingItem != nil : nil

        if let nowPlayingAlive {
            let crumb = Breadcrumb(level: .debug, category: "musickit.heartbeat")
            crumb.message = "currentEntry=\(entry?.id ?? "nil") nowPlayingItem=\(nowPlayingAlive ? "alive" : "nil") backgrounded=\(isBackgrounded) backgroundedFor=\(backgroundedFor)s lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled)"
            SentrySDK.addBreadcrumb(crumb)
        }

        switch staleMonitor.record(hasEntry: entry != nil, isBackgrounded: isBackgrounded, at: Date()) {
        case .none:
            return
        case .recovered(let streak):
            SentrySDK.capture(message: "MusicKit recovered after \(streak) stale heartbeats")
        case .recover(let streak):
            let mechanism = settings.useMPMusicPlayerRecovery ? "mpMusicPlayerController" : "audioSession"
            if staleMonitor.attempts == 1 { SentrySDK.capture(message: "MusicKit stale for \(streak) heartbeats after \(backgroundedFor)s backgrounded, nowPlayingItem=\(nowPlayingAlive == true ? "alive" : "nil"), attempting \(mechanism) recovery") }

            if settings.useMPMusicPlayerRecovery {
                Logger.musicKit.info("currentEntry missing for \(streak) heartbeats, cycling MPMusicPlayerController connection")
                let player = MPMusicPlayerController.systemMusicPlayer
                player.endGeneratingPlaybackNotifications()
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    player.beginGeneratingPlaybackNotifications()
                }
            } else {
                Logger.musicKit.info("currentEntry missing for \(streak) heartbeats, cycling audio session")
                keeper.cycleSession()
            }
        }
    }

    // MARK: - Observation

    private func publishCurrent() async {
        if !isAuthorized {
            return
        }

        let player = SystemMusicPlayer.shared

        guard let item = player.queue.currentEntry?.item else {
            manager.update(nil)
            currentSongID = nil
            expandedArtistName = nil
            return
        }

        let title: String
        let artistName: String
        let album: String?
        let duration: TimeInterval?

        switch item {
        case .song(let song):
            title = song.title
            artistName = song.artistName
            album = song.albumTitle
            duration = song.duration
        case .musicVideo(let video):
            title = video.title
            artistName = video.artistName
            album = video.albumTitle
            duration = video.duration
        @unknown default:
            manager.update(nil)
            currentSongID = nil
            expandedArtistName = nil
            return
        }

        if item.id != currentSongID {
            let songID = item.id.rawValue
            let context = modelContainer.mainContext

            let resolvedArtist: String?
            if let cached = CachedArtist.cachedName(forSongID: songID, in: context) {
                resolvedArtist = cached
            } else {
                switch item {
                case .song(let song):
                    resolvedArtist = (try? await song.with([.artists]))?.artists?.first?.name
                case .musicVideo(let video):
                    resolvedArtist = (try? await video.with([.artists]))?.artists?.first?.name
                @unknown default:
                    resolvedArtist = nil
                }
                if let resolvedArtist {
                    CachedArtist.cache(songID: songID, artistName: resolvedArtist, in: context)
                }
            }

            guard player.queue.currentEntry?.item?.id == item.id else { return }

            currentSongID = item.id
            expandedArtistName = resolvedArtist
            if resolvedArtist == nil {
                Logger.musicKit.error("Failed to fetch expanded artist info for \(title, privacy: .public)")
            }
        }

        let info = GenericPlaybackInfo(
            title: title,
            artist: expandedArtistName ?? artistName,
            album: album,
            durationSeconds: Int(duration ?? 0),
            elapsedTimeSeconds: Int(player.playbackTime),
            isPlaying: player.state.playbackStatus == .playing
        )
        manager.update(info)
    }
}
#endif
