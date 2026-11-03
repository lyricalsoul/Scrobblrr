//
//  DittoTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
import Foundation
@testable import Scrobblr

@Suite struct DittoTests {
    static func reply(_ request: URLRequest, _ status: Int?, _ body: String) -> (URLResponse, Data) {
        let data = Data(body.utf8)
        guard let status else { return (URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil), data) }
        return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
    }

    static func make(_ status: Int? = 200, _ body: String = #"{"error":false,"url":"https://img.example/c.png","time":12}"#) -> (Ditto, URLSession) {
        let session = StubURLProtocol.session { reply($0, status, body) }
        return (Ditto(username: "me", session: session), session)
    }

    static func generate(_ api: Ditto, theme: CollageTheme = .classic) async throws -> URL {
        try await api.generateCollage(theme: theme, entity: .album, period: .week, rows: 4, columns: 5, showLabels: true, showPlayCount: false, padded: true)
    }

    static func errorName(_ api: Ditto) async -> String {
        do { _ = try await generate(api); return "no error" } catch { return String(describing: error) }
    }

    static func sentBody(_ session: URLSession) throws -> [String: Any] {
        let body = try #require(StubURLProtocol.requests(of: session).first?.body)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    @Test func classicThemeSendsGridValues() async throws {
        let (api, session) = Self.make()
        let url = try await Self.generate(api)
        #expect(url.absoluteString == "https://img.example/c.png")
        let request = try #require(StubURLProtocol.requests(of: session).first)
        #expect(request.request.httpMethod == "POST")
        #expect(request.request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try Self.sentBody(session)
        #expect(body["theme"] as? String == "classic_collage")
        let data = try #require(body["data"] as? [String: Any])
        #expect(data["username"] as? String == "me")
        #expect(data["entity"] as? String == "album")
        #expect(data["period"] as? String == "7day")
        #expect(data["rows"] as? Int == 4)
        #expect(data["columns"] as? Int == 5)
        #expect(data["padded"] as? Bool == true)
        #expect(data["show_labels"] as? Bool == true)
        #expect(data["show_play_count"] as? Bool == false)
    }

    @Test func asymmetricForcesOneByOneAndNilPadded() async throws {
        let (api, session) = Self.make()
        _ = try await Self.generate(api, theme: .asymmetric)
        let body = try Self.sentBody(session)
        #expect(body["theme"] as? String == "asymmetric_collage")
        let data = try #require(body["data"] as? [String: Any])
        #expect(data["rows"] as? Int == 1)
        #expect(data["columns"] as? Int == 1)
        #expect(data["padded"] == nil)
    }

    @Test func serverErrorUsesMessage() async {
        let (api, _) = Self.make(500, #"{"error":true,"message":"boom"}"#)
        #expect(await Self.errorName(api) == "server(\"boom\")")
    }

    @Test func errorFlagThrows() async {
        let (api, _) = Self.make(200, #"{"error":true,"message":"nope"}"#)
        #expect(await Self.errorName(api) == "server(\"nope\")")
    }

    @Test func missingURLThrowsNoURL() async {
        let (api, _) = Self.make(200, #"{"error":false}"#)
        #expect(await Self.errorName(api) == "noURL")
    }

    @Test func undecodableSuccessBodyThrowsBadResponse() async {
        let (api, _) = Self.make(200, "<html>")
        #expect(await Self.errorName(api) == "badResponse")
    }

    @Test func non2xxWithoutBodyUsesStatusMessage() async {
        let (api, _) = Self.make(503, "")
        #expect(await Self.errorName(api) == "server(\"Request failed (HTTP 503).\")")
    }

    @Test func nonHTTPResponseThrowsBadResponse() async {
        let (api, _) = Self.make(nil)
        #expect(await Self.errorName(api) == "badResponse")
    }
}
