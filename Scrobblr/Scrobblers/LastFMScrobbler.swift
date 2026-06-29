//
//  LastFMScrobbler.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//

import Foundation
import Observation
import LastFM
import os

@Observable
final class LastFMScrobbler: Scrobbable {
    let name = "Last.fm"

    @ObservationIgnored
    private let client = LastFM(apiKey: Constants.lfmApiKey, apiSecret: Constants.lfmApiSecret)

    private(set) var username: String?

    private var sessionKey: String? {
        didSet { Keychain.set(sessionKey, for: Self.sessionKeyKeychainAccount) }
    }
    
    private var hasRecentlyLaunchedApp = true

    private static let sessionKeyKeychainAccount = "lastfm.sessionKey"
    private static let usernameDefaultsKey = "lastfm.username"

    var isAuthenticated: Bool { sessionKey != nil }

    init() {
        sessionKey = Keychain.get(Self.sessionKeyKeychainAccount)
        username = UserDefaults.standard.string(forKey: Self.usernameDefaultsKey)
    }

    // MARK: - Web authentication

    func authorizationURL(callbackScheme: String) -> URL {
        var components = URLComponents(string: "https://www.last.fm/api/auth/")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Constants.lfmApiKey),
            URLQueryItem(name: "cb", value: "\(callbackScheme)://auth"),
        ]
        return components.url!
    }

    func completeAuthentication(token: String) async throws {
        let session = try await client.Auth.getSession(token: token)
        sessionKey = session.key
        username = session.name
        UserDefaults.standard.set(session.name, forKey: Self.usernameDefaultsKey)
        Logger.auth.info("Signed in to Last.fm as \(session.name, privacy: .public)")
    }

    func signOut() {
        Logger.auth.info("Signing out of Last.fm")
        sessionKey = nil
        username = nil
        UserDefaults.standard.removeObject(forKey: Self.usernameDefaultsKey)
    }

    // MARK: - Scrobbable

    func updateNowPlaying(_ scrobble: Scrobble) async throws {
        guard let sessionKey else { throw ScrobblerError.notAuthenticated }

        let params = TrackNowPlayingParams(
            artist: scrobble.artist,
            track: scrobble.track,
            album: scrobble.album,
            albumArtist: scrobble.albumArtist,
            duration: scrobble.durationSeconds.flatMap { UInt(exactly: $0) }
        )

        _ = try await client.Track.updateNowPlaying(params: params, sessionKey: sessionKey)
    }

    func scrobble(_ scrobble: Scrobble) async throws {
        guard let sessionKey else { throw ScrobblerError.notAuthenticated }

        if hasRecentlyLaunchedApp {
            if await alreadyScrobbled(scrobble) {
                Logger.scrobbler.info("Skipping duplicate (already on Last.fm): \(scrobble.artist, privacy: .public) — \(scrobble.track, privacy: .public)")
                
                return
            }
            hasRecentlyLaunchedApp = false
        }

        var params = ScrobbleParams()
        try params.addItem(item: ScrobbleParamItem(
            artist: scrobble.artist,
            track: scrobble.track,
            date: scrobble.timestamp,
            album: scrobble.album,
            albumArtist: scrobble.albumArtist,
            duration: scrobble.durationSeconds.flatMap { UInt(exactly: $0) }
        ))

        _ = try await client.Track.scrobble(params: params, sessionKey: sessionKey)
    }

    private func alreadyScrobbled(_ scrobble: Scrobble) async -> Bool {
        guard let username else { return false }

        do {
            let params = RecentTracksParams(user: username, limit: 2)
            let page = try await client.User.getRecentTracks(params: params)
            let tolerance: TimeInterval = 120

            return page.items.contains { item in
                guard !item.nowPlaying, let date = item.date else { return false }
                return item.name.caseInsensitiveCompare(scrobble.track) == .orderedSame
                    && item.artist.name.caseInsensitiveCompare(scrobble.artist) == .orderedSame
                    && abs(date.timeIntervalSince(scrobble.timestamp)) <= tolerance
            }
        } catch {
            Logger.scrobbler.error("Recent-tracks dedupe check failed: \(error.localizedDescription, privacy: .public). Will ignore")
            return false
        }
    }
}
