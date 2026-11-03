//
//  CorrectionTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/26/26.
//

import Testing
import SwiftData
@testable import Scrobblr

@Suite struct CorrectionTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Correction.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func seedingInsertsAllDefaultsExactlyOnce() throws {
        let context = try makeContext()
        Correction.seedDefaultsIfNeeded(in: context)

        let firstPass = try context.fetch(FetchDescriptor<Correction>())
        #expect(firstPass.count == Correction.defaultRules.count)

        Correction.seedDefaultsIfNeeded(in: context)
        let secondPass = try context.fetch(FetchDescriptor<Correction>())
        #expect(secondPass.count == Correction.defaultRules.count)
    }

    @Test func seededRemasterRuleCoversTrackAndAlbum() throws {
        let context = try makeContext()
        Correction.seedDefaultsIfNeeded(in: context)

        let rules = try context.fetch(FetchDescriptor<Correction>())
        let remaster = try #require(rules.first { $0.title == "Remove - Remaster(ed)" })
        #expect(Set(remaster.entities) == Set([.track, .album]))
    }

    private func rule(_ pattern: String, enabled: Bool = true) -> Correction {
        Correction(title: pattern, pattern: pattern, replacement: "", entities: [.track], isEnabled: enabled)
    }

    @Test func dedupeKeepsOnePerPattern() throws {
        let context = try makeContext()
        [rule("a"), rule("a"), rule("a")].forEach(context.insert)
        Correction.dedupeDefaults(in: context)
        #expect(try context.fetch(FetchDescriptor<Correction>()).count == 1)
    }

    @Test func dedupePreservesDisabledState() throws {
        let context = try makeContext()
        [rule("a"), rule("a", enabled: false)].forEach(context.insert)
        Correction.dedupeDefaults(in: context)
        let rules = try context.fetch(FetchDescriptor<Correction>())
        #expect(rules.count == 1)
        #expect(rules[0].isEnabled == false)
    }

    @Test func dedupeLeavesDistinctPatternsAlone() throws {
        let context = try makeContext()
        [rule("a"), rule("b")].forEach(context.insert)
        Correction.dedupeDefaults(in: context)
        #expect(try context.fetch(FetchDescriptor<Correction>()).count == 2)
    }

    @Test func seedAfterRemoteDuplicatesYieldsDefaultCount() throws {
        let context = try makeContext()
        Correction.seedDefaultsIfNeeded(in: context)
        for (_, keyword, entities) in Correction.defaultRules {
            context.insert(Correction(title: "dup", pattern: Correction.trailingNoisePattern(keyword), replacement: "", entities: entities))
        }
        Correction.seedDefaultsIfNeeded(in: context)
        #expect(try context.fetch(FetchDescriptor<Correction>()).count == Correction.defaultRules.count)
    }

    @Test func dedupeKeepsRulesWithSamePatternButDifferentReplacement() throws {
        let context = try makeContext()
        context.insert(rule("a"))
        context.insert(Correction(title: "a", pattern: "a", replacement: "x", entities: [.track]))
        Correction.dedupeDefaults(in: context)
        #expect(try context.fetch(FetchDescriptor<Correction>()).count == 2)
    }

    @Test func dedupeKeepsRulesWithSamePatternButDifferentEntities() throws {
        let context = try makeContext()
        context.insert(rule("a"))
        context.insert(Correction(title: "a", pattern: "a", replacement: "", entities: [.album]))
        Correction.dedupeDefaults(in: context)
        #expect(try context.fetch(FetchDescriptor<Correction>()).count == 2)
    }
}
