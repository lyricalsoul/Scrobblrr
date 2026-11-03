//
//  Epistolares.swift
//  Scrobblr
//
//  Created by Renan Martins on 7/2/26.
//

import Foundation
import os

struct Cover: Decodable {
    let defaultURL: String?
    let template: String?

    func url(size: Int = Constants.epistolaresCoverSize) -> URL? {
        if let template {
            let sized = template.replacingOccurrences(of: "{w}x{h}", with: "\(size)x\(size)")
            if let url = URL(string: sized) { return url }
        }
        return defaultURL.flatMap { URL(string: $0) }
    }
}

struct EpistolaresUserScrobbles: Decodable {
    let playCount: Int
}

struct EpistolaresBio: Decodable {
    let summary: String?
    let content: String?
    let license: String?
}

struct EpistolaresTrackInfo: Decodable {
    let track: Track
    let album: Album?
    let artist: Artist

    struct Track: Decodable {
        let id: String?
        let name: String
        let cover: Cover?
        let listeners: Int
        let scrobbles: Int
        let tags: [String]
        let userScrobbles: EpistolaresUserScrobbles?
    }

    struct Album: Decodable {
        let id: String?
        let name: String
        let cover: Cover?
        let listeners: Int
        let scrobbles: Int
        let userScrobbles: EpistolaresUserScrobbles?
    }

    struct Artist: Decodable {
        let id: String?
        let name: String
        let cover: Cover?
        let listeners: Int
        let scrobbles: Int
        let userScrobbles: EpistolaresUserScrobbles?
    }
}

struct EpistolaresArtistInfo: Decodable {
    let id: String?
    let name: String
    let listeners: Int
    let scrobbles: Int
    let userScrobbles: EpistolaresUserScrobbles?
    let url: String?
    let cover: Cover?
    let tags: [String]
    let bio: EpistolaresBio?
    let similarArtists: [SimilarArtist]

    struct SimilarArtist: Decodable, Identifiable {
        let id: String
        let name: String
        let cover: Cover?
    }
}

struct EpistolaresAlbumInfo: Decodable {
    let id: String?
    let name: String
    let artist: String
    let listeners: Int
    let scrobbles: Int
   
    let userScrobbles: EpistolaresUserScrobbles?
    let url: String?
    let cover: Cover?
    let tags: [String]
    let bio: EpistolaresBio?
    let tracks: [Track]

    struct Track: Decodable, Identifiable {
        let id: String
        let name: String
        let rank: Int
    }
}

struct EpistolaresRecentTracks: Decodable {
    let page: Int
    let totalPages: Int
    let total: Int
    let items: [Item]

    struct Item: Decodable {
        let nowPlaying: Bool
        let playedAt: Date?
        let track: EpistolaresTrackInfo.Track
        let album: EpistolaresTrackInfo.Album?
        let artist: EpistolaresTrackInfo.Artist
    }
}

// MARK: - Cross-device presence

struct RemotePresence: Decodable {
    let device: String
    let info: GenericPlaybackInfo?
    let updatedAt: Date
}

struct PresenceRegistration: Decodable {
    let username: String
    let pushKey: String
}

struct ChartPage: Decodable {
    let items: [ChartItem]
}

struct ChartItem: Decodable {
    let id: String?
    let name: String
    /// `nil` if this is an artist chart
    let artist: String?
    let cover: Cover?
    let playCount: Int
}

struct AllCharts: Decodable {
    let artists: ChartPage
    let albums: ChartPage
    let tracks: ChartPage
}

extension SimpleTopData {
    init(_ item: ChartItem) {
        self.init(
            id: item.id,
            name: item.name,
            artist: item.artist,
            scrobbles: UInt(max(0, item.playCount)),
            coverURL: item.cover?.url()
        )
    }
}

// MARK: - Client

enum EpistolaresError: LocalizedError {
    case badResponse
    case notFound
    case badRequest
    case unauthorized
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse:    "Epistolares returned an unexpected response"
        case .notFound:       "The requested entity wasn't found"
        case .badRequest:     "The request was missing or had invalid parameters"
        case .unauthorized:   "The session key or push key was rejected"
        case .server(let s):  "Epistolares request failed (HTTP \(s))"
        }
    }
}

nonisolated protocol EpistolaresAPI: Sendable {
    func trackInfo(track: String, artist: String, album: String?, username: String?) async throws -> EpistolaresTrackInfo
    func recentTracks(username: String, limit: Int) async throws -> EpistolaresRecentTracks
    func registerPresence(sessionKey: String) async throws -> PresenceRegistration
    func pushPresence(username: String, pushKey: String, device: String, info: GenericPlaybackInfo?) async throws
    func presence(username: String, pushKey: String) async throws -> RemotePresence?
    func invalidateTrackInfoCache()
}

nonisolated final class TrackInfoCache: @unchecked Sendable {
    private let lock = NSLock()
    private let ttl: TimeInterval
    private var entries: [String: (value: EpistolaresTrackInfo, at: Date)] = [:]
    var count: Int { lock.withLock { entries.count } }

    init(ttl: TimeInterval = 300) { self.ttl = ttl }

    func value(for key: String) -> EpistolaresTrackInfo? {
        lock.withLock { entries[key].flatMap { Date().timeIntervalSince($0.at) < ttl ? $0.value : nil } }
    }
    func set(_ value: EpistolaresTrackInfo, for key: String) {
        lock.withLock {
            entries = entries.filter { Date().timeIntervalSince($0.value.at) < ttl }
            entries[key] = (value, Date())
        }
    }
    func removeAll() { lock.withLock { entries = [:] } }
}

nonisolated struct Epistolares: EpistolaresAPI {
    private static let baseURL = Constants.epistolaresBaseURL
    static let sharedCache = TrackInfoCache()

    var session = URLSession.shared
    var cache = Epistolares.sharedCache

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    // MARK: - Methofs

    func trackInfo(track: String, artist: String, album: String? = nil, username: String? = nil) async throws -> EpistolaresTrackInfo {
        let key = [track, artist, album ?? "", username ?? ""].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.joined(separator: "|")
        return try await cached(key) {
            try await get("/track/info", query: Self.query(("track", track), ("artist", artist), ("album", album), ("username", username)))
        }
    }

    func trackInfo(id: String, username: String? = nil) async throws -> EpistolaresTrackInfo {
        try await cached("id|\(id)|\(username ?? "")") {
            try await get("/track/info", query: Self.query(("id", id), ("username", username)))
        }
    }

    func invalidateTrackInfoCache() { cache.removeAll() }

    private func cached(_ key: String, fetch: () async throws -> EpistolaresTrackInfo) async throws -> EpistolaresTrackInfo {
        if let hit = cache.value(for: key) { return hit }
        let result = try await fetch()
        cache.set(result, for: key)
        return result
    }

    func artistInfo(id: String, username: String? = nil) async throws -> EpistolaresArtistInfo {
        try await get("/artist/info", query: Self.query(("id", id), ("username", username)))
    }

    func albumInfo(id: String, username: String? = nil) async throws -> EpistolaresAlbumInfo {
        try await get("/album/info", query: Self.query(("id", id), ("username", username)))
    }

    func userChartsAll(username: String, period: LastFMPeriod, limit: Int = 50) async throws -> AllCharts {
        try await get("/user/charts/all", query: Self.query(("username", username), ("period", period.apiValue), ("limit", String(limit))))
    }

    func recentTracks(username: String, limit: Int = 2) async throws -> EpistolaresRecentTracks {
        try await get("/user/recent-tracks", query: Self.query(("username", username), ("limit", String(limit))))
    }

    // MARK: - Cross-device presence

    func registerPresence(sessionKey: String) async throws -> PresenceRegistration {
        try Self.decoder.decode(PresenceRegistration.self, from: await post("/user/presence/register", body: ["sessionKey": sessionKey]))
    }

    func pushPresence(username: String, pushKey: String, device: String, info: GenericPlaybackInfo?) async throws {
        struct Body: Encodable {
            let device: String
            let info: GenericPlaybackInfo?
            let updatedAt: Date
        }
        try await post(
            "/user/presence/\(username)",
            body: Body(device: device, info: info, updatedAt: Date()),
            headers: ["Authorization": "Bearer \(pushKey)"]
        )
    }

    func presence(username: String, pushKey: String) async throws -> RemotePresence? {
        do {
            return try await get("/user/presence/\(username)", query: [], headers: ["Authorization": "Bearer \(pushKey)"])
        } catch EpistolaresError.notFound {
            return nil
        }
    }

    // MARK: - Request helpers

    private static func query(_ items: (String, String?)...) -> [URLQueryItem] {
        items.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem], headers: [String: String] = [:]) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query

        guard let url = components.url else { throw EpistolaresError.badResponse }

        var request = URLRequest(url: url)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }

        let (data, response) = try await session.data(for: request)

        try validate(response)

        return try Self.decoder.decode(T.self, from: data)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw EpistolaresError.badResponse }
        switch http.statusCode {
        case 200..<300: break
        case 400:       throw EpistolaresError.badRequest
        case 401:       throw EpistolaresError.unauthorized
        case 404:       throw EpistolaresError.notFound
        default:        throw EpistolaresError.server(http.statusCode)
        }
    }

    @discardableResult
    private func post(_ path: String, body: some Encodable, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = try Self.encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        try validate(response)

        return data
    }
}
