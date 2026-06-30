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
import CachedAsyncImage
import SwiftUI

typealias CoverImage<Content: View, Placeholder: View> = CachedAsyncImage<_ConditionalContent<Content, Placeholder>>

@Observable
class ScrobblerManager {
    private(set) var current: GenericPlaybackInfo?
    private(set) var coverImageUrl: URL? = nil

    private(set) var currentTrackInfo: TrackInfo?
    private(set) var currentAlbumInfo: AlbumInfo?
    private(set) var currentArtistInfo: ArtistInfo?

    @ObservationIgnored let intelligence: AutoCorrector

    @ObservationIgnored let lastFM = LastFMScrobbler()
    @ObservationIgnored private var services: [any Scrobbable] { [lastFM] }

    @ObservationIgnored private let modelContainer: ModelContainer
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    @ObservationIgnored private static let baseDelay: TimeInterval = 30          // first retry after 30s
    @ObservationIgnored private static let maxDelay: TimeInterval = 60 * 60      // cap at 1 hour
    @ObservationIgnored private static let maxAttempts = 12                      // then give up
    @ObservationIgnored private static let idlePollInterval: TimeInterval = 60   // when queue is empty
    
    @ObservationIgnored private var currentTrackID: String?
    @ObservationIgnored private var wasPlaying = false
    @ObservationIgnored private var pendingScrobble: Scrobble?
    @ObservationIgnored private var didScrobbleCurrent = false
    @ObservationIgnored private var scrobbleTask: Task<Void, Never>?

    private var settings: Settings {
        get {
            return Settings.shared(in: modelContainer.mainContext)
        }
    }
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.intelligence = AutoCorrector(modelContainer: modelContainer)
        startRetryLoop()
    }

    deinit {
        retryTask?.cancel()
        scrobbleTask?.cancel()
    }

    // MARK: - Main

    func sendNowPlaying(_ scrobble: Scrobble) async {
        for service in services where service.isAuthenticated {
            do {
                try await service.updateNowPlaying(scrobble)
                Logger.scrobbler.info("Sent NP to \(service.name, privacy: .public): \(scrobble.artist, privacy: .public) - \(scrobble.track, privacy: .public)")
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
            durationSeconds: track.durationSeconds,
            timestamp: Date(timeIntervalSinceNow: -Double(track.elapsedTimeSeconds))
        )
    }

    /// The corrected title to scrobble, or `nil`
    private func scrobbleable(_ correction: CorrectedEntity, original: String) -> String? {
        guard correction.shouldScrobble else {
            Logger.scrobbler.info("Skipping \(original, privacy: .public), reason: \(correction.reason ?? "ignored by rule", privacy: .public)")
            return nil
        }
        return correction.title
    }

    // MARK: - Submission

    private func submit(_ scrobble: Scrobble, to service: any Scrobbable) async {
        do {
            try await service.scrobble(scrobble)
            Logger.scrobbler.info("Scrobbled to \(service.name, privacy: .public): \(scrobble.artist, privacy: .public) - \(scrobble.track, privacy: .public)")
        } catch {
            if isRetryable(error) {
                enqueue(scrobble, for: service.name)
                Logger.scrobbler.error("Scrobble to \(service.name, privacy: .public) failed, queued: \(error.localizedDescription, privacy: .public)")
            } else {
                Logger.scrobbler.error("Scrobble to \(service.name, privacy: .public) dropped: \(error.localizedDescription, privacy: .public)")
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
            Logger.queue.info("Processing \(due.count) queued scrobble(s) of \(items.count) total")
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
            context.delete(item) // unknown service, can't succeed
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
            Logger.queue.info("Retry succeeded for \(item.serviceName, privacy: .public): \(scrobble.artist, privacy: .public) - \(scrobble.track, privacy: .public)")
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
    
    // MARK: - Event handling
    
    /// Feed the latest playback state. Pass `nil` when playback stops
    func update(_ info: GenericPlaybackInfo?) {
        guard let info else {
            handleStopped()
            return
        }

        Task { await handle(info) }
    }
    
    private func handle(_ info: GenericPlaybackInfo) async {
        let isNewTrack = info.id != currentTrackID
        let playStateChanged = info.isPlaying != wasPlaying
        
        guard isNewTrack || playStateChanged else {
            return
        }
        
        currentTrackID = info.id
        wasPlaying = info.isPlaying

        if isNewTrack {
            didScrobbleCurrent = false
            scrobbleTask?.cancel()
            scrobbleTask = nil
            // Drop the previous track's correction while we compute this one's.
            pendingScrobble = nil

            let scrobble = await corrected(from: info)
            pendingScrobble = scrobble
            
            // Fetch the track, artist, and (optional) album metadata concurrently.
            async let trackInfo = lastFM.getInfoFor(track: info.title, artist: info.artist)
            async let artistInfo = lastFM.getInfoFor(artist: info.artist)
            async let albumInfo: AlbumInfo? = {
                guard let album = info.album else { return nil }
                return await lastFM.getInfoFor(album: album, artist: info.artist)
            }()

            currentTrackInfo = await trackInfo
            currentArtistInfo = await artistInfo
            currentAlbumInfo = await albumInfo

            coverImageUrl = currentAlbumInfo?.image.extraLarge.flatMap {
                URL(string: $0.absoluteString.replacing("300x300", with: "600x600"))
            }

            // are we still playing the same thing after the model run?
            guard currentTrackID == info.id else { return }
            
            // refresh with the up to date info
            guard scrobble != nil else { return }
            current = info.withMetadata(from: scrobble!)

            if info.isPlaying {
                Logger.playback.info("New track playing: \(info.displayName, privacy: .public)")
                await announceAndSchedule(for: info)
            } else {
                Logger.playback.info("New track is paused, waiting: \(info.displayName, privacy: .public)")
            }
        } else if info.isPlaying {
            // Resumed
            guard !didScrobbleCurrent, pendingScrobble != nil else { return }
            Logger.playback.info("Resumed \(info.displayName, privacy: .public)")
            await announceAndSchedule(for: info)
        } else {
            // Paused
            if scrobbleTask != nil {
                Logger.playback.info("Paused: cancelling scrobble countdown for \(info.displayName, privacy: .public)")
            }
            scrobbleTask?.cancel()
            scrobbleTask = nil
        }
    }

    /// Sends now playing request to last.fm
    private func announceAndSchedule(for info: GenericPlaybackInfo) async {
        guard let scrobble = pendingScrobble else { return }
        await self.sendNowPlaying(scrobble)
        guard currentTrackID == info.id, wasPlaying else { return }
        scheduleCommit(for: info)
    }

    private func handleStopped() {
        scrobbleTask?.cancel()
        scrobbleTask = nil
        currentTrackID = nil
        wasPlaying = false
        pendingScrobble = nil
        didScrobbleCurrent = false
        current = nil
    }

    /// Schedules the committed scrobble for the time remaining until the listen
    /// threshold is reached, based on the current elapsed position.
    private func scheduleCommit(for info: GenericPlaybackInfo) {
        guard let scrobble = pendingScrobble else { return }
        guard info.isPlaying else { return }
        guard info.durationSeconds >= settings.minTrackSeconds else { return } // too short to scrobble

        let target = min(Double(info.durationSeconds) * settings.scrobbleThreshold, Double(settings.maxScrobbleSeconds))
        let remaining = max(0, target - Double(info.elapsedTimeSeconds))

        Logger.playback.info("Scrobble scheduled in \(Int(remaining))s for \(info.displayName, privacy: .public)")

        scrobbleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self else { return }
            Logger.playback.info("Threshold reached, pushing \(scrobble.artist, privacy: .public) — \(scrobble.track, privacy: .public)")
            await self.commit(scrobble)
            self.didScrobbleCurrent = true
            self.scrobbleTask = nil
        }
    }
}
