//
//  GenericPlaybackInfo.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//
import SwiftUI

struct GenericPlaybackInfo : Equatable {
    let title: String
    let artist: String
    let album: String?
    
    let durationSeconds: Int
    let elapsedTimeSeconds: Int

    let isPlaying: Bool

    var displayName: String {
        "\(artist) - \(title)"
    }

    /// "Artist • Album", subtitle on the player
    var subtitle: String {
        "\(artist) • \(album ?? "Unknown Album")"
    }

    var id: String {
        "\(artist)\u{1}\(title)\u{1}\(album ?? "")"
    }

    /// A copy of this playback state with title/artist/album replaced by the
    /// corrected metadata from `scrobble`, keeping the original timing.
    func withMetadata(from scrobble: Scrobble) -> GenericPlaybackInfo {
        GenericPlaybackInfo(
            title: scrobble.track,
            artist: scrobble.artist,
            album: scrobble.album,
            durationSeconds: durationSeconds,
            elapsedTimeSeconds: elapsedTimeSeconds,
            isPlaying: isPlaying
        )
    }

    static func == (lhs: GenericPlaybackInfo, rhs: GenericPlaybackInfo) -> Bool {
        lhs.displayName == rhs.displayName && lhs.album == rhs.album
    }
}
