//
//  LastFMScrobbler.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//

import Foundation
import Observation
import os


// makes it easier to render out the stuff in WeekView
struct SimpleTopData {
    let id: String?
    let name: String
    let artist: String?
    let scrobbles: UInt
    let coverURL: URL?

    var listKey: String { "\(id ?? "")\u{0}\(artist ?? "")\u{0}\(name)" }
}

enum LastFMEntity: String, CaseIterable, Identifiable {
    case artist = "Artist"
    case album = "Album"
    case track = "Track"
    
    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .artist: "Artist"
        case .album:  "Album"
        case .track:  "Track"
        }
    }

    var apiValue: String { rawValue.lowercased() }
}

enum LastFMPeriod: String, CaseIterable, Identifiable {
    case week = "Last 7 Days"
    case month = "Last 30 Days"
    case threeMonths = "Last 90 Days"
    case sixMonths = "Last 180 Days"
    case twelveMonths = "Last Year"
    case allTime = "All Time"

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .week:         "Last 7 Days"
        case .month:        "Last 30 Days"
        case .threeMonths:  "Last 90 Days"
        case .sixMonths:    "Last 180 Days"
        case .twelveMonths: "Last Year"
        case .allTime:      "All Time"
        }
    }

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

struct CredentialStore {
    var get: @MainActor (String) -> String?
    var set: @MainActor (String?, String) -> Void
    static let keychain = CredentialStore(get: { Keychain.get($0) }, set: { Keychain.set($0, for: $1) })
}

@Observable
final class LastFMScrobbler: Scrobbable {
    let name = "Last.fm"

    @ObservationIgnored private let transport: any LastFMTransport
    @ObservationIgnored private let epistolares: any EpistolaresAPI
    @ObservationIgnored private let credentials: CredentialStore
    @ObservationIgnored private var presenceTask: Task<Void, Never>?

    private(set) var username: String? {
        didSet { credentials.set(username, Self.usernameKeychainAccount) }
    }

    /// cross-device presence push key, see `Epistolares.registerPresence`
    private(set) var pushKey: String? {
        didSet { credentials.set(pushKey, Self.pushKeyKeychainAccount) }
    }

    private var sessionKey: String? {
        didSet { credentials.set(sessionKey, Self.sessionKeyKeychainAccount) }
    }

    private var hasRecentlyLaunchedApp = true

    private static let sessionKeyKeychainAccount = "lastfm.sessionKey"
    private static let pushKeyKeychainAccount = "lastfm.presencePushKey"
    private static let usernameKeychainAccount = "lastfm.username"

    var isAuthenticated: Bool { sessionKey != nil }

    init(transport: any LastFMTransport = LiveLastFMTransport(), epistolares: any EpistolaresAPI = Epistolares(), credentials: CredentialStore = .keychain) {
        self.transport = transport
        self.epistolares = epistolares
        self.credentials = credentials
        sessionKey = credentials.get(Self.sessionKeyKeychainAccount)
        pushKey = credentials.get(Self.pushKeyKeychainAccount)
        username = credentials.get(Self.usernameKeychainAccount)

        if sessionKey != nil, pushKey == nil {
            registerPresenceIfNeeded()
        }
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
        let session = try await transport.session(token: token)
        sessionKey = session.key
        username = session.name
        Logger.auth.info("Signed in to Last.fm as \(session.name, privacy: .public)")
        registerPresenceIfNeeded()
    }

    func signOut() {
        Logger.auth.info("Signing out of Last.fm")
        sessionKey = nil
        username = nil
        pushKey = nil
    }

    // MARK: - Cross-device presence

    private func registerPresenceIfNeeded() {
        guard let sessionKey else { return }
        Task {
            do {
                let registration = try await epistolares.registerPresence(sessionKey: sessionKey)
                pushKey = registration.pushKey
                Logger.scrobbler.info("Registered cross-device presence for \(registration.username, privacy: .public)")
            } catch {
                Logger.scrobbler.error("Presence registration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// pushes the current playback state for cross-device presence relay, superseding any push still in flight
    func pushPresence(_ info: GenericPlaybackInfo?, device: String) {
        guard let username, let pushKey else { return }
        presenceTask?.cancel()
        presenceTask = Task { [epistolares] in
            guard !Task.isCancelled else { return }
            do {
                try await epistolares.pushPresence(username: username, pushKey: pushKey, device: device, info: info)
            } catch {
                Logger.scrobbler.error("Presence push failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Scrobbable

    func updateNowPlaying(_ scrobble: Scrobble) async throws {
        guard let sessionKey else { throw ScrobblerError.notAuthenticated }
        try await transport.updateNowPlaying(scrobble, sessionKey: sessionKey)
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

        try await transport.scrobble(scrobble, sessionKey: sessionKey)
    }

    private func alreadyScrobbled(_ scrobble: Scrobble) async -> Bool {
        guard let username else { return false }

        do {
            return Self.isDuplicate(try await epistolares.recentTracks(username: username, limit: 2).items, of: scrobble)
        } catch {
            Logger.scrobbler.error("Recent-tracks dedupe check failed: \(error.localizedDescription, privacy: .public). Will ignore")
            return false
        }
    }

    static func isDuplicate(_ items: [EpistolaresRecentTracks.Item], of scrobble: Scrobble, tolerance: TimeInterval = 120) -> Bool {
        items.contains { item in
            guard !item.nowPlaying, let playedAt = item.playedAt else { return false }
            return item.track.name.caseInsensitiveCompare(scrobble.track) == .orderedSame
                && item.artist.name.caseInsensitiveCompare(scrobble.artist) == .orderedSame
                && abs(playedAt.timeIntervalSince(scrobble.timestamp)) <= tolerance
        }
    }
}
