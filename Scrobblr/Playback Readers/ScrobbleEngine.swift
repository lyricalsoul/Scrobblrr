//
//  ScrobbleEngine.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//
//  Platform-agnostic scrobble timing state machine. A platform-specific
//  playback reader (MediaRemote on macOS, MusicKit on iOS) translates its
//  native events into `GenericPlaybackInfo` and feeds them in via `update(_:)`.
//  The engine owns the "now playing" value the UI shows plus all the
//  announce / threshold / commit bookkeeping.

import SwiftUI
import os

@Observable
@MainActor
final class ScrobbleEngine {
    /// The currently playing track, for the UI. `nil` when nothing is playing.
    private(set) var current: GenericPlaybackInfo?

    @ObservationIgnored private let manager: ScrobblerManager
    @ObservationIgnored private let settings: Settings

    @ObservationIgnored private var currentTrackID: String?
    @ObservationIgnored private var wasPlaying = false
    @ObservationIgnored private var pendingScrobble: Scrobble?
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

    /// Feed the latest playback state. Pass `nil` when playback stops.
    func update(_ info: GenericPlaybackInfo?) {
        guard let info else {
            handleStopped()
            return
        }

        current = info
        Logger.playback.debug("Event: \(info.displayName, privacy: .public) playing=\(info.isPlaying) elapsed=\(info.elapsedTimeSeconds)s/\(info.durationSeconds)s")
        Task { await handle(info) }
    }

    // MARK: - Event handling

    private func handle(_ info: GenericPlaybackInfo) async {
        let isNewTrack = info.id != currentTrackID
        let playStateChanged = info.isPlaying != wasPlaying

        // The reader may emit frequent events for the same track & state
        // (progress ticks). Only react to real transitions — anything else is noise.
        guard isNewTrack || playStateChanged else {
            return
        }

        // Commit dedupe state synchronously, before any await, so a concurrent
        // event sees the updated state and treats itself as a no-op instead of
        // double-handling across the suspension points below.
        currentTrackID = info.id
        wasPlaying = info.isPlaying

        if isNewTrack {
            didScrobbleCurrent = false
            scrobbleTask?.cancel()
            scrobbleTask = nil

            let scrobble = await manager.prepare(info)
            // A newer track may have superseded this one during the await.
            guard currentTrackID == info.id else { return }
            pendingScrobble = scrobble
            guard scrobble != nil else { return }

            if info.isPlaying {
                Logger.playback.info("New track playing: \(info.displayName, privacy: .public)")
                await announceAndSchedule(for: info)
            } else {
                Logger.playback.info("New track is paused; holding without announcing: \(info.displayName, privacy: .public)")
            }
        } else if info.isPlaying {
            // Resumed.
            guard !didScrobbleCurrent, pendingScrobble != nil else { return }
            Logger.playback.info("Resumed: re-announcing and rescheduling for \(info.displayName, privacy: .public)")
            await announceAndSchedule(for: info)
        } else {
            // Paused.
            if scrobbleTask != nil {
                Logger.playback.info("Paused: cancelling scrobble countdown for \(info.displayName, privacy: .public)")
            }
            scrobbleTask?.cancel()
            scrobbleTask = nil
        }
    }

    /// Announces "now playing" and (re)schedules the commit, bailing if the
    /// track or play state changed while awaiting the network call.
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
            Logger.playback.info("Threshold reached, committing: \(scrobble.artist, privacy: .public) — \(scrobble.track, privacy: .public)")
            await self.manager.commit(scrobble)
            self.didScrobbleCurrent = true
            self.scrobbleTask = nil
        }
    }
}
