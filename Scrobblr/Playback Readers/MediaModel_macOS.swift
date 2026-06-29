//
//  MediaModel (macOS).swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//

#if os(macOS)
import MediaRemoteAdapter
import SwiftUI
import os

@Observable
@MainActor
final class MediaModel {
    let manager: ScrobblerManager

    /// The current cover art, tracked separately from the metadata: the player
    /// often delivers a track's metadata before its artwork, so the cover fades
    /// in once it arrives rather than blocking the rest of the UI. Used for
    /// the backdrop, as the actual cover is fetched from last.fm for better
    /// quality.
    private(set) var artwork: NSImage?

    @ObservationIgnored private let mediaController = MediaController()

    init(manager: ScrobblerManager, settings: Settings) {
        self.manager = manager
        
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            guard let self else { return }
            guard let payload = trackInfo?.payload else {
                self.clear()
                return
            }

            let info = GenericPlaybackInfo(
                title: payload.title!,
                artist: payload.artist!,
                album: payload.album,
                durationSeconds: Int(payload.durationMicros! / 1000000),
                elapsedTimeSeconds: Int(payload.elapsedTimeMicros! / 1000000),
                isPlaying: payload.isPlaying ?? false
            )
            self.manager.update(info)
            self.updateArtwork(payload.artwork)
        }

        mediaController.onListenerTerminated = { [weak self] in
            self?.clear()
        }

        mediaController.startListening()
    }

    /// Adopts artwork for the current track.
    private func updateArtwork(_ image: NSImage?) {
        artwork = image
    }

    private func clear() {
        self.manager.update(nil)
        artwork = nil
    }

    deinit {
        mediaController.stopListening()
    }
}
#endif
