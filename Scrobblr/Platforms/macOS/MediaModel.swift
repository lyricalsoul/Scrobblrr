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

/// macOS playback source: reads system-wide "now playing" via MediaRemote and
/// feeds it into the shared ``ScrobbleEngine``.
@MainActor
final class MediaModel {
    let engine: ScrobbleEngine

    /// The currently playing track, for the UI.
    var trackInfo: GenericPlaybackInfo? { engine.current }

    private let mediaController = MediaController()

    init(manager: ScrobblerManager, settings: Settings) {
        engine = ScrobbleEngine(manager: manager, settings: settings)

        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            guard let self else { return }
            guard let payload = trackInfo?.payload else {
                self.engine.update(nil)
                return
            }

            let info = GenericPlaybackInfo(
                title: payload.title!,
                artist: payload.artist!,
                album: payload.album,
                durationSeconds: Int(payload.durationMicros! / 1000000),
                elapsedTimeSeconds: Int(payload.elapsedTimeMicros! / 1000000),
                isPlaying: payload.isPlaying ?? false,
                image: payload.artwork,
            )
            self.engine.update(info)
        }

        mediaController.onListenerTerminated = { [weak self] in
            self?.engine.update(nil)
        }

        mediaController.startListening()
    }

    deinit {
        mediaController.stopListening()
    }
}
#endif
