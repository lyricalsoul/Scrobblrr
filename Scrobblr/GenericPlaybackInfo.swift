//
//  GenericPlaybackInfo.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//
import SwiftUI

struct GenericPlaybackInfo: Codable, Equatable, Identifiable {
    let title: String
    let artist: String
    let album: String?
    
    let durationSeconds: Int
    var elapsedTimeSeconds: Int

    var isPlaying: Bool

    var coverURL: URL? = nil

    var displayName: String {
        "\(artist) - \(title)"
    }

    var id: String {
        "\(artist)\u{1}\(title)\u{1}\(album ?? "")"
    }

    /// copy with title, artist and album taken from `scrobble`, keeping the original timing
    func withMetadata(from scrobble: Scrobble) -> GenericPlaybackInfo {
        GenericPlaybackInfo(
            title: scrobble.track,
            artist: scrobble.artist,
            album: scrobble.album,
            durationSeconds: durationSeconds,
            elapsedTimeSeconds: elapsedTimeSeconds,
            isPlaying: isPlaying,
            coverURL: coverURL
        )
    }

    func withCoverURL(_ coverURL: URL?) -> GenericPlaybackInfo {
        var copy = self
        copy.coverURL = coverURL
        return copy
    }

    func withPlaying(_ isPlaying: Bool) -> GenericPlaybackInfo {
        var copy = self
        copy.isPlaying = isPlaying
        return copy
    }

    func withElapsedTimeSeconds(_ elapsedTimeSeconds: Int) -> GenericPlaybackInfo {
        var copy = self
        copy.elapsedTimeSeconds = elapsedTimeSeconds
        return copy
    }

    func adjustedForRelayDrift(since updatedAt: Date, now: Date = Date()) -> GenericPlaybackInfo? {
        guard isPlaying else { return self }
        let drift = max(0, Int(now.timeIntervalSince(updatedAt).rounded()))
        let adjusted = elapsedTimeSeconds + drift
        if durationSeconds > 0, adjusted >= durationSeconds { return nil }
        return withElapsedTimeSeconds(adjusted)
    }
}
