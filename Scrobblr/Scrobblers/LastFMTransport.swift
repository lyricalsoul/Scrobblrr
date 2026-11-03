//
//  LastFMTransport.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Foundation
import LastFM

nonisolated protocol LastFMTransport: Sendable {
    func session(token: String) async throws -> (key: String, name: String)
    func updateNowPlaying(_ scrobble: Scrobble, sessionKey: String) async throws
    func scrobble(_ scrobble: Scrobble, sessionKey: String) async throws
}

nonisolated struct LiveLastFMTransport: LastFMTransport, @unchecked Sendable {
    private let client: LastFM

    init() {
        client = LastFM(apiKey: Constants.lfmApiKey, apiSecret: Constants.lfmApiSecret)
    }

    func session(token: String) async throws -> (key: String, name: String) {
        let session = try await client.Auth.getSession(token: token)
        return (session.key, session.name)
    }

    func updateNowPlaying(_ scrobble: Scrobble, sessionKey: String) async throws {
        let params = TrackNowPlayingParams(artist: scrobble.artist, track: scrobble.track, album: scrobble.album, duration: scrobble.durationSeconds.flatMap { UInt(exactly: $0) })
        _ = try await client.Track.updateNowPlaying(params: params, sessionKey: sessionKey)
    }

    func scrobble(_ scrobble: Scrobble, sessionKey: String) async throws {
        var params = ScrobbleParams()
        try params.addItem(item: ScrobbleParamItem(
            artist: scrobble.artist,
            track: scrobble.track,
            date: scrobble.timestamp,
            album: scrobble.album,
            duration: scrobble.durationSeconds.flatMap { UInt(exactly: $0) }
        ))
        _ = try await client.Track.scrobble(params: params, sessionKey: sessionKey)
    }
}
