//
//  MediaModel (macOS).swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//

#if os(macOS)
import MediaRemoteAdapter
import SwiftData
import SwiftUI
import os

@Observable
@MainActor
final class MediaModel {
    let manager: ScrobblerManager

    @ObservationIgnored private let mediaController = MediaController()

    init(manager: ScrobblerManager, settings: Settings, modelContainer: ModelContainer) {
        self.manager = manager

        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            guard let self else { return }
            guard let payload = trackInfo?.payload, let title = payload.title, let artist = payload.artist else {
                self.manager.update(nil)
                return
            }
            
            guard payload.bundleIdentifier == "com.apple.Music" else { return }

            let info = GenericPlaybackInfo(
                title: title,
                artist: artist,
                album: payload.album,
                durationSeconds: Int((payload.durationMicros ?? 0) / 1_000_000),
                elapsedTimeSeconds: Int(payload.currentElapsedTime ?? (payload.elapsedTimeMicros ?? 0) / 1_000_000),
                isPlaying: payload.isPlaying ?? false
            )
            self.manager.update(info)
        }

        mediaController.onListenerTerminated = { [weak self] in
            self?.manager.update(nil)
        }

        mediaController.startListening()
    }

    deinit {
        mediaController.stopListening()
    }
}
#endif
