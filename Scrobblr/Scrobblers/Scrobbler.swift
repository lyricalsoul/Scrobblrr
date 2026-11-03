//
//  Scrobbler.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//
//  Defines a scrobbling interface (lfm, musicbrainz, etc etc)

import Foundation

nonisolated struct Scrobble: Sendable, Codable, Equatable {
    let artist: String
    let track: String
    let album: String?
    let durationSeconds: Int?
    let timestamp: Date
}

enum ScrobblerError: Error {
    /// the service has no stored session or credentials yet
    case notAuthenticated
}

/// a destination for now playing updates and scrobbles, e.g. last.fm
protocol Scrobbable {
    /// stable user-facing name, e.g. "Last.fm"
    var name: String { get }

    var isAuthenticated: Bool { get }
    
    /// announce the current track (ephemeral, no timestamp used)
    func updateNowPlaying(_ scrobble: Scrobble) async throws

    func scrobble(_ scrobble: Scrobble) async throws
}
