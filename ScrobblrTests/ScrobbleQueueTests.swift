//
//  ScrobbleQueueTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
import Foundation
import SwiftData
import LastFM
@testable import Scrobblr

@Suite @MainActor struct ScrobbleQueueTests {
    let container: ModelContainer
    let fake = FakeScrobbler()
    let sleeper = ManualSleeper()
    let queue: ScrobbleQueue

    init() throws {
        container = try makeContainer()
        queue = ScrobbleQueue(modelContainer: container, services: { [fake] in [fake] }, sleep: sleeper.sleep)
    }

    var context: ModelContext { container.mainContext }
    var items: [QueuedScrobble] { (try? context.fetch(FetchDescriptor<QueuedScrobble>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [] }

    static let scrobble = Scrobble(artist: "Artist", track: "Song", album: nil, durationSeconds: 200, timestamp: Date(timeIntervalSince1970: 1_000_000))

    @discardableResult
    func insert(service: String = "Last.fm", due: Date = .distantPast, attempt: Int = 0, createdAt: Date = .now) throws -> QueuedScrobble {
        let item = try QueuedScrobble(serviceName: service, scrobble: Self.scrobble, nextAttempt: due, createdAt: createdAt)
        item.attempt = attempt
        context.insert(item)
        try context.save()
        return item
    }

    @Test func backoffDoublesAndCaps() {
        #expect(ScrobbleQueue.backoff(forAttempt: 0) == 30)
        #expect(ScrobbleQueue.backoff(forAttempt: 1) == 30)
        #expect(ScrobbleQueue.backoff(forAttempt: 2) == 60)
        #expect(ScrobbleQueue.backoff(forAttempt: 3) == 120)
        #expect(ScrobbleQueue.backoff(forAttempt: 7) == 1920)
        #expect(ScrobbleQueue.backoff(forAttempt: 8) == 3600)
        #expect(ScrobbleQueue.backoff(forAttempt: 40) == 3600)
    }

    struct Other: Error {}

    @Test(arguments: [
        (URLError(.timedOut) as any Error, true),
        (ScrobblerError.notAuthenticated, false),
        (Other(), true),
        (LastFMError.NoData, true),
        (LastFMError.OtherError(URLError(.networkConnectionLost)), true),
        (LastFMError.OtherError(Other()), false),
    ])
    func isRetryable(error: any Error, expected: Bool) {
        #expect(ScrobbleQueue.isRetryable(error) == expected)
    }

    @Test(arguments: [
        (2, false), (3, false), (4, false), (5, false), (6, false), (7, false),
        (8, true), (9, false), (10, false), (11, true), (13, false), (14, false),
        (16, true), (26, false), (29, true),
    ])
    func isRetryableServiceError(rawValue: Int, expected: Bool) throws {
        let type = try #require(LastFMServiceErrorType(rawValue: rawValue))
        #expect(ScrobbleQueue.isRetryable(LastFMError.LastFMServiceError(type, "message")) == expected)
    }

    @Test func successfulRetryDeletesItem() async throws {
        try insert()
        #expect(await queue.processDue() == nil)
        #expect(items.isEmpty)
        #expect(fake.scrobbled == [Self.scrobble])
    }

    @Test func retryableFailureIncrementsAttemptAndReschedules() async throws {
        fake.scrobbleError = URLError(.timedOut)
        let item = try insert()
        let delay = try #require(await queue.processDue())
        #expect(item.attempt == 1)
        #expect(abs(item.nextAttempt.timeIntervalSinceNow - 60) < 5)
        #expect(abs(delay - 60) < 5)
    }

    @Test func giveUpAtMaxAttemptsDeletes() async throws {
        fake.scrobbleError = URLError(.timedOut)
        try insert(attempt: ScrobbleQueue.maxAttempts - 1)
        #expect(await queue.processDue() == nil)
        #expect(items.isEmpty)
    }

    @Test func nonRetryableDrops() async throws {
        fake.scrobbleError = ScrobblerError.notAuthenticated
        try insert()
        _ = await queue.processDue()
        #expect(items.isEmpty)
    }

    @Test func unknownServiceDeletes() async throws {
        try insert(service: "Nope")
        _ = await queue.processDue()
        #expect(items.isEmpty)
        #expect(fake.scrobbled.isEmpty)
    }

    @Test func undecodablePayloadDeletes() async throws {
        let item = try insert()
        item.payloadData = Data("nope".utf8)
        _ = await queue.processDue()
        #expect(items.isEmpty)
        #expect(fake.scrobbled.isEmpty)
    }

    @Test(arguments: [URLError(.cancelled) as any Error, CancellationError(), LastFMError.OtherError(URLError(.cancelled))])
    func cancelledErrorLeavesAttemptUntouched(error: any Error) async throws {
        fake.scrobbleError = error
        let item = try insert(due: Date(timeIntervalSince1970: 0))
        await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = await queue.processDue()
        }.value
        #expect(items.count == 1)
        #expect(item.attempt == 0)
        #expect(item.nextAttempt == Date(timeIntervalSince1970: 0))
    }

    @Test func persistentCancelledURLErrorCountsAsAttempt() async throws {
        fake.scrobbleError = URLError(.cancelled)
        let item = try insert()
        _ = await queue.processDue()
        #expect(item.attempt == 1)
        item.attempt = ScrobbleQueue.maxAttempts - 1
        item.nextAttempt = .distantPast
        _ = await queue.processDue()
        #expect(items.isEmpty)
    }

    @Test func overlappingProcessCallsSubmitOnce() async throws {
        let gate = ManualSleeper()
        fake.gate = { try? await gate.sleep(.zero) }
        try insert()
        let first = Task { await queue.processDue() }
        #expect(await waitUntil { gate.requested.count == 1 })
        let second = Task { await queue.processDue() }
        var secondResult: TimeInterval??
        Task { secondResult = await second.value }
        #expect(await waitUntil { secondResult != nil || gate.requested.count == 2 })
        gate.advance()
        gate.advance()
        _ = await (first.value, second.value)
        #expect(gate.requested.count == 1)
        #expect(secondResult == .some(5))
        #expect(fake.scrobbled.count == 1)
        #expect(items.isEmpty)
    }

    @Test func clearDuringSubmissionDoesNotTouchDeletedItem() async throws {
        let gate = ManualSleeper()
        fake.gate = { try? await gate.sleep(.zero) }
        fake.scrobbleError = URLError(.timedOut)
        try insert(createdAt: Date(timeIntervalSince1970: 1))
        try insert(createdAt: Date(timeIntervalSince1970: 2))
        let processing = Task { await queue.processDue() }
        #expect(await waitUntil { gate.requested.count == 1 })
        queue.clear()
        var result: TimeInterval??
        Task { result = await processing.value }
        gate.advance()
        #expect(await waitUntil { result != nil || gate.requested.count == 2 })
        gate.advance()
        #expect(await processing.value == nil)
        #expect(items.isEmpty)
        #expect(gate.requested.count == 1)
    }

    @Test func enqueueWhileSleepingWakesLoop() async {
        queue.enqueue(Self.scrobble, for: "Last.fm")
        #expect(await waitUntil { sleeper.requested.count == 1 })
        queue.enqueue(Self.scrobble, for: "Last.fm")
        #expect(await waitUntil { sleeper.requested.count == 2 })
        #expect(items.count == 2)
        #expect(fake.scrobbled.isEmpty)
    }

    @Test func enqueueWhileProcessingDoesNotCancelRequest() async throws {
        let gate = ManualSleeper()
        var sawCancel = false
        fake.gate = {
            try? await gate.sleep(.zero)
            sawCancel = sawCancel || Task.isCancelled
        }
        try insert()
        let started = ScrobbleQueue(modelContainer: container, services: { [fake] in [fake] }, sleep: sleeper.sleep)
        #expect(await waitUntil { gate.requested.count == 1 })
        started.enqueue(Self.scrobble, for: "Last.fm")
        gate.advance()
        #expect(await waitUntil { fake.scrobbled.count == 1 })
        #expect(!sawCancel)
        #expect(await waitUntil { sleeper.requested.count == 1 })
        #expect(items.count == 1)
        withExtendedLifetime(started) {}
    }

    @Test func clearByServiceKeepsOthers() throws {
        try insert(service: "Last.fm")
        try insert(service: "ListenBrainz")
        queue.clear(serviceName: "Last.fm")
        #expect(items.map(\.serviceName) == ["ListenBrainz"])
        queue.clear()
        #expect(items.isEmpty)
    }

    @Test func processDueReturnsNilWhenEmpty() async {
        #expect(await queue.processDue() == nil)
    }

    @Test func processDueDelayHasFiveSecondFloor() async throws {
        try insert(due: Date(timeIntervalSinceNow: 4))
        #expect(await queue.processDue() == 5)
        #expect(fake.scrobbled.isEmpty)
    }
}
