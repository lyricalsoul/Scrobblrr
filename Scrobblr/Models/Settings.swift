//
//  Settings.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//

import Foundation
import SwiftData

/// use ``shared(in:)`` to fetch the single instance used across the app
@Model
final class Settings {
    /// fraction of the track, e.g. `0.5` for 50%
    var scrobbleThreshold: Double

    /// seconds after which a track is scrobbled regardless of `scrobbleThreshold`
    var maxScrobbleSeconds: Int

    /// tracks shorter than this are never scrobbled
    var minTrackSeconds: Int

    var useArtistFix: Bool

    var showNowPlayingInMenu: Bool

    /// mac only
    var discordPresenceEnabled: Bool = true

    /// this device pushes its now playing for the cross-device relay
    var crossDevicePresenceEnabled: Bool = true

    /// this mac shows another device's now playing on discord
    var receiveCrossDevicePresenceEnabled: Bool = true

    /// experiment: recover a stale `SystemMusicPlayer` through `MPMusicPlayerController` instead of the audio session
    var useMPMusicPlayerRecovery: Bool = true

    init(
        scrobbleThreshold: Double = 0.5,
        maxScrobbleSeconds: Int = 240,
        minTrackSeconds: Int = 30,
        useArtistFix: Bool = true,
        showNowPlayingInMenu: Bool = true,
        discordPresenceEnabled: Bool = true,
        crossDevicePresenceEnabled: Bool = true,
        receiveCrossDevicePresenceEnabled: Bool = true,
        useMPMusicPlayerRecovery: Bool = true
    ) {
        self.scrobbleThreshold = scrobbleThreshold
        self.maxScrobbleSeconds = maxScrobbleSeconds
        self.minTrackSeconds = minTrackSeconds
        self.useArtistFix = useArtistFix
        self.showNowPlayingInMenu = showNowPlayingInMenu
        self.discordPresenceEnabled = discordPresenceEnabled
        self.crossDevicePresenceEnabled = crossDevicePresenceEnabled
        self.receiveCrossDevicePresenceEnabled = receiveCrossDevicePresenceEnabled
        self.useMPMusicPlayerRecovery = useMPMusicPlayerRecovery
    }

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
