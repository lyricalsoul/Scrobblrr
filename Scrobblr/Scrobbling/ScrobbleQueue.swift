//
//  ScrobbleQueue.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Foundation
import SwiftData
import LastFM
import os

@MainActor
final class ScrobbleQueue {
    static let maxAttempts = 12
    private static let baseDelay: TimeInterval = 30
    private static let maxDelay: TimeInterval = 60 * 60

    private let modelContainer: ModelContainer
    private let services: () -> [any Scrobbable]
    private let sleep: (Duration) async throws -> Void
    private var loop: Task<Void, Never>?
    private var nap: Task<Void, Error>?
    private var isProcessing = false

    private var context: ModelContext { modelContainer.mainContext }

    init(modelContainer: ModelContainer, services: @escaping () -> [any Scrobbable], sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.modelContainer = modelContainer
        self.services = services
        self.sleep = sleep
        startLoop()
    }

    func enqueue(_ scrobble: Scrobble, for serviceName: String) {
        let next = Date(timeIntervalSinceNow: Self.backoff(forAttempt: 1))
        guard let item = try? QueuedScrobble(serviceName: serviceName, scrobble: scrobble, nextAttempt: next, createdAt: Date()) else { return }
        context.insert(item)
        try? context.save()
        Logger.queue.info("Enqueued scrobble for \(serviceName, privacy: .public), next attempt at \(next, privacy: .public)")
        nap?.cancel()
        startLoop()
    }

    func clear(serviceName: String? = nil) {
        for item in (try? context.fetch(FetchDescriptor<QueuedScrobble>())) ?? [] where serviceName == nil || item.serviceName == serviceName {
            context.delete(item)
        }
        try? context.save()
    }

    private func startLoop() {
        guard loop == nil, ((try? context.fetchCount(FetchDescriptor<QueuedScrobble>())) ?? 0) > 0 else { return }
        loop = Task { [weak self, sleep] in
            while let delay = await self?.processDue() {
                let nap = Task { try await sleep(.seconds(delay)) }
                self?.nap = nap
                _ = await nap.result
                self?.nap = nil
            }
            self?.loop = nil
        }
    }

    /// returns the delay until the next item, or `nil` when the queue is empty
    func processDue() async -> TimeInterval? {
        let descriptor = FetchDescriptor<QueuedScrobble>(sortBy: [SortDescriptor(\.nextAttempt)])
        if !isProcessing {
            isProcessing = true
            defer { isProcessing = false }
            let due = ((try? context.fetch(descriptor)) ?? []).filter { $0.nextAttempt <= Date() }
            if !due.isEmpty {
                Logger.queue.info("Processing \(due.count) queued scrobble(s)")
            }
            for item in due {
                await process(item)
            }
        }
        guard let soonest = try? context.fetch(descriptor).first else { return nil }
        return max(5, soonest.nextAttempt.timeIntervalSinceNow)
    }

    private func process(_ item: QueuedScrobble) async {
        guard item.modelContext != nil else { return }
        guard let service = services().first(where: { $0.name == item.serviceName }), let scrobble = item.scrobble else {
            context.delete(item) // unknown service or undecodable payload, can't succeed
            try? context.save()
            return
        }

        var failure: Error?
        do {
            try await service.scrobble(scrobble)
        } catch {
            failure = error
        }
        guard item.modelContext != nil, !item.isDeleted else { return } // cleared while submitting

        if let error = failure {
            if Self.isCancellation(error), Task.isCancelled { return } // a real cancel, not a failing request
            if Self.isRetryable(error) && item.attempt + 1 < Self.maxAttempts {
                item.attempt += 1
                item.nextAttempt = Date(timeIntervalSinceNow: Self.backoff(forAttempt: item.attempt + 1))
                Logger.queue.error("Retry \(item.attempt) failed for \(item.serviceName, privacy: .public), next at \(item.nextAttempt, privacy: .public): \(error.localizedDescription, privacy: .public)")
            } else {
                Logger.queue.error("Giving up on queued scrobble for \(item.serviceName, privacy: .public) after \(item.attempt + 1) attempts: \(error.localizedDescription, privacy: .public)")
                context.delete(item)
            }
        } else {
            context.delete(item)
            Logger.queue.info("Retry succeeded for \(service.name, privacy: .public): \(scrobble.artist, privacy: .public) - \(scrobble.track, privacy: .public)")
        }
        try? context.save()
    }

    static func backoff(forAttempt attempt: Int) -> TimeInterval {
        min(baseDelay * pow(2, Double(max(0, attempt - 1))), maxDelay)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if case LastFMError.OtherError(let inner) = error { return isCancellation(inner) }
        return error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    static func isRetryable(_ error: Error) -> Bool {
        switch error {
        case is URLError:
            return true
        case ScrobblerError.notAuthenticated:
            return false
        case let lastFM as LastFMError:
            switch lastFM {
            case .NoData:
                return true
            case .OtherError(let inner):
                return inner is URLError
            case .LastFMServiceError(let type, _):
                switch type {
                case .ServiceOffline, .TemporaryProcessingError, .RateLimitExceeded, .OperationFailed:
                    return true
                default:
                    return false // bad params, invalid session key, etc.
                }
            }
        default:
            return true // unknown: prefer not to lose the scrobble (bounded by maxAttempts)
        }
    }
}
