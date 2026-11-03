//
//  Backoff.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

struct Backoff {
    let base: Duration
    let max: Duration
    private var current: Duration

    init(base: Duration = .seconds(3), max: Duration = .seconds(300)) {
        self.base = base
        self.max = max
        current = base
    }

    mutating func next() -> Duration {
        defer { current = Swift.min(current * 2, max) }
        return current
    }

    mutating func reset() { current = base }
}
