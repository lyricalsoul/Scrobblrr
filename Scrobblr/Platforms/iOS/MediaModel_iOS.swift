//
//  MediaModel (iOS).swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//
//  iOS playback source: observes Apple Music via MusicKit's SystemMusicPlayer
//  and feeds it into the shared ``ScrobbleEngine``. A silent background audio
//  session (``SilentAudioKeeper``) keeps the app alive to keep scrobbling.
//
//  NOTE: MusicKit exposes the system player only as Combine `ObservableObject`s
//  (no async/Notification equivalent), so Combine is used here deliberately —
//  it's the only observation API available — and kept confined to this file.

#if os(iOS)
import MusicKit
import Combine
import UIKit
import os

@Observable
@MainActor
final class MediaModel {
    /// The currently playing track, for the UI.
    var trackInfo: GenericPlaybackInfo? { engine.current }

    /// Whether the user has granted MusicKit access. Drives the UI gate.
    private(set) var isAuthorized = false

    @ObservationIgnored let engine: ScrobbleEngine
    @ObservationIgnored private let keeper = SilentAudioKeeper()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    // Artwork arrives asynchronously (MusicKit gives a URL we must download),
    // so it's tracked per-song and re-published once loaded.
    @ObservationIgnored private var currentSongID: MusicItemID?
    @ObservationIgnored private var currentArtwork: UIImage?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?

    init(manager: ScrobblerManager, settings: Settings) {
        engine = ScrobbleEngine(manager: manager, settings: settings)
    }

    /// Requests MusicKit access, starts the background audio keeper, and begins
    /// observing the system player. Safe to call once on launch.
    func start() async {
        let status = await MusicAuthorization.request()
        isAuthorized = (status == .authorized)
        guard isAuthorized else {
            Logger.auth.error("MusicKit authorization denied: \(String(describing: status), privacy: .public)")
            return
        }

        keeper.start()
        observe()
        publishCurrent()
    }

    // MARK: - Observation

    private func observe() {
        let player = SystemMusicPlayer.shared

        // Track / queue changes.
        player.queue.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.publishCurrent() }
            }
            .store(in: &cancellables)

        // Play / pause / stop changes.
        player.state.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.publishCurrent() }
            }
            .store(in: &cancellables)
    }

    /// Snapshots the current system-player state and feeds it to the engine.
    private func publishCurrent() {
        let player = SystemMusicPlayer.shared

        guard case let .song(song)? = player.queue.currentEntry?.item else {
            engine.update(nil)
            currentSongID = nil
            currentArtwork = nil
            artworkTask?.cancel()
            return
        }

        // A newly-seen song: reset artwork and kick off a fresh download.
        if song.id != currentSongID {
            currentSongID = song.id
            currentArtwork = nil
            loadArtwork(for: song)
        }

        let info = GenericPlaybackInfo(
            title: song.title,
            artist: song.artistName,
            album: song.albumTitle,
            durationSeconds: Int(song.duration ?? 0),
            elapsedTimeSeconds: Int(player.playbackTime),
            isPlaying: player.state.playbackStatus == .playing,
            image: currentArtwork
        )
        engine.update(info)
    }

    // MARK: - Artwork

    private func loadArtwork(for song: Song) {
        artworkTask?.cancel()
        guard let artwork = song.artwork,
              let url = artwork.url(width: 600, height: 600) else { return }

        let songID = song.id
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            guard !Task.isCancelled, let self, self.currentSongID == songID else { return }
            self.currentArtwork = image
            // Re-publish so the engine/UI pick up the now-available artwork.
            self.publishCurrent()
        }
    }
}
#endif
