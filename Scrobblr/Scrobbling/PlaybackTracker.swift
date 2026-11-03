//
//  PlaybackTracker.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Foundation

enum PlaybackChange: Equatable {
    case none, newTrack, resumed, paused, seeked, restarted
}

struct PlaybackTracker {
    static let seekTolerance = 5

    private var last: (id: String, isPlaying: Bool, elapsed: Int, at: Date)?

    mutating func observe(_ info: GenericPlaybackInfo, at date: Date, didScrobble: Bool) -> PlaybackChange {
        defer { last = (info.id, info.isPlaying, info.elapsedTimeSeconds, date) }
        guard let last, last.id == info.id else { return .newTrack }
        if last.isPlaying != info.isPlaying { return info.isPlaying ? .resumed : .paused }
        guard info.isPlaying, let expected = position(at: date) else { return .none }
        let drift = info.elapsedTimeSeconds - expected
        guard abs(drift) > Self.seekTolerance else { return .none }
        return drift < 0 && didScrobble ? .restarted : .seeked
    }

    /// the last observed position extrapolated to `date` while playing
    func position(at date: Date) -> Int? {
        guard let last else { return nil }
        return last.isPlaying ? last.elapsed + Int(date.timeIntervalSince(last.at).rounded()) : last.elapsed
    }

    mutating func reset() {
        last = nil
    }
}
