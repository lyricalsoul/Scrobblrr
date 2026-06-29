//
//  ScrobbleEngine.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//

import SwiftUI
import os

@Observable
@MainActor
final class ScrobbleEngine {
    // TODO: reuse mediamodel?
    private(set) var current: GenericPlaybackInfo?

    @ObservationIgnored private let manager: ScrobblerManager
    @ObservationIgnored private let settings: Settings

    @ObservationIgnored private var currentTrackID: String?
    @ObservationIgnored private var wasPlaying = false
    @ObservationIgnored private var pendingScrobble: Scrobble?
    /// The track id `pendingScrobble`'s corrected metadata applies to
    @ObservationIgnored private var pendingScrobbleID: String?
   
    @ObservationIgnored private var lastRaw: GenericPlaybackInfo?
    @ObservationIgnored private var didScrobbleCurrent = false
    @ObservationIgnored private var scrobbleTask: Task<Void, Never>?

    init(manager: ScrobblerManager, settings: Settings) {
        self.manager = manager
        self.settings = settings
    }

    deinit {
        scrobbleTask?.cancel()
    }

    // MARK: - Input

    /// Feed the latest playback state. Pass `nil` when playback stops
    func update(_ info: GenericPlaybackInfo?) {
        guard let info else {
            handleStopped()
            return
        }

        lastRaw = info
        refreshCurrent()
        Logger.playback.debug("Event: \(info.displayName, privacy: .public) playing=\(info.isPlaying) elapsed=\(info.elapsedTimeSeconds)s/\(info.durationSeconds)s")
        Task { await handle(info) }
    }

    private func refreshCurrent() {
        guard let lastRaw else { current = nil; return }
        current = displayInfo(for: lastRaw)
    }

    // TODO: ew this is messy
    private func displayInfo(for info: GenericPlaybackInfo) -> GenericPlaybackInfo {
        guard let scrobble = pendingScrobble, pendingScrobbleID == info.id else { return info }
        return GenericPlaybackInfo(
            title: scrobble.track,
            artist: scrobble.artist,
            album: scrobble.album,
            durationSeconds: info.durationSeconds,
            elapsedTimeSeconds: info.elapsedTimeSeconds,
            isPlaying: info.isPlaying,
            image: info.image
        )
    }

    // MARK: - Event handling

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
            pendingScrobbleID = nil

            let scrobble = await manager.prepare(info)
            // are we still playing the same thing after the model run?
            guard currentTrackID == info.id else { return }
            pendingScrobble = scrobble
            pendingScrobbleID = info.id
            // refresh with the up to date info
            refreshCurrent()
            guard scrobble != nil else { return }

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
        await manager.sendNowPlaying(scrobble)
        guard currentTrackID == info.id, wasPlaying else { return }
        scheduleCommit(for: info)
    }

    private func handleStopped() {
        scrobbleTask?.cancel()
        scrobbleTask = nil
        currentTrackID = nil
        wasPlaying = false
        pendingScrobble = nil
        pendingScrobbleID = nil
        lastRaw = nil
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
            await self.manager.commit(scrobble)
            self.didScrobbleCurrent = true
            self.scrobbleTask = nil
        }
    }
}
