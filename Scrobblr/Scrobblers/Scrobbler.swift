//
//  Scrobbler.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//
//  Defines a scrobbling interface (lfm, musicbrainz, etc etc)

import Foundation

/// A finished (or in-progress) play, ready to be submitted to a scrobbling
/// service. Unlike `GenericPlaybackInfo` this carries only the corrected,
/// service-bound metadata plus a fixed start `timestamp`, and is `Codable` so
/// it can be queued for offline retry.
struct Scrobble: Sendable, Codable, Equatable {
    let artist: String
    let track: String
    let album: String?
    let albumArtist: String?
    let durationSeconds: Int?
    /// When playback of this track started.
    let timestamp: Date
}

enum ScrobblerError: Error {
    /// The service has no stored session/credentials yet.
    case notAuthenticated
}

/// A destination that can receive "now playing" updates and scrobbles,
/// e.g. Last.fm or (later) ListenBrainz.
protocol Scrobbable {
    /// Stable, user-facing name, e.g. "Last.fm".
    var name: String { get }

    /// Whether the service is configured and ready to submit.
    var isAuthenticated: Bool { get }

    /// Announce the currently playing track (ephemeral, no timestamp used).
    func updateNowPlaying(_ scrobble: Scrobble) async throws

    /// Submit a committed play.
    func scrobble(_ scrobble: Scrobble) async throws
}
