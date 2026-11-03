//
//  CachedArtistTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/26/26.
//

import Foundation
import Testing
import SwiftData
@testable import Scrobblr

@Suite struct CachedArtistTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CachedArtist.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func missingSongReturnsNil() throws {
        let context = try makeContext()
        #expect(CachedArtist.cachedName(forSongID: "abc", in: context) == nil)
    }

    @Test func cacheThenLookupRoundTrips() throws {
        let context = try makeContext()
        CachedArtist.cache(songID: "abc", artistName: "Faye Webster", in: context)
        #expect(CachedArtist.cachedName(forSongID: "abc", in: context) == "Faye Webster")
    }

    private func entry(_ id: String, daysAgo: Double) -> CachedArtist {
        let entry = CachedArtist(songID: id, artistName: id)
        entry.lastAccess = Date(timeIntervalSinceNow: -daysAgo * 86400)
        return entry
    }

    @Test func cachedArtistDedupeKeepsNewest() throws {
        let context = try makeContext()
        [entry("a", daysAgo: 5), entry("a", daysAgo: 1), entry("a", daysAgo: 9)].forEach(context.insert)
        CachedArtist.dedupe(in: context)
        let rows = try context.fetch(FetchDescriptor<CachedArtist>())
        #expect(rows.count == 1)
        #expect(abs(rows[0].lastAccess.timeIntervalSinceNow + 86400) < 5)
    }

    @Test func cachedArtistDedupeLeavesDistinctSongs() throws {
        let context = try makeContext()
        [entry("a", daysAgo: 1), entry("b", daysAgo: 1)].forEach(context.insert)
        CachedArtist.dedupe(in: context)
        #expect(try context.fetch(FetchDescriptor<CachedArtist>()).count == 2)
    }

    @Test func cachedNameSkipsRecentTouch() throws {
        let context = try makeContext()
        let recent = entry("a", daysAgo: 0.5)
        let before = recent.lastAccess
        context.insert(recent)
        _ = CachedArtist.cachedName(forSongID: "a", in: context)
        #expect(recent.lastAccess == before)
    }

    @Test func cachedNameRefreshesOldTouch() throws {
        let context = try makeContext()
        let old = entry("a", daysAgo: 2)
        context.insert(old)
        _ = CachedArtist.cachedName(forSongID: "a", in: context)
        #expect(abs(old.lastAccess.timeIntervalSinceNow) < 5)
    }

    @Test func pruneRemovesStaleOnly() throws {
        let context = try makeContext()
        [entry("old", daysAgo: 100), entry("fresh", daysAgo: 10)].forEach(context.insert)
        CachedArtist.cache(songID: "new", artistName: "n", in: context)
        let ids = Set(try context.fetch(FetchDescriptor<CachedArtist>()).map(\.songID))
        #expect(ids == ["fresh", "new"])
    }

    @Test func cacheTwiceLeavesOneRow() throws {
        let context = try makeContext()
        CachedArtist.cache(songID: "a", artistName: "x", in: context)
        CachedArtist.cache(songID: "a", artistName: "y", in: context)
        #expect(try context.fetch(FetchDescriptor<CachedArtist>()).count == 1)
    }
}
