//
//  ScrobblerManager.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//

import Foundation
import SwiftData
import LastFM
import os


class ScrobblerManager {
    let intelligence: AutoCorrector


    let lastFM = LastFMScrobbler()
    private var services: [any Scrobbable] { [lastFM] }

    private let modelContainer: ModelContainer
    private var retryTask: Task<Void, Never>?

    private static let baseDelay: TimeInterval = 30          // first retry after 30s
    private static let maxDelay: TimeInterval = 60 * 60      // cap at 1 hour
    private static let maxAttempts = 12                      // then give up
    private static let idlePollInterval: TimeInterval = 60   // when queue is empty

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.intelligence = AutoCorrector(modelContainer: modelContainer)
        startRetryLoop()
    }

    deinit {
        retryTask?.cancel()
    }

    // MARK: - Main

    func prepare(_ track: GenericPlaybackInfo) async -> Scrobble? {
        await corrected(from: track)
    }

    func sendNowPlaying(_ scrobble: Scrobble) async {
        for service in services where service.isAuthenticated {
            do {
                try await service.updateNowPlaying(scrobble)
                Logger.scrobbler.info("Now playing \(service.name, privacy: .public): \(scrobble.artist, privacy: .public) — \(scrobble.track, privacy: .public)")
            } catch {
                Logger.scrobbler.error("Now playing \(service.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func commit(_ scrobble: Scrobble) async {
        for service in services where service.isAuthenticated {
            await submit(scrobble, to: service)
        }
    }

    // MARK: - Correction

    private func corrected(from track: GenericPlaybackInfo) async -> Scrobble? {
        guard let artist = scrobbleable(await intelligence.correct(artist: track.artist), original: track.artist),
              let trackTitle = scrobbleable(await intelligence.correct(track: track.title), original: track.title)
        else { return nil }

        var album = track.album
        if let originalAlbum = track.album {
            guard let correctedAlbum = scrobbleable(await intelligence.correct(album: originalAlbum), original: originalAlbum)
            else { return nil }
            album = correctedAlbum
        }

        return Scrobble(
            artist: artist,
            track: trackTitle,
            album: album,
            albumArtist: nil,
            durationSeconds: track.durationSeconds,
            timestamp: Date(timeIntervalSinceNow: -Double(track.elapsedTimeSeconds))
        )
    }

    /// The corrected title to scrobble, or `nil`
    private func scrobbleable(_ correction: CorrectedEntity, original: String) -> String? {
        guard correction.shouldScrobble else {
            Logger.scrobbler.info("Skipping \(original, privacy: .public) — \(correction.reason ?? "ignored by rule", privacy: .public)")
            return nil
        }
        return correction.title
    }

    // MARK: - Submission

    private func submit(_ scrobble: Scrobble, to service: any Scrobbable) async {
        do {
            try await service.scrobble(scrobble)
            Logger.scrobbler.info("Scrobbled \(service.name, privacy: .public): \(scrobble.artist, privacy: .public) — \(scrobble.track, privacy: .public)")
        } catch {
            if isRetryable(error) {
                enqueue(scrobble, for: service.name)
                Logger.scrobbler.error("Scrobble \(service.name, privacy: .public) failed (retryable), queued: \(error.localizedDescription, privacy: .public)")
            } else {
                Logger.scrobbler.error("Scrobble \(service.name, privacy: .public) dropped (permanent): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Queue

    private func enqueue(_ scrobble: Scrobble, for serviceName: String) {
        let context = modelContainer.mainContext
        let next = Date(timeIntervalSinceNow: Self.backoff(forAttempt: 1))
        guard let item = try? QueuedScrobble(
            serviceName: serviceName,
            scrobble: scrobble,
            nextAttempt: next,
            createdAt: Date()
        ) else { return }

        context.insert(item)
        try? context.save()
        Logger.queue.info("Enqueued scrobble for \(serviceName, privacy: .public), next attempt at \(next, privacy: .public)")
    }

    private func startRetryLoop() {
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let sleep = await self.processQueueTick()
                do {
                    try await Task.sleep(for: .seconds(sleep))
                } catch {
                    return // cancelled
                }
            }
        }
    }

    private func processQueueTick() async -> TimeInterval {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<QueuedScrobble>(
            sortBy: [SortDescriptor(\.nextAttempt)]
        )

        let items = (try? context.fetch(descriptor)) ?? []
        guard !items.isEmpty else { return Self.idlePollInterval }

        let now = Date()
        let due = items.filter { $0.nextAttempt <= now }
        if !due.isEmpty {
            Logger.queue.info("Processing \(due.count) due queued scrobble(s) of \(items.count) total")
        }
        for item in due {
            await process(item, in: context)
        }

        let remaining = (try? context.fetch(descriptor)) ?? []
        guard let soonest = remaining.first else { return Self.idlePollInterval }
        return max(5, soonest.nextAttempt.timeIntervalSinceNow)
    }

    private func process(_ item: QueuedScrobble, in context: ModelContext) async {
        guard let service = services.first(where: { $0.name == item.serviceName }) else {
            context.delete(item) // unknown service, can't ever succeed
            try? context.save()
            return
        }

        guard let scrobble = item.scrobble else {
            context.delete(item) // undecodable payload
            try? context.save()
            return
        }

        do {
            try await service.scrobble(scrobble)
            context.delete(item)
            Logger.queue.info("Retry succeeded for \(item.serviceName, privacy: .public): \(scrobble.artist, privacy: .public) — \(scrobble.track, privacy: .public)")
        } catch {
            if isRetryable(error) && item.attempt + 1 < Self.maxAttempts {
                item.attempt += 1
                item.nextAttempt = Date(timeIntervalSinceNow: Self.backoff(forAttempt: item.attempt + 1))
                Logger.queue.error("Retry \(item.attempt) failed for \(item.serviceName, privacy: .public), next at \(item.nextAttempt, privacy: .public): \(error.localizedDescription, privacy: .public)")
            } else {
                Logger.queue.error("Giving up on queued scrobble for \(item.serviceName, privacy: .public) after \(item.attempt + 1) attempts: \(error.localizedDescription, privacy: .public)")
                context.delete(item)
            }
        }
        try? context.save()
    }

    // MARK: - Helpers

    private static func backoff(forAttempt attempt: Int) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        let delay = baseDelay * pow(2, Double(exponent))
        return min(delay, maxDelay)
    }

    private func isRetryable(_ error: Error) -> Bool {
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
