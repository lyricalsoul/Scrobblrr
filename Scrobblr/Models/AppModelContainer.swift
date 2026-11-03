//
//  AppModelContainer.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import SwiftData

enum AppModelContainer {
    private static let schema = Schema([Correction.self, ManualCorrection.self, CachedArtist.self, Settings.self, QueuedScrobble.self])

    static func make(synced: () throws -> ModelContainer = { try container(cloud: true) }, local: () throws -> ModelContainer = { try container(cloud: false) }) throws -> ModelContainer {
        do { return try synced() } catch { return try local() }
    }

    static func configurations(cloud: Bool) -> [ModelConfiguration] {
        [
            ModelConfiguration("synced", schema: Schema([Correction.self, ManualCorrection.self, CachedArtist.self]), cloudKitDatabase: cloud ? .private("iCloud.io.lyricalsoul.Scrobblrr") : .none),
            ModelConfiguration("local", schema: Schema([Settings.self, QueuedScrobble.self]), cloudKitDatabase: .none),
        ]
    }

    private static func container(cloud: Bool) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: configurations(cloud: cloud))
    }
}
