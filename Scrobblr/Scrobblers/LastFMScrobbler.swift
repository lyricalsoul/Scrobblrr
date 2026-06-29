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

/// Scrobbles to Last.fm using the desktop authentication flow:
/// `getToken` → user authorizes in the browser → `getSession` returns a
/// long-lived session key that signs all subsequent scrobbles.
@Observable
final class LastFMScrobbler: Scrobbable {
    let name = "Last.fm"

    @ObservationIgnored
    private let client = LastFM(apiKey: Constants.lfmApiKey, apiSecret: Constants.lfmApiSecret)

    /// The authenticated Last.fm username, if signed in.
    private(set) var username: String?

    /// True once a sign-in has been started and is waiting for the user to
    /// approve in the browser before `finishAuthentication()` can complete it.
    private(set) var isAwaitingAuthorization = false

    // The session key is a credential (grants write access to the account), so
    // it lives in the Keychain. The username is not sensitive — UserDefaults.
    private var sessionKey: String? {
        didSet { Keychain.set(sessionKey, for: Self.sessionKeyKeychainAccount) }
    }
    
    private var hasRecentlyLaunchedApp = true

    @ObservationIgnored
    private var pendingToken: String?

    private static let sessionKeyKeychainAccount = "lastfm.sessionKey"
    private static let usernameDefaultsKey = "lastfm.username"

    var isAuthenticated: Bool { sessionKey != nil }

    init() {
        // didSet does not fire during init, so this load won't re-write the Keychain.
        sessionKey = Keychain.get(Self.sessionKeyKeychainAccount)
        username = UserDefaults.standard.string(forKey: Self.usernameDefaultsKey)
    }

    // MARK: - Desktop authentication

    /// Step 1: request a token and return the URL the user must open to
    /// authorize it. Open the URL, let the user approve, then call
    /// `finishAuthentication()`.
    func beginAuthentication() async throws -> URL {
        Logger.auth.info("Requesting Last.fm auth token")
        let token = try await client.Auth.getToken()
        pendingToken = token
        isAwaitingAuthorization = true
        Logger.auth.info("Got auth token; awaiting user authorization in browser")

        var components = URLComponents(string: "https://www.last.fm/api/auth/")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Constants.lfmApiKey),
            URLQueryItem(name: "token", value: token),
        ]
        return components.url!
    }

    /// Step 2: exchange the authorized token for a session key and store it.
    func finishAuthentication() async throws {
        guard let pendingToken else { throw ScrobblerError.notAuthenticated }
        try await completeAuthentication(token: pendingToken)
    }

    // MARK: - Web authentication (iOS / ASWebAuthenticationSession)

    /// The URL to present in a web-auth session. After the user authorizes,
    /// Last.fm redirects to `<callbackScheme>://auth?token=…`; hand that token
    /// to `completeAuthentication(token:)`.
    func authorizationURL(callbackScheme: String) -> URL {
        isAwaitingAuthorization = true
        var components = URLComponents(string: "https://www.last.fm/api/auth/")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Constants.lfmApiKey),
            URLQueryItem(name: "cb", value: "\(callbackScheme)://auth"),
        ]
        return components.url!
    }

    /// Exchanges an authorized token for a session key and stores it. Used by
    /// both the desktop (`finishAuthentication`) and web (callback) flows.
    func completeAuthentication(token: String) async throws {
        let session = try await client.Auth.getSession(token: token)
        sessionKey = session.key
        username = session.name
        UserDefaults.standard.set(session.name, forKey: Self.usernameDefaultsKey)

        pendingToken = nil
        isAwaitingAuthorization = false
        Logger.auth.info("Signed in to Last.fm as \(session.name, privacy: .public)")
    }

    func signOut() {
        Logger.auth.info("Signing out of Last.fm")
        sessionKey = nil
        username = nil
        pendingToken = nil
        isAwaitingAuthorization = false
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

    /// Whether this play already exists in the user's recent scrobbles — used to
    /// avoid re-scrobbling the same play after a relaunch while it's still going.
    /// Matches artist + track with a start time close to ours (both reference the
    /// play's start timestamp, so a relaunch mid-track lines up).
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
            // If we can't check (e.g. offline), don't block the scrobble.
            Logger.scrobbler.error("Recent-tracks dedupe check failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
