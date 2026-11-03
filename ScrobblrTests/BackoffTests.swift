//
//  BackoffTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
@testable import Scrobblr

@Suite struct BackoffTests {
    @Test func doublesThenCaps() {
        var backoff = Backoff(base: .seconds(3), max: .seconds(20))
        let delays = (0..<5).map { _ in backoff.next() }
        #expect(delays == [.seconds(3), .seconds(6), .seconds(12), .seconds(20), .seconds(20)])
    }

    @Test func resetReturnsToBase() {
        var backoff = Backoff()
        _ = backoff.next()
        _ = backoff.next()
        backoff.reset()
        #expect(backoff.next() == .seconds(3))
    }
}
