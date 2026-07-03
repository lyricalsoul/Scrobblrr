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
        let userScrobbles: UserScrobbles?

        struct UserScrobbles: Decodable {
            let playCount: Int
            let loved: Bool
        }
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
    let mbid: String?
    let listeners: Int
    let scrobbles: Int
    let userScrobbles: EpistolaresUserScrobbles?
    let url: String?
    let cover: Cover?
    let aliases: [String]
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
    let mbid: String?
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

struct ChartPage: Decodable {
    let page: Int
    let totalPages: Int
    let total: Int
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
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse:    "Epistolares returned an unexpected response"
        case .notFound:       "The requested entity wasn't found"
        case .badRequest:     "The request was missing or had invalid parameters"
        case .server(let s):  "Epistolares request failed (HTTP \(s))"
        }
    }
}

struct Epistolares {
    private static let baseURL = Constants.epistolaresBaseURL

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Methofs

    func trackInfo(track: String, artist: String, album: String? = nil, username: String? = nil) async throws -> EpistolaresTrackInfo {
        var items = [
            URLQueryItem(name: "track", value: track),
            URLQueryItem(name: "artist", value: artist),
        ]
        if let album { items.append(URLQueryItem(name: "album", value: album)) }
        if let username { items.append(URLQueryItem(name: "username", value: username)) }

        return try await get("/track/info", query: items)
    }

    func trackInfo(id: String, username: String? = nil) async throws -> EpistolaresTrackInfo {
        var items = [URLQueryItem(name: "id", value: id)]
        if let username { items.append(URLQueryItem(name: "username", value: username)) }
        return try await get("/track/info", query: items)
    }

    func artistInfo(id: String, username: String? = nil) async throws -> EpistolaresArtistInfo {
        var items = [URLQueryItem(name: "id", value: id)]
        if let username { items.append(URLQueryItem(name: "username", value: username)) }
        return try await get("/artist/info", query: items)
    }

    func albumInfo(id: String, username: String? = nil) async throws -> EpistolaresAlbumInfo {
        var items = [URLQueryItem(name: "id", value: id)]
        if let username { items.append(URLQueryItem(name: "username", value: username)) }
        return try await get("/album/info", query: items)
    }

    func userChartsAll(username: String, period: LastFMPeriod, limit: Int = 50) async throws -> AllCharts {
        try await get("/user/charts/all", query: [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "period", value: period.apiValue),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }

    func recentTracks(username: String, limit: Int = 2) async throws -> EpistolaresRecentTracks {
        try await get("/user/recent-tracks", query: [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }

    // MARK: - Request helpers

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query

        guard let url = components.url else { throw EpistolaresError.badResponse }

        var request = URLRequest(url: url)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw EpistolaresError.badResponse
        }
        switch http.statusCode {
        case 200..<300: break
        case 400:       throw EpistolaresError.badRequest
        case 404:       throw EpistolaresError.notFound
        default:        throw EpistolaresError.server(http.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }
}
