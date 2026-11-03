//
//  GenericPlaybackInfoTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Foundation
import Testing
@testable import Scrobblr

@Suite struct GenericPlaybackInfoTests {
    @Test func equalityDistinguishesPlayState() {
        #expect(info(playing: true) != info(playing: false))
    }

    @Test func equalityDistinguishesCover() {
        let cover = URL(string: "https://example.com/a.jpg")
        #expect(info().withCoverURL(cover) != info())
    }

    @Test func equalityDistinguishesElapsed() {
        #expect(info(elapsed: 5) != info(elapsed: 6))
    }

    @Test func withPlayingKeepsEverythingElse() {
        let cover = URL(string: "https://example.com/a.jpg")
        let original = info(elapsed: 42, playing: true).withCoverURL(cover)
        let paused = original.withPlaying(false)
        #expect(!paused.isPlaying)
        #expect(paused.withPlaying(true) == original)
    }

    @Test func withMetadataKeepsTimingAndCover() {
        let cover = URL(string: "https://example.com/a.jpg")
        let original = info(duration: 300, elapsed: 42, playing: false).withCoverURL(cover)
        let result = original.withMetadata(from: Scrobble(artist: "New Artist", track: "New Song", album: "New Album", durationSeconds: 300, timestamp: Date()))
        #expect(result.artist == "New Artist")
        #expect(result.title == "New Song")
        #expect(result.album == "New Album")
        #expect(result.durationSeconds == 300)
        #expect(result.elapsedTimeSeconds == 42)
        #expect(!result.isPlaying)
        #expect(result.coverURL == cover)
    }

    @Test func driftPastDurationReturnsNil() {
        #expect(info(duration: 200, elapsed: 100).adjustedForRelayDrift(since: Date(timeIntervalSinceNow: -500)) == nil)
    }

    @Test func driftWhilePausedIsIdentity() {
        let paused = info(elapsed: 10, playing: false)
        #expect(paused.adjustedForRelayDrift(since: Date(timeIntervalSinceNow: -500)) == paused)
    }

    @Test func idIgnoresPlayState() {
        #expect(info(playing: true).id == info(playing: false).id)
    }
}
