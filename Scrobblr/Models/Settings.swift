//
//  Settings.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//
// App settings.
// How much % of the song must be scrobbled (50%) OR how much max time (3m)
// Whether the AI artist name fix should be used

import Foundation
import SwiftData

/// Persisted app settings. A single instance is expected to exist in the store;
/// use ``shared(in:)`` to fetch or create it.
@Model
final class Settings {
    /// Fraction of the track that must elapse before it is scrobbled (e.g. `0.5` for 50%).
    var scrobbleThreshold: Double

    /// Maximum listening time, in seconds, after which a track is scrobbled
    /// regardless of `scrobbleThreshold` (e.g. `180` for 3 minutes).
    var maxScrobbleSeconds: Int

    /// Tracks shorter than this (in seconds) are never scrobbled.
    var minTrackSeconds: Int

    /// Whether the on-device AI artist-name correction should be applied.
    var useArtistFix: Bool

    /// Whether the menu shows the currently playing track.
    var showNowPlayingInMenu: Bool

    init(
        scrobbleThreshold: Double = 0.5,
        maxScrobbleSeconds: Int = 240,
        minTrackSeconds: Int = 30,
        useArtistFix: Bool = true,
        showNowPlayingInMenu: Bool = true
    ) {
        self.scrobbleThreshold = scrobbleThreshold
        self.maxScrobbleSeconds = maxScrobbleSeconds
        self.minTrackSeconds = minTrackSeconds
        self.useArtistFix = useArtistFix
        self.showNowPlayingInMenu = showNowPlayingInMenu
    }

    /// Returns the single persisted settings instance, creating and saving a
    /// default one if none exists yet.
    @MainActor
    static func shared(in context: ModelContext) -> Settings {
        if let existing = try? context.fetch(FetchDescriptor<Settings>()).first {
            return existing
        }
        let created = Settings()
        context.insert(created)
        try? context.save()
        return created
    }
}
