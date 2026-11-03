//
//  CorrectionRulesTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/26/26.
//

import Testing
import SwiftData
@testable import Scrobblr

@Suite struct CorrectionRulesTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Correction.self, ManualCorrection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func regexStripsWithEmptyReplacement() throws {
        let context = try makeContext()
        context.insert(Correction(title: "remaster", pattern: Correction.trailingNoisePattern("remaster(?:ed)?"), replacement: "", entities: [.track]))

        let result = CorrectionRules.applyCorrections(for: "Song Title (Remastered 2011)", type: .track, in: context)
        #expect(result.title == "Song Title")
        #expect(result.reason == "remaster")
    }

    @Test func regexStripsStackedMatches() throws {
        let context = try makeContext()
        context.insert(Correction(title: "remaster", pattern: Correction.trailingNoisePattern("remaster(?:ed)?"), replacement: "", entities: [.track]))
        context.insert(Correction(title: "single", pattern: Correction.trailingNoisePattern("single version"), replacement: "", entities: [.track]))

        let result = CorrectionRules.applyCorrections(for: "Song Title (Single Version) (Remastered 2011)", type: .track, in: context)
        #expect(result.title == "Song Title")
    }

    @Test func regexSkipsWhenReplacementIsNil() throws {
        let context = try makeContext()
        context.insert(Correction(title: "skip", pattern: "^Bad.*$", replacement: nil, entities: [.track]))

        let result = CorrectionRules.applyCorrections(for: "Bad Track", type: .track, in: context)
        #expect(!result.shouldScrobble)
    }

    @Test func disabledRulesDoNotApply() throws {
        let context = try makeContext()
        context.insert(Correction(title: "remaster", pattern: Correction.trailingNoisePattern("remaster(?:ed)?"), replacement: "", entities: [.track], isEnabled: false))

        let result = CorrectionRules.applyCorrections(for: "Song Title (Remastered 2011)", type: .track, in: context)
        #expect(result.title == "Song Title (Remastered 2011)")
    }

    @Test func rulesScopedToOtherEntitiesDoNotApply() throws {
        let context = try makeContext()
        context.insert(Correction(title: "deluxe", pattern: Correction.trailingNoisePattern("deluxe edition"), replacement: "", entities: [.album]))

        let result = CorrectionRules.applyCorrections(for: "Album Title (Deluxe Edition)", type: .track, in: context)
        #expect(result.title == "Album Title (Deluxe Edition)")
    }

    @Test func multiEntityRuleAppliesToBothEntities() throws {
        let context = try makeContext()
        context.insert(Correction(title: "remaster", pattern: Correction.trailingNoisePattern("remaster(?:ed)?"), replacement: "", entities: [.track, .album]))

        let trackResult = CorrectionRules.applyCorrections(for: "Track (Remastered)", type: .track, in: context)
        let albumResult = CorrectionRules.applyCorrections(for: "Album (Remastered)", type: .album, in: context)
        #expect(trackResult.title == "Track")
        #expect(albumResult.title == "Album")
    }

    @Test func unaffectedTitlePassesThrough() throws {
        let context = try makeContext()
        context.insert(Correction(title: "remaster", pattern: Correction.trailingNoisePattern("remaster(?:ed)?"), replacement: "", entities: [.track]))

        let result = CorrectionRules.applyCorrections(for: "Plain Title", type: .track, in: context)
        #expect(result.title == "Plain Title")
        #expect(result.shouldScrobble)
    }

    @Test func zeroWidthPatternDoesNotHang() throws {
        let context = try makeContext()
        context.insert(Correction(title: "trailing whitespace", pattern: "\\s*$", replacement: "", entities: [.track]))

        let result = CorrectionRules.applyCorrections(for: "Some Song", type: .track, in: context)
        #expect(result.title == "Some Song")
    }

    @Test func manualArtistOverrideWins() throws {
        let context = try makeContext()
        context.insert(Correction(title: "noop", pattern: "^Bad Artist$", replacement: "Regex Wins", entities: [.artist]))
        context.insert(ManualCorrection(kind: .artist, artistName: "Bad Artist", replacement: "Good Artist"))

        let result = CorrectionRules.applyCorrections(for: "Bad Artist", type: .artist, in: context)
        #expect(result.title == "Good Artist")
    }

    @Test func manualAlbumOverrideRequiresMatchingArtist() throws {
        let context = try makeContext()
        context.insert(ManualCorrection(kind: .album, albumName: "Greatest Hits", artistName: "Artist A", replacement: "Fixed Album"))

        let matching = CorrectionRules.applyCorrections(for: "Greatest Hits", type: .album, artist: "Artist A", in: context)
        let nonMatching = CorrectionRules.applyCorrections(for: "Greatest Hits", type: .album, artist: "Artist B", in: context)
        #expect(matching.title == "Fixed Album")
        #expect(nonMatching.title == "Greatest Hits")
    }

    @Test func manualTrackOverrideRequiresMatchingAlbumAndArtist() throws {
        let context = try makeContext()
        context.insert(ManualCorrection(kind: .track, trackName: "Intro", albumName: "Album A", artistName: "Artist A", replacement: "Fixed Intro"))

        let matching = CorrectionRules.applyCorrections(for: "Intro", type: .track, album: "Album A", artist: "Artist A", in: context)
        let wrongAlbum = CorrectionRules.applyCorrections(for: "Intro", type: .track, album: "Album B", artist: "Artist A", in: context)
        #expect(matching.title == "Fixed Intro")
        #expect(wrongAlbum.title == "Intro")
    }

    @Test func manualOverrideCanSkipScrobbling() throws {
        let context = try makeContext()
        context.insert(ManualCorrection(kind: .track, trackName: "Silence", albumName: "Album A", artistName: "Artist A", replacement: nil))

        let result = CorrectionRules.applyCorrections(for: "Silence", type: .track, album: "Album A", artist: "Artist A", in: context)
        #expect(!result.shouldScrobble)
    }

    @Test func manualOverrideStillMatchesForArtistAlbumTrack() throws {
        let context = try makeContext()
        context.insert(ManualCorrection(kind: .artist, artistName: "A", replacement: "A2"))
        context.insert(ManualCorrection(kind: .album, albumName: "Al", artistName: "A", replacement: "Al2"))
        context.insert(ManualCorrection(kind: .track, trackName: "T", albumName: "Al", artistName: "A", replacement: "T2"))

        #expect(CorrectionRules.applyCorrections(for: "A", type: .artist, in: context).title == "A2")
        #expect(CorrectionRules.applyCorrections(for: "Al", type: .album, artist: "A", in: context).title == "Al2")
        #expect(CorrectionRules.applyCorrections(for: "T", type: .track, album: "Al", artist: "A", in: context).title == "T2")
    }

    @Test(arguments: ["", "   "])
    func emptyAndWhitespaceTitlesDoNotCrash(title: String) throws {
        let context = try makeContext()
        context.insert(Correction(title: "remaster", pattern: Correction.trailingNoisePattern("remaster"), replacement: "", entities: [.track]))

        let result = CorrectionRules.applyCorrections(for: title, type: .track, in: context)
        #expect(result.title == title)
    }

    @Test func ruleEatingWholeTitleIsIgnored() throws {
        let context = try makeContext()
        context.insert(Correction(title: "all", pattern: "^.*$", replacement: "", entities: [.track]))

        let result = CorrectionRules.applyCorrections(for: "Song", type: .track, in: context)
        #expect(result.title == "Song")
        #expect(result.shouldScrobble)
    }

    @Test func skipRuleReturnsSkip() throws {
        let context = try makeContext()
        context.insert(Correction(title: "skip", pattern: "karaoke", replacement: nil, entities: [.track]))

        let result = CorrectionRules.applyCorrections(for: "Song (Karaoke)", type: .track, in: context)
        #expect(!result.shouldScrobble)
        #expect(result.reason == "skip")
    }

    @Test(arguments: [
        ("Song - 2011 Remaster", CorrectionEntity.track, "Song"),
        ("Song (Feat. X)", .track, "Song"),
        ("Album (Deluxe Edition)", .album, "Album"),
        ("Album - EP", .album, "Album"),
    ])
    func defaultRulesStripExpectedSuffixes(input: String, type: CorrectionEntity, expected: String) throws {
        let context = try makeContext()
        Correction.seedDefaultsIfNeeded(in: context)

        #expect(CorrectionRules.applyCorrections(for: input, type: type, in: context).title == expected)
    }
}
