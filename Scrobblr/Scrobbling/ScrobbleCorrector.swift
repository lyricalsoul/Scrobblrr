//
//  ScrobbleCorrector.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Foundation
import SwiftData
import os

struct ScrobbleCorrector {
    let context: ModelContext
    let settings: Settings
    let fixArtist: ((String) async -> CorrectedEntity)?

    /// `date` is when the track was observed, so a slow correction doesn't shift the timestamp
    func corrected(from track: GenericPlaybackInfo, at date: Date = Date()) async -> Scrobble? {
        guard let artist = scrobbleable(await correctedArtist(track.artist), original: track.artist),
              let title = scrobbleable(CorrectionRules.applyCorrections(for: track.title, type: .track, album: track.album, artist: track.artist, in: context), original: track.title)
        else { return nil }

        var album = track.album
        if let originalAlbum = track.album {
            guard let correctedAlbum = scrobbleable(CorrectionRules.applyCorrections(for: originalAlbum, type: .album, artist: track.artist, in: context), original: originalAlbum)
            else { return nil }
            album = correctedAlbum
        }

        return Scrobble(
            artist: artist,
            track: title,
            album: album,
            durationSeconds: track.durationSeconds,
            timestamp: date.addingTimeInterval(-Double(track.elapsedTimeSeconds))
        )
    }

    private func correctedArtist(_ artist: String) async -> CorrectedEntity {
        if settings.useArtistFix, let fixArtist { return await fixArtist(artist) }
        return CorrectionRules.applyCorrections(for: artist, type: .artist, in: context)
    }

    private func scrobbleable(_ correction: CorrectedEntity, original: String) -> String? {
        guard correction.shouldScrobble else {
            Logger.scrobbler.info("Skipping \(original, privacy: .public), reason: \(correction.reason ?? "ignored by rule", privacy: .public)")
            return nil
        }
        return correction.title
    }
}
