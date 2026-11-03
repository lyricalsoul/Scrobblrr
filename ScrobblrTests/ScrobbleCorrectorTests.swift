//
//  ScrobbleCorrectorTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
import Foundation
import SwiftData
@testable import Scrobblr

@Suite @MainActor struct ScrobbleCorrectorTests {
    private final class Calls { var artists: [String] = [] }

    private let container = try! makeContainer()

    private func make(useArtistFix: Bool = false, fix: Bool = true) throws -> (ScrobbleCorrector, ModelContext, Calls) {
        let context = container.mainContext
        Correction.seedDefaultsIfNeeded(in: context)
        let settings = Settings.shared(in: context)
        settings.useArtistFix = useArtistFix
        let calls = Calls()
        let fixer: ((String) async -> CorrectedEntity)? = fix ? { artist in
            calls.artists.append(artist)
            return CorrectedEntity(originalTitle: artist, correctedTitle: "Fixed", reason: nil, shouldScrobble: true)
        } : nil
        return (ScrobbleCorrector(context: context, settings: settings, fixArtist: fixer), context, calls)
    }

    @Test func usesArtistFixWhenEnabled() async throws {
        let (corrector, _, calls) = try make(useArtistFix: true)
        let scrobble = await corrector.corrected(from: info(artist: "A feat. B"))
        #expect(scrobble?.artist == "Fixed")
        #expect(calls.artists == ["A feat. B"])
    }

    @Test func usesRulesWhenArtistFixDisabled() async throws {
        let (corrector, _, calls) = try make(useArtistFix: false)
        let scrobble = await corrector.corrected(from: info(artist: "Plain"))
        #expect(scrobble?.artist == "Plain")
        #expect(calls.artists.isEmpty)
    }

    @Test func usesRulesWhenNoFixerEvenIfEnabled() async throws {
        let (corrector, _, _) = try make(useArtistFix: true, fix: false)
        #expect(await corrector.corrected(from: info(artist: "Plain"))?.artist == "Plain")
    }

    @Test func skipOnTrackReturnsNil() async throws {
        let (corrector, context, _) = try make()
        context.insert(ManualCorrection(kind: .track, trackName: "Song", albumName: "Album", artistName: "Artist", replacement: nil))
        #expect(await corrector.corrected(from: info()) == nil)
    }

    @Test func skipOnAlbumReturnsNil() async throws {
        let (corrector, context, _) = try make()
        context.insert(ManualCorrection(kind: .album, albumName: "Album", artistName: "Artist", replacement: nil))
        #expect(await corrector.corrected(from: info()) == nil)
    }

    @Test func artistSkipReturnsNil() async throws {
        let (corrector, context, _) = try make()
        context.insert(ManualCorrection(kind: .artist, artistName: "Artist", replacement: nil))
        #expect(await corrector.corrected(from: info()) == nil)
    }

    @Test func nilAlbumPassesThrough() async throws {
        let (corrector, _, _) = try make()
        let scrobble = await corrector.corrected(from: info(album: nil))
        #expect(scrobble != nil)
        #expect(scrobble?.album == nil)
    }

    @Test func timestampIsEventDateMinusElapsed() async throws {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let (corrector, _, _) = try make()
        let scrobble = await corrector.corrected(from: info(duration: 200, elapsed: 42), at: fixed)
        #expect(scrobble?.timestamp == fixed.addingTimeInterval(-42))
        #expect(scrobble?.durationSeconds == 200)
    }

    @Test func emptyStringsDoNotCrash() async throws {
        let (corrector, _, _) = try make()
        let scrobble = await corrector.corrected(from: info("", artist: "", album: ""))
        #expect(scrobble?.track == "")
        #expect(scrobble?.artist == "")
    }

    @Test func stripsRemasterFromTrackAndAlbum() async throws {
        let (corrector, _, _) = try make()
        let scrobble = await corrector.corrected(from: info("Song (Remastered 2011)", album: "Album (Remastered)"))
        #expect(scrobble?.track == "Song")
        #expect(scrobble?.album == "Album")
    }
}
