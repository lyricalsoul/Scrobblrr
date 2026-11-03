//
//  EpistolaresTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
import Foundation
@testable import Scrobblr

@Suite struct EpistolaresTests {
    struct StatusCase: CustomTestStringConvertible {
        let status: Int?
        let expected: String
        var testDescription: String { "\(status.map(String.init) ?? "non-http") -> \(expected)" }
    }

    static let statusCases = [
        StatusCase(status: 400, expected: "badRequest"),
        StatusCase(status: 401, expected: "unauthorized"),
        StatusCase(status: 404, expected: "notFound"),
        StatusCase(status: 500, expected: "server(500)"),
        StatusCase(status: nil, expected: "badResponse"),
    ]

    static let trackJSON = Data(#"{"track":{"name":"T","listeners":1,"scrobbles":2,"tags":[]},"artist":{"name":"A","listeners":1,"scrobbles":2}}"#.utf8)

    static func reply(_ request: URLRequest, _ status: Int?, _ data: Data = Data("{}".utf8)) -> (URLResponse, Data) {
        guard let status else { return (URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil), data) }
        return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
    }

    static func make(_ status: Int? = 200, body: Data = Data("{}".utf8), cache: TrackInfoCache = TrackInfoCache()) -> (Epistolares, URLSession) {
        let session = StubURLProtocol.session { reply($0, status, body) }
        return (Epistolares(session: session, cache: cache), session)
    }

    static func errorName(_ operation: () async throws -> Void) async -> String {
        do { try await operation(); return "no error" } catch { return String(describing: error) }
    }

    @Test(arguments: statusCases) func getMapsStatus(_ testCase: StatusCase) async {
        let (api, _) = Self.make(testCase.status)
        #expect(await Self.errorName { _ = try await api.recentTracks(username: "u") } == testCase.expected)
    }

    @Test(arguments: statusCases) func postMapsStatus(_ testCase: StatusCase) async {
        let (api, _) = Self.make(testCase.status)
        #expect(await Self.errorName { _ = try await api.registerPresence(sessionKey: "k") } == testCase.expected)
    }

    @Test func trackInfoCachesAcrossCaseAndWhitespace() async throws {
        let (api, session) = Self.make(body: Self.trackJSON)
        _ = try await api.trackInfo(track: "Song", artist: "Artist", album: "Album", username: "me")
        _ = try await api.trackInfo(track: " song ", artist: "ARTIST", album: "album", username: " Me")
        #expect(StubURLProtocol.requests(of: session).count == 1)
    }

    @Test func invalidateClearsCache() async throws {
        let (api, session) = Self.make(body: Self.trackJSON)
        _ = try await api.trackInfo(track: "Song", artist: "Artist", album: nil, username: nil)
        api.invalidateTrackInfoCache()
        _ = try await api.trackInfo(track: "Song", artist: "Artist", album: nil, username: nil)
        #expect(StubURLProtocol.requests(of: session).count == 2)
    }

    @MainActor @Test func cacheEvictsExpiredEntriesOnInsert() throws {
        let info = try JSONDecoder().decode(EpistolaresTrackInfo.self, from: Self.trackJSON)
        let expiring = TrackInfoCache(ttl: 0)
        expiring.set(info, for: "a")
        expiring.set(info, for: "b")
        #expect(expiring.count == 1)
        let fresh = TrackInfoCache()
        fresh.set(info, for: "a")
        fresh.set(info, for: "b")
        #expect(fresh.count == 2 && fresh.value(for: "a") != nil)
    }

    @Test func presenceReturnsNilOn404() async throws {
        let (api, _) = Self.make(404)
        #expect(try await api.presence(username: "u", pushKey: "p") == nil)
    }

    @Test func pushPresenceSendsBearerAndBody() async throws {
        let (api, session) = Self.make()
        try await api.pushPresence(username: "u", pushKey: "secret", device: "mac", info: info("S"))
        let sent = try #require(StubURLProtocol.requests(of: session).first)
        #expect(sent.request.httpMethod == "POST")
        #expect(sent.request.url?.path.hasSuffix("/user/presence/u") == true)
        #expect(sent.request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        let body = try #require(sent.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["device"] as? String == "mac")
        #expect((json["info"] as? [String: Any])?["title"] as? String == "S")
    }

    @Test func chartsQueryHasPeriodAndLimit() async throws {
        let page = #"{"page":1,"totalPages":1,"total":0,"items":[]}"#
        let (api, session) = Self.make(body: Data(#"{"artists":\#(page),"albums":\#(page),"tracks":\#(page)}"#.utf8))
        _ = try await api.userChartsAll(username: "u", period: .month, limit: 7)
        let url = try #require(StubURLProtocol.requests(of: session).first?.request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "period" }?.value == LastFMPeriod.month.apiValue)
        #expect(items?.first { $0.name == "limit" }?.value == "7")
    }

    @Test func coverURLUsesTemplate() {
        let cover = Cover(defaultURL: "https://x.test/default.jpg", template: "https://x.test/{w}x{h}.jpg")
        #expect(cover.url(size: 300)?.absoluteString == "https://x.test/300x300.jpg")
    }

    @Test func coverURLFallsBackToDefault() {
        #expect(Cover(defaultURL: "https://x.test/default.jpg", template: nil).url()?.absoluteString == "https://x.test/default.jpg")
        #expect(Cover(defaultURL: nil, template: nil).url() == nil)
    }
}
