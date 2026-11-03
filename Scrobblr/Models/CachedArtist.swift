//
//  CachedArtist.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/26/26.
//

import Foundation
import SwiftData

@Model
final class CachedArtist {
    // no adding unique or it crashes the app
    var songID: String = ""
    var artistName: String = ""
    var lastAccess: Date = Date()

    init(songID: String, artistName: String) {
        self.songID = songID
        self.artistName = artistName
        self.lastAccess = Date()
    }

    /// entries not looked up within this long are pruned
    private static let maxAge: TimeInterval = 60 * 60 * 24 * 90 // 90 days

    private static let touchInterval: TimeInterval = 60 * 60 * 24

    static func cachedName(forSongID songID: String, in context: ModelContext) -> String? {
        let descriptor = FetchDescriptor<CachedArtist>(predicate: #Predicate { $0.songID == songID })
        guard let entry = (try? context.fetch(descriptor))?.first else { return nil }
        if -entry.lastAccess.timeIntervalSinceNow > touchInterval { entry.lastAccess = Date() }
        return entry.artistName
    }

    static func cache(songID: String, artistName: String, in context: ModelContext) {
        let existed = ((try? context.fetchCount(FetchDescriptor<CachedArtist>(predicate: #Predicate { $0.songID == songID }))) ?? 0) > 0
        context.insert(CachedArtist(songID: songID, artistName: artistName))
        pruneStale(in: context)
        if existed { dedupe(in: context) } else { try? context.save() }
    }

    static func dedupe(in context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<CachedArtist>(sortBy: [SortDescriptor(\.lastAccess, order: .reverse)])) else { return }
        var seen = Set<String>()
        for entry in all where !seen.insert(entry.songID).inserted { context.delete(entry) }
        try? context.save()
    }

    private static func pruneStale(in context: ModelContext) {
        let cutoff = Date(timeIntervalSinceNow: -maxAge)
        let descriptor = FetchDescriptor<CachedArtist>(predicate: #Predicate { $0.lastAccess < cutoff })
        guard let stale = try? context.fetch(descriptor), !stale.isEmpty else { return }
        stale.forEach { context.delete($0) }
    }
}
