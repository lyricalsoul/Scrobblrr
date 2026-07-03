//
//  MediaModel (iOS).swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//
// Consider using this on mac?

#if os(iOS)
import MusicKit
import Combine
import UIKit
import os

@Observable
@MainActor
final class MediaModel {
    private(set) var authorizationStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus

    /// Whether the user has granted MusicKit access
    var isAuthorized: Bool { authorizationStatus == .authorized }

    /// `true` only when the system has refused access
    var accessDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }

    @ObservationIgnored private let keeper = SilentAudioKeeper()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    @ObservationIgnored private var currentSongID: MusicItemID?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var expandedArtistName: String?

    private static let heartbeatInterval: Duration = .seconds(15)
    
    private let manager: ScrobblerManager

    init(manager: ScrobblerManager, settings: Settings) {
        self.manager = manager
    }

    deinit {
        heartbeatTask?.cancel()
    }

    /// Requests MusicKit access, starts the background audio keeper, and begins
    /// observing the system player
    func start() async {
        authorizationStatus = await MusicAuthorization.request()
        guard isAuthorized else {
            Logger.auth.error("MusicKit authorization denied: \(String(describing: self.authorizationStatus), privacy: .public)")
            return
        }

        Task {
            keeper.start()
            observe()
            await startHeartbeat()
            await publishCurrent()
        }
    }

    // MARK: - Heartbeat

    // TODO: is this the right thing?
    private func startHeartbeat() async {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard !Task.isCancelled, let self else { return }
                // Pick up a revocation that happened while we were running so the
                // UI can switch to the access gate cleanly instead of going stale.
                self.authorizationStatus = MusicAuthorization.currentStatus
                self.keeper.ensurePlaying()
                let entry = SystemMusicPlayer.shared.queue.currentEntry
                Logger.musicKit.debug("Heartbeat tick: currentEntry=\(entry?.id ?? "nil", privacy: .public) status=\(String(describing: SystemMusicPlayer.shared.state.playbackStatus), privacy: .public)")
                await self.publishCurrent()
            }
        }
    }

    // MARK: - Observation

    private func observe() {
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
            let resolvedArtist: String?
            switch item {
            case .song(let song):
                resolvedArtist = (try? await song.with([.artists]))?.artists?.first?.name
            case .musicVideo(let video):
                resolvedArtist = (try? await video.with([.artists]))?.artists?.first?.name
            @unknown default:
                resolvedArtist = nil
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
