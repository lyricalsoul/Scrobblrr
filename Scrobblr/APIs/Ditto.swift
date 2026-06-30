//
//  Ditto.swift
//  Scrobblr
//
//  Created by Renan Martins on 6/29/26.
//

import Foundation
import os

// MARK: - Collage configuration

enum CollageTheme: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case asymmetric = "Asymmetric"
    var id: String { rawValue }

    /// The theme name the Ditto API expects.
    var apiValue: String {
        switch self {
        case .classic:     "classic_collage"
        case .asymmetric:  "asymmetric_collage"
        }
    }

    /// Asymmetric layouts size themselves; rows/columns/padding aren't configurable.
    var supportsGrid: Bool { self == .classic }
}

/// Generates collage images for a given Last.fm user via a ditto server (https://github.com/musicorum-app/ditto)
struct Ditto {
    let username: String

    // TODO: super users should be able to change this in the settings
    private static let endpoint = URL(string: "https://ditto-stg.musicorum.cloud/generate")!

    init(username: String) {
        self.username = username
    }

    func generateCollage(
        theme: CollageTheme,
        entity: LastFMEntity,
        period: LastFMPeriod,
        rows: Int,
        columns: Int,
        showLabels: Bool,
        showPlayCount: Bool,
        padded: Bool
    ) async throws -> URL {
        let usesGrid = theme.supportsGrid

        let data = CollageData(
            username: username,
            entity: entity.apiValue,
            period: period.apiValue,
            rows: usesGrid ? rows : 1,
            columns: usesGrid ? columns : 1,
            padded: usesGrid ? padded : nil,
            showLabels: showLabels,
            showPlayCount: showPlayCount
        )

        // TODO: NOOOO! i need a real request lib for caching
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GenerateRequest(theme: theme.apiValue, data: data))

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw DittoError.badResponse
        }

        let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: responseData)

        guard (200..<300).contains(http.statusCode) else {
            throw DittoError.server(decoded?.message ?? "Request failed (HTTP \(http.statusCode)).")
        }
        guard let decoded else {
            throw DittoError.badResponse
        }
        if decoded.error {
            throw DittoError.server(decoded.message ?? "The collage couldn't be generated.")
        }
        guard let url = decoded.url else {
            throw DittoError.noURL
        }

        Logger.ditto.info("Generated collage for \(username, privacy: .public) in \(decoded.time ?? -1)ms")
        return url
    }
}

// MARK: - Types

private struct GenerateRequest: Encodable {
    let theme: String
    let data: CollageData
}

private struct CollageData: Encodable {
    let username: String
    let entity: String
    let period: String?
    let rows: Int
    let columns: Int
    let padded: Bool?
    let showLabels: Bool?
    let showPlayCount: Bool?

    enum CodingKeys: String, CodingKey {
        case username, entity, period, rows, columns, padded
        case showLabels = "show_labels"
        case showPlayCount = "show_play_count"
    }
}

struct GenerateResponse: Decodable {
    let error: Bool
    let message: String?
    let file: String?
    let url: URL?
    let time: Int?
}

enum DittoError: LocalizedError {
    case badResponse
    case server(String)
    case noURL

    var errorDescription: String? {
        switch self {
        case .badResponse:          "The collage service returned an unexpected response."
        case .server(let message):  message
        case .noURL:                "The collage service didn't return an image."
        }
    }
}
