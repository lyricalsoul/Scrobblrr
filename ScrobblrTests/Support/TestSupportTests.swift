//
//  TestSupportTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
import Foundation
import SwiftData
@testable import Scrobblr

@Suite(.serialized) struct TestSupportTests {
    @Test func containerOpens() throws {
        let container = try makeContainer()
        #expect(try ModelContext(container).fetch(FetchDescriptor<Settings>()).isEmpty)
    }

    @Test func fakeScrobblerRecords() async throws {
        let fake = FakeScrobbler()
        let scrobble = Scrobble(artist: "A", track: "T", album: nil, durationSeconds: 1, timestamp: .now)
        try await fake.updateNowPlaying(scrobble)
        try await fake.scrobble(scrobble)
        #expect(fake.nowPlaying == [scrobble])
        #expect(fake.scrobbled == [scrobble])
        fake.scrobbleError = URLError(.badURL)
        await #expect(throws: URLError.self) { try await fake.scrobble(scrobble) }
    }

    @Test func sleeperSuspendsUntilAdvance() async throws {
        let sleeper = ManualSleeper()
        let sleep = sleeper.sleep
        let task = Task { try await sleep(.seconds(5)) }
        while sleeper.requested.isEmpty { await Task.yield() }
        #expect(sleeper.requested == [.seconds(5)])
        sleeper.advance()
        try await task.value
    }

    @Test func advanceBeforeSleepDoesNotHang() async throws {
        let sleeper = ManualSleeper()
        sleeper.advance()
        try await sleeper.sleep(.seconds(1))
        #expect(sleeper.requested == [.seconds(1)])
    }

    @Test func cancellingSleepingTaskThrowsCancellationError() async throws {
        let sleeper = ManualSleeper()
        let sleep = sleeper.sleep
        let task = Task { try await sleep(.seconds(5)) }
        while sleeper.requested.isEmpty { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func sleepAfterCancelWithBankedCreditStillThrows() async {
        let sleeper = ManualSleeper()
        sleeper.advance()
        let sleep = sleeper.sleep
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            try await sleep(.seconds(1))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func advanceAfterObservingRequestNeverHangs() async {
        for _ in 0..<200 {
            let sleeper = ManualSleeper()
            let sleep = sleeper.sleep
            let task = Task { try await sleep(.seconds(1)) }
            let watchdog = Task {
                try await Task.sleep(for: .seconds(5))
                sleeper.cancelAll()
            }
            while sleeper.requested.isEmpty { await Task.yield() }
            sleeper.advance()
            let result = await task.result
            watchdog.cancel()
            #expect(throws: Never.self) { try result.get() }
        }
    }

    @Test func stubProtocolServesResponseAndRecordsBody() async throws {
        let url = URL(string: "https://example.test/x")!
        let session = StubURLProtocol.session { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("ok".utf8))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("payload".utf8)
        let (data, response) = try await session.data(for: request)
        #expect(String(decoding: data, as: UTF8.self) == "ok")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let captured = StubURLProtocol.requests(of: session)
        #expect(captured.count == 1)
        #expect(captured.first?.body.map { String(decoding: $0, as: UTF8.self) } == "payload")
    }

    @Test func stubSessionsDoNotShareHandlers() async throws {
        let url = URL(string: "https://example.test/x")!
        let first = StubURLProtocol.session { _ in (HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data()) }
        let second = StubURLProtocol.session { _ in (HTTPURLResponse(url: url, statusCode: 202, httpVersion: nil, headerFields: nil)!, Data()) }
        #expect(((try await first.data(from: url)).1 as? HTTPURLResponse)?.statusCode == 201)
        #expect(((try await second.data(from: url)).1 as? HTTPURLResponse)?.statusCode == 202)
    }

    @Test func infoBuildsPlaying() {
        let value = info("S", artist: "Ar")
        #expect(value.title == "S" && value.artist == "Ar" && value.isPlaying)
    }
}
