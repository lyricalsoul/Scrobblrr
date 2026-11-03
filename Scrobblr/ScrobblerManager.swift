//
//  ScrobblerManager.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//

import Foundation
import SwiftData
import os
import SwiftUI

@Observable
final class ScrobblerManager {
    private(set) var current: GenericPlaybackInfo?
    private(set) var rawCurrent: GenericPlaybackInfo?
    private(set) var coverImageUrl: URL? = nil

    private(set) var currentInfo: EpistolaresTrackInfo?

    #if os(macOS)
    var displayInfo: GenericPlaybackInfo? { presence.displayInfo }
    var displayCoverURL: URL? { presence.displayCoverURL }
    var displayDeviceName: String? { presence.displayDeviceName }
    var displayTrackInfo: EpistolaresTrackInfo? { presence.isLocalIdle ? presence.relay.trackInfo : currentInfo }
    #else
    var displayTrackInfo: EpistolaresTrackInfo? { currentInfo }
    #endif

    var currentTrackScrobbles: Int? { displayTrackInfo?.track.userScrobbles?.playCount }
    var currentAlbumScrobbles: Int? { displayTrackInfo?.album?.userScrobbles?.playCount }
    var currentArtistScrobbles: Int? { displayTrackInfo?.artist.userScrobbles?.playCount }
    var currentArtistCoverURL: URL? { displayTrackInfo?.artist.cover?.url() }
    var albumOnlyCoverURL: URL? {
        displayTrackInfo?.album?.cover?.url() ?? displayTrackInfo?.track.cover?.url() ?? currentArtistCoverURL
    }

    #if os(macOS)
    @ObservationIgnored let discordPresence = DiscordPresence()
    #endif
    @ObservationIgnored let presence: PresenceCoordinator

    @ObservationIgnored let lastFM: LastFMScrobbler
    @ObservationIgnored let queue: ScrobbleQueue
    @ObservationIgnored private let trackInfo: any EpistolaresAPI
    @ObservationIgnored private let services: [any Scrobbable]
    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let corrector: ScrobbleCorrector
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    @ObservationIgnored private let now: () -> Date

    @ObservationIgnored private var tracker = PlaybackTracker()
    @ObservationIgnored private var playGeneration = 0
    @ObservationIgnored private var pendingScrobble: Scrobble?
    @ObservationIgnored private var didScrobbleCurrent = false
    @ObservationIgnored private var scrobbleTask: Task<Void, Never>?
    @ObservationIgnored private var nowPlayingTask: Task<Void, Never>?

    private enum Event {
        case playback(GenericPlaybackInfo?, at: Date), refreshCorrections(at: Date), barrier(CheckedContinuation<Void, Never>)
    }

    @ObservationIgnored private let events: AsyncStream<Event>.Continuation

    init(modelContainer: ModelContainer, settings: Settings, lastFM: LastFMScrobbler = LastFMScrobbler(), services: [any Scrobbable]? = nil, trackInfo: any EpistolaresAPI = Epistolares(), corrector: ScrobbleCorrector? = nil, queue: ScrobbleQueue? = nil, presence: PresenceCoordinator? = nil, sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }, now: @escaping () -> Date = Date.init) {
        let services = services ?? [lastFM]
        self.settings = settings
        self.lastFM = lastFM
        self.services = services
        self.trackInfo = trackInfo
        self.sleep = sleep
        self.now = now
        self.queue = queue ?? ScrobbleQueue(modelContainer: modelContainer, services: { services }, sleep: sleep)
        #if os(macOS)
        self.presence = presence ?? .live(settings: settings, discord: discordPresence, lastFM: lastFM, trackInfo: trackInfo)
        let intelligence = AutoCorrector(modelContainer: modelContainer)
        let fixArtist: ((String) async -> CorrectedEntity)? = { await intelligence.correct(artist: $0) }
        #else
        self.presence = presence ?? PresenceCoordinator(settings: settings, lastFM: lastFM)
        let fixArtist: ((String) async -> CorrectedEntity)? = nil
        #endif
        self.corrector = corrector ?? ScrobbleCorrector(context: modelContainer.mainContext, settings: settings, fixArtist: fixArtist)

        let (stream, events) = AsyncStream.makeStream(of: Event.self)
        self.events = events
        Task { [weak self] in
            for await event in stream {
                await self?.handle(event)
            }
        }
    }

    deinit {
        events.finish()
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

    func refreshCurrentTrackCorrections() {
        events.yield(.refreshCorrections(at: now()))
    }

    func signOut() {
        lastFM.signOut()
        queue.clear()
    }

    // MARK: - Submission

    private func submit(_ scrobble: Scrobble, to service: any Scrobbable) async {
        do {
            try await service.scrobble(scrobble)
            Logger.scrobbler.info("Scrobbled to \(service.name, privacy: .public): \(scrobble.artist, privacy: .public) - \(scrobble.track, privacy: .public)")
        } catch {
            if ScrobbleQueue.isRetryable(error), service.isAuthenticated { // signed out meanwhile: don't replay into the next session
                queue.enqueue(scrobble, for: service.name)
                Logger.scrobbler.error("Scrobble to \(service.name, privacy: .public) failed, queued: \(error.localizedDescription, privacy: .public)")
            } else {
                Logger.scrobbler.error("Scrobble to \(service.name, privacy: .public) dropped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Event handling

    /// `nil` when playback stops
    func update(_ info: GenericPlaybackInfo?) {
        events.yield(.playback(info, at: now()))
    }

    private func handle(_ event: Event) async {
        switch event {
        case .playback(let info?, let date):
            guard await handle(info, at: date) else { return }
        case .playback(nil, _):
            stop()
        case .refreshCorrections(let date):
            await refreshCorrections(at: date)
        case .barrier(let continuation):
            return continuation.resume()
        }
        presence.broadcast(current: current, coverURL: coverImageUrl)
    }

    /// returns false when nothing changed
    private func handle(_ info: GenericPlaybackInfo, at date: Date) async -> Bool {
        switch tracker.observe(info, at: date, didScrobble: didScrobbleCurrent) {
        case .none:
            return false
        case .newTrack:
            scrobbleTask?.cancel()
            playGeneration += 1
            didScrobbleCurrent = false
            let scrobble = await corrector.corrected(from: info, at: date)
            pendingScrobble = scrobble
            currentInfo = nil
            coverImageUrl = nil
            current = scrobble.map(info.withMetadata(from:)) ?? info
            rawCurrent = info
            fetchTrackInfo(for: info, scrobble: scrobble)
            Logger.playback.info("New track (playing: \(info.isPlaying)): \(info.displayName, privacy: .public)")
            if info.isPlaying { announceAndSchedule(info) }
        case .resumed, .paused:
            Logger.playback.info("\(info.isPlaying ? "Resumed" : "Paused", privacy: .public) \(info.displayName, privacy: .public)")
            current = current?.withPlaying(info.isPlaying)
            rawCurrent = rawCurrent?.withPlaying(info.isPlaying)
            scrobbleTask?.cancel()
            if info.isPlaying, !didScrobbleCurrent { announceAndSchedule(info) }
        case .seeked:
            scheduleCommit(for: info)
        case .restarted:
            Logger.playback.info("Restarted \(info.displayName, privacy: .public)")
            playGeneration += 1
            didScrobbleCurrent = false
            let timestamp = date.addingTimeInterval(-Double(info.elapsedTimeSeconds))
            pendingScrobble = pendingScrobble.map { Scrobble(artist: $0.artist, track: $0.track, album: $0.album, durationSeconds: $0.durationSeconds, timestamp: timestamp) }
            announceAndSchedule(info)
        }
        return true
    }

    private func refreshCorrections(at date: Date) async {
        guard let rawCurrent else { return }
        let info = rawCurrent.withElapsedTimeSeconds(tracker.position(at: date) ?? rawCurrent.elapsedTimeSeconds)
        let scrobble = await corrector.corrected(from: info, at: date)
        pendingScrobble = scrobble
        current = scrobble.map(rawCurrent.withMetadata(from:)) ?? rawCurrent
        fetchTrackInfo(for: rawCurrent, scrobble: scrobble)
        if info.isPlaying, !didScrobbleCurrent { announceAndSchedule(info) }
    }

    private func stop() {
        scrobbleTask?.cancel()
        tracker.reset()
        playGeneration += 1
        pendingScrobble = nil
        didScrobbleCurrent = false
        current = nil
        rawCurrent = nil
        currentInfo = nil
        coverImageUrl = nil
    }

    private func fetchTrackInfo(for info: GenericPlaybackInfo, scrobble: Scrobble?) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let fetchedInfo = try await self.trackInfo.trackInfo(
                    track: scrobble?.track ?? info.title,
                    artist: scrobble?.artist ?? info.artist,
                    album: scrobble?.album ?? info.album,
                    username: self.lastFM.username
                )
                guard self.rawCurrent?.id == info.id else { return }
                self.currentInfo = fetchedInfo
                let resolvedCover = fetchedInfo.album?.cover?.url() ?? fetchedInfo.artist.cover?.url()
                if resolvedCover != self.coverImageUrl {
                    self.coverImageUrl = resolvedCover
                }
                self.presence.broadcast(current: self.current, coverURL: self.coverImageUrl)
            } catch {
                Logger.epistolares.error("Couldn't fetch track info: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// sends now playing in order without holding up playback events, then schedules the commit
    private func announceAndSchedule(_ info: GenericPlaybackInfo) {
        if let scrobble = pendingScrobble {
            nowPlayingTask = Task { [weak self, previous = nowPlayingTask] in
                await previous?.value
                await self?.sendNowPlaying(scrobble)
            }
        }
        scheduleCommit(for: info)
    }

    /// schedules the commit for the time left until the listen threshold
    private func scheduleCommit(for info: GenericPlaybackInfo) {
        scrobbleTask?.cancel()
        guard let scrobble = pendingScrobble, info.isPlaying, !didScrobbleCurrent, info.durationSeconds > 0,
              info.durationSeconds >= settings.minTrackSeconds
        else { return }

        let target = min(Double(info.durationSeconds) * settings.scrobbleThreshold, Double(settings.maxScrobbleSeconds))
        let remaining = max(0, target - Double(info.elapsedTimeSeconds))
        let generation = playGeneration

        Logger.playback.info("Scrobble scheduled in \(Int(remaining))s for \(info.displayName, privacy: .public)")

        scrobbleTask = Task { [weak self, sleep] in
            guard (try? await sleep(.seconds(remaining))) != nil, let self, !Task.isCancelled, self.playGeneration == generation else { return }
            Logger.playback.info("Threshold reached, pushing \(scrobble.artist, privacy: .public) — \(scrobble.track, privacy: .public)")
            // marked before the request so a pause/resume while it is in flight can't schedule a second one
            self.didScrobbleCurrent = true
            // unstructured so cancelling the schedule never cancels a request in flight
            await Task { await self.commit(scrobble) }.value
        }
    }
}

#if DEBUG
extension ScrobblerManager {
    /// returns once every event sent so far has been handled and its now playing sent
    func settle() async {
        await withCheckedContinuation { events.yield(.barrier($0)) }
        await nowPlayingTask?.value
    }

    static func preview(current: GenericPlaybackInfo? = nil, coverImageUrl: URL? = nil) -> ScrobblerManager {
        let container = try! ModelContainer(
            for: Correction.self, ManualCorrection.self, CachedArtist.self, Settings.self, QueuedScrobble.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let manager = ScrobblerManager(modelContainer: container, settings: Settings.shared(in: container.mainContext))
        manager.current = current
        manager.rawCurrent = current
        manager.coverImageUrl = coverImageUrl
        manager.presence.broadcast(current: current, coverURL: coverImageUrl)
        return manager
    }
}
#endif
