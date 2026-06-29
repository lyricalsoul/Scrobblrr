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
    /// The currently playing track
    var trackInfo: GenericPlaybackInfo? { engine.current }

    /// Whether the user has granted MusicKit access
    private(set) var isAuthorized = false

    @ObservationIgnored let engine: ScrobbleEngine
    @ObservationIgnored private let keeper = SilentAudioKeeper()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    @ObservationIgnored private var currentSongID: MusicItemID?
    @ObservationIgnored private var currentArtwork: UIImage?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?

    private static let heartbeatInterval: Duration = .seconds(15)

    init(manager: ScrobblerManager, settings: Settings) {
        engine = ScrobbleEngine(manager: manager, settings: settings)
    }

    deinit {
        heartbeatTask?.cancel()
        artworkTask?.cancel()
    }

    /// Requests MusicKit access, starts the background audio keeper, and begins
    /// observing the system player
    func start() async {
        let status = await MusicAuthorization.request()
        isAuthorized = (status == .authorized)
        guard isAuthorized else {
            Logger.auth.error("MusicKit authorization denied: \(String(describing: status), privacy: .public)")
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
            engine.update(nil)
            currentSongID = nil
            currentArtwork = nil
            artworkTask?.cancel()
            return
        }

        // reset artwork and kick off a fresh download
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

    // TODO: use a library for this
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
            // force UI update w new artwork
            self.publishCurrent()
        }
    }
}
#endif
