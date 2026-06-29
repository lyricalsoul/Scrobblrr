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
    /// The current MusicKit authorization status. Seeded synchronously from the
    /// system's cached status so the UI never flashes the "access needed" gate
    /// before `start()` has had a chance to ask.
    private(set) var authorizationStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus

    /// Whether the user has granted MusicKit access
    var isAuthorized: Bool { authorizationStatus == .authorized }

    /// `true` only when the system has refused access
    var accessDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }

    @ObservationIgnored private let keeper = SilentAudioKeeper()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    @ObservationIgnored private var currentSongID: MusicItemID?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?

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

        keeper.start()
        observe()
        startHeartbeat()
        publishCurrent()
    }

    // MARK: - Heartbeat

    // TODO: is this the right thing?
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard !Task.isCancelled, let self else { return }
                // Pick up a revocation that happened while we were running so the
                // UI can switch to the access gate cleanly instead of going stale.
                self.authorizationStatus = MusicAuthorization.currentStatus
                self.keeper.ensurePlaying()
                self.publishCurrent()
            }
        }
    }

    // MARK: - Observation

    private func observe() {
        let player = SystemMusicPlayer.shared

        player.queue.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.publishCurrent() }
            }
            .store(in: &cancellables)

        player.state.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.publishCurrent() }
            }
            .store(in: &cancellables)
    }

    private func publishCurrent() {
        let player = SystemMusicPlayer.shared

        guard case let .song(song)? = player.queue.currentEntry?.item else {
            manager.update(nil)
            currentSongID = nil
            return
        }

        // reset artwork and kick off a fresh download
        if song.id != currentSongID {
            currentSongID = song.id
        }

        let info = GenericPlaybackInfo(
            title: song.title,
            artist: song.artistName,
            album: song.albumTitle,
            durationSeconds: Int(song.duration ?? 0),
            elapsedTimeSeconds: Int(player.playbackTime),
            isPlaying: player.state.playbackStatus == .playing
        )
        manager.update(info)
    }
}
#endif
