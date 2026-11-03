//
//  PlaybackTrackerTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
import Foundation
@testable import Scrobblr

@Suite struct PlaybackTrackerTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    @Test func firstObservationIsNewTrack() {
        var tracker = PlaybackTracker()
        #expect(tracker.observe(info(), at: start, didScrobble: false) == .newTrack)
        #expect(tracker.observe(info("Other"), at: at(1), didScrobble: false) == .newTrack)
    }

    @Test func sameTrackSameStateIsNone() {
        var tracker = PlaybackTracker()
        _ = tracker.observe(info(), at: start, didScrobble: false)
        #expect(tracker.observe(info(), at: start, didScrobble: false) == .none)
    }

    @Test func heartbeatProgressionWithinToleranceIsNone() {
        var tracker = PlaybackTracker()
        _ = tracker.observe(info(elapsed: 10), at: start, didScrobble: false)
        #expect(tracker.observe(info(elapsed: 40), at: at(30), didScrobble: false) == .none)
        #expect(tracker.observe(info(elapsed: 74), at: at(60), didScrobble: false) == .none)
        #expect(tracker.observe(info(elapsed: 100), at: at(90), didScrobble: false) == .none)
    }

    @Test func pauseThenResume() {
        var tracker = PlaybackTracker()
        _ = tracker.observe(info(elapsed: 10), at: start, didScrobble: false)
        #expect(tracker.observe(info(elapsed: 20, playing: false), at: at(10), didScrobble: false) == .paused)
        #expect(tracker.observe(info(elapsed: 20), at: at(500), didScrobble: false) == .resumed)
        #expect(tracker.observe(info(elapsed: 30), at: at(510), didScrobble: false) == .none)
    }

    @Test func forwardSeek() {
        var tracker = PlaybackTracker()
        _ = tracker.observe(info(elapsed: 10), at: start, didScrobble: false)
        #expect(tracker.observe(info(elapsed: 100), at: at(5), didScrobble: false) == .seeked)
        #expect(tracker.observe(info(elapsed: 105), at: at(10), didScrobble: true) == .none)
        #expect(tracker.observe(info(elapsed: 150), at: at(11), didScrobble: true) == .seeked)
    }

    @Test func backwardSeekBeforeScrobbleIsSeeked() {
        var tracker = PlaybackTracker()
        _ = tracker.observe(info(elapsed: 60), at: start, didScrobble: false)
        #expect(tracker.observe(info(elapsed: 5), at: at(1), didScrobble: false) == .seeked)
    }

    @Test func backwardJumpAfterScrobbleIsRestarted() {
        var tracker = PlaybackTracker()
        _ = tracker.observe(info(elapsed: 0), at: start, didScrobble: false)
        #expect(tracker.observe(info(elapsed: 0), at: at(200), didScrobble: true) == .restarted)
    }

    @Test func resetMakesNextNewTrack() {
        var tracker = PlaybackTracker()
        _ = tracker.observe(info(), at: start, didScrobble: false)
        tracker.reset()
        #expect(tracker.observe(info(), at: start, didScrobble: false) == .newTrack)
    }

    @Test func pausedElapsedChangesIgnored() {
        var tracker = PlaybackTracker()
        _ = tracker.observe(info(elapsed: 50, playing: false), at: start, didScrobble: false)
        #expect(tracker.observe(info(elapsed: 0, playing: false), at: at(100), didScrobble: true) == .none)
        #expect(tracker.observe(info(elapsed: 120, playing: false), at: at(101), didScrobble: false) == .none)
    }
}
