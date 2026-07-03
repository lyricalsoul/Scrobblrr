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


// makes it easier to render out the stuff in WeekView
struct SimpleTopData {
    let id: String?
    let name: String
    let artist: String?
    let scrobbles: UInt
    let coverURL: URL?
}

enum LastFMEntity: String, CaseIterable, Identifiable {
    case artist = "Artist"
    case album = "Album"
    case track = "Track"
    
    var id: Self { self }
    
    var apiValue: String {
        switch self {
        case .artist: "artist"
        case .album:  "album"
        case .track:  "track"
        }
    }
}

enum LastFMPeriod: String, CaseIterable, Identifiable {
    case week = "Last 7 Days"
    case month = "Last 30 Days"
    case threeMonths = "Last 90 Days"
    case sixMonths = "Last 180 Days"
    case twelveMonths = "Last Year"
    case allTime = "All Time"
    
    var id: Self { self }

    var apiValue: String {
        switch self {
        case .week:         "7day"
        case .month:        "1month"
        case .threeMonths:  "3month"
        case .sixMonths:    "6month"
        case .twelveMonths: "12month"
        case .allTime:      "overall"
        }
    }
}

@Observable
final class LastFMScrobbler: Scrobbable {
    let name = "Last.fm"

    @ObservationIgnored
    private let client = LastFM(apiKey: Constants.lfmApiKey, apiSecret: Constants.lfmApiSecret)
    @ObservationIgnored
    private let epistolares = Epistolares()

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
            duration: scrobble.durationSeconds.flatMap { UInt(exactly: $0) }
        )

        _ = try await client.Track.updateNowPlaying(params: params, sessionKey: sessionKey)
    }

    func scrobble(_ scrobble: Scrobble) async throws {
        guard let sessionKey else { throw ScrobblerError.notAuthenticated }

        if hasRecentlyLaunchedApp {
            if await alreadyScrobbled(scrobble) {
                Logger.scrobbler.info("Skipping duplicate (already on Last.fm): \(scrobble.artist, privacy: .public): \(scrobble.track, privacy: .public)")
                
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
            duration: scrobble.durationSeconds.flatMap { UInt(exactly: $0) }
        ))

        _ = try await client.Track.scrobble(params: params, sessionKey: sessionKey)
    }

    private func alreadyScrobbled(_ scrobble: Scrobble) async -> Bool {
        guard let username else { return false }

        do {
            let page = try await epistolares.recentTracks(username: username, limit: 2)
            let tolerance: TimeInterval = 120

            return page.items.contains { item in
                guard !item.nowPlaying, let playedAt = item.playedAt else { return false }
                return item.track.name.caseInsensitiveCompare(scrobble.track) == .orderedSame
                    && item.artist.name.caseInsensitiveCompare(scrobble.artist) == .orderedSame
                    && abs(playedAt.timeIntervalSince(scrobble.timestamp)) <= tolerance
            }
        } catch {
            Logger.scrobbler.error("Recent-tracks dedupe check failed: \(error.localizedDescription, privacy: .public). Will ignore")
            return false
        }
    }
}
