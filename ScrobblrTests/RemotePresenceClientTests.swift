//
//  RemotePresenceClientTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

#if os(macOS)
import Foundation
import Testing
@testable import Scrobblr

@MainActor
@Suite struct RemotePresenceClientTests {
    private func json(device: String = "ios", title: String? = "Song", at date: String) -> String {
        let info = title.map { #","info":{"title":"\#($0)","artist":"Artist","durationSeconds":200,"elapsedTimeSeconds":10,"isPlaying":true}"# } ?? ""
        return #"{"device":"\#(device)"\#(info),"updatedAt":"\#(date)"}"#
    }

    private func presence(device: String = "ios", title: String? = "Song", at date: String) throws -> RemotePresence {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RemotePresence.self, from: Data(json(device: device, title: title, at: date).utf8))
    }

    private func nextDelay(_ client: RemotePresenceClient) -> Duration {
        var copy = client.backoff
        return copy.next()
    }

    @Test func staleUpdateIgnored() throws {
        let client = RemotePresenceClient()
        client.apply(try presence(device: "mac", at: "2026-01-01T12:00:10Z"))
        client.apply(try presence(device: "ios", title: "Old", at: "2026-01-01T12:00:00Z"))
        #expect(client.latestDevice == "mac")
        #expect(client.latest?.title == "Song")
    }

    @Test func newerUpdateReplaces() throws {
        let client = RemotePresenceClient()
        client.apply(try presence(at: "2026-01-01T12:00:00Z"))
        client.apply(try presence(device: "mac", title: "New", at: "2026-01-01T12:00:10Z"))
        #expect(client.latestDevice == "mac")
        #expect(client.latest?.title == "New")
    }

    @Test func handleDecodesStringMessage() {
        let client = RemotePresenceClient()
        client.handle(.string(json(at: "2026-01-01T12:00:00Z")))
        #expect(client.latest?.title == "Song")
        #expect(client.latestDevice == "ios")
    }

    @Test func handleIgnoresBinaryAndGarbage() {
        let client = RemotePresenceClient()
        client.handle(.data(Data(json(at: "2026-01-01T12:00:00Z").utf8)))
        client.handle(.string("not json"))
        #expect(client.latest == nil)
        #expect(client.latestUpdatedAt == nil)
    }

    @Test func applyFiresOnUpdateOnce() async throws {
        let client = RemotePresenceClient()
        let value = try presence(at: "2026-01-01T12:00:00Z")
        await confirmation(expectedCount: 1) { fired in
            client.onUpdate = { fired() }
            client.apply(value)
        }
    }

    @Test func stopClearsLatest() throws {
        let client = RemotePresenceClient()
        client.apply(try presence(at: "2026-01-01T12:00:00Z"))
        client.connectionFailed(statusCode: 500, message: "boom")
        client.stop()
        #expect(client.latest == nil)
        #expect(client.latestDevice == nil)
        #expect(client.latestUpdatedAt == nil)
        #expect(client.status == .disabled)
    }

    @Test func unauthorizedStopsReconnecting() {
        let client = RemotePresenceClient()
        client.connectionFailed(statusCode: 401, message: "bad handshake")
        #expect(client.status == .error("Presence key rejected"))
        #expect(client.reconnectTask == nil)
    }

    @Test func stopAfterRejectionResetsStatusAndCredentials() throws {
        let client = RemotePresenceClient()
        client.username = "u"
        client.pushKey = "k"
        client.apply(try presence(at: "2026-01-01T12:00:00Z"))
        client.connectionFailed(statusCode: 401, message: "bad")
        client.stop()
        #expect(client.status == .disabled)
        #expect(client.username == nil && client.pushKey == nil)
        #expect(client.latest == nil && client.latestUpdatedAt == nil)
    }

    @Test func lateUnauthorizedFromOldCredentialsIsIgnored() {
        let client = RemotePresenceClient()
        client.username = "new"
        client.pushKey = "k2"
        client.connectionFailed(statusCode: 503, message: "down")
        client.initialFetched(.failure(EpistolaresError.unauthorized), username: "old", pushKey: "k")
        #expect(client.status == .error("down"))
        #expect(client.reconnectTask != nil)
        client.initialFetched(.failure(EpistolaresError.unauthorized), username: "new", pushKey: "k2")
        #expect(client.status == .error("Presence key rejected"))
        #expect(client.reconnectTask == nil)
        client.stop()
    }

    @Test func staleSuccessFromOldCredentialsIsIgnored() throws {
        let client = RemotePresenceClient()
        client.username = "new"
        client.pushKey = "k2"
        client.initialFetched(.success(try presence(title: "Old", at: "2026-01-01T12:00:00Z")), username: "old", pushKey: "k")
        #expect(client.latest == nil)
        client.initialFetched(.success(try presence(at: "2026-01-01T12:00:00Z")), username: "new", pushKey: "k2")
        #expect(client.latest?.title == "Song")
    }

    private func offline(username: String, pushKey: String) -> (RemotePresenceClient, Locked<[URLRequest]>) {
        let client = RemotePresenceClient()
        let opened = Locked<[URLRequest]>([])
        client.openSocket = { opened.value.append($0); return nil }
        client.fetchPresence = { _, _ in nil }
        client.username = username
        client.pushKey = pushKey
        return (client, opened)
    }

    @Test func startWithSameCredentialsAfterRejectionDoesNotRetry() {
        let (client, opened) = offline(username: "u", pushKey: "k")
        client.connectionFailed(statusCode: 401, message: "bad")
        client.start(username: "u", pushKey: "k")
        #expect(opened.value.isEmpty)
        #expect(client.reconnectTask == nil)
        #expect(client.status == .error("Presence key rejected"))
        client.stop()
    }

    @Test func startWithSameCredentialsKeepsPendingReconnect() {
        let (client, opened) = offline(username: "u", pushKey: "k")
        client.connectionFailed(statusCode: 503, message: "down")
        let pending = client.reconnectTask
        client.start(username: "u", pushKey: "k")
        #expect(opened.value.isEmpty)
        #expect(pending != nil && client.reconnectTask == pending)
        #expect(nextDelay(client) == .seconds(6))
        client.stop()
    }

    @Test func startWithNewCredentialsAfterRejectionReconnects() {
        let (client, opened) = offline(username: "old", pushKey: "k")
        client.connectionFailed(statusCode: 401, message: "bad")
        client.start(username: "new", pushKey: "k2")
        #expect(opened.value.count == 1)
        #expect(opened.value.first?.url?.path.hasSuffix("/user/presence/new/ws") == true)
        #expect(opened.value.first?.value(forHTTPHeaderField: "Authorization") == "Bearer k2")
        #expect(client.status == .connecting)
        client.stop()
    }

    @Test func serverErrorSchedulesReconnectWithGrowingBackoff() {
        let client = RemotePresenceClient()
        #expect(nextDelay(client) == .seconds(3))
        client.connectionFailed(statusCode: 503, message: "down")
        #expect(client.reconnectTask != nil)
        #expect(nextDelay(client) == .seconds(6))
        client.stop()
        client.connectionFailed(statusCode: nil, message: "down")
        #expect(nextDelay(client) == .seconds(12))
        client.stop()
        client.handle(.string(json(at: "2026-01-01T12:00:00Z")))
        #expect(nextDelay(client) == .seconds(3))
    }
}
#endif
