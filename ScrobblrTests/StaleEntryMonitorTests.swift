//
//  StaleEntryMonitorTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
import Foundation
@testable import Scrobblr

@Suite struct StaleEntryMonitorTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func feed(_ monitor: inout StaleEntryMonitor, count: Int, backgrounded: Bool, at date: Date) -> [StaleEntryMonitor.Decision] {
        (0..<count).map { _ in monitor.record(hasEntry: false, isBackgrounded: backgrounded, at: date) }
    }

    @Test func belowThresholdDoesNothing() {
        var monitor = StaleEntryMonitor()
        #expect(feed(&monitor, count: 4, backgrounded: true, at: t0).allSatisfy { $0 == .none })
    }

    @Test(arguments: [1, 5, 8])
    func atThresholdWhileBackgroundedRecovers(threshold: Int) {
        var monitor = StaleEntryMonitor(threshold: threshold)
        #expect(feed(&monitor, count: threshold - 1, backgrounded: true, at: t0).allSatisfy { $0 == .none })
        #expect(monitor.record(hasEntry: false, isBackgrounded: true, at: t0) == .recover(streak: threshold))
    }

    @Test func foregroundNeverRecovers() {
        var monitor = StaleEntryMonitor()
        #expect(feed(&monitor, count: 20, backgrounded: false, at: t0).allSatisfy { $0 == .none })
    }

    @Test func streakKeepsGrowingWhileForegrounded() {
        var monitor = StaleEntryMonitor()
        _ = feed(&monitor, count: 20, backgrounded: false, at: t0)
        #expect(monitor.record(hasEntry: false, isBackgrounded: true, at: t0) == .recover(streak: 21))
    }

    @Test func cooldownSuppressesSecondRecovery() {
        var monitor = StaleEntryMonitor()
        _ = feed(&monitor, count: 4, backgrounded: true, at: t0)
        #expect(monitor.record(hasEntry: false, isBackgrounded: true, at: t0) == .recover(streak: 5))
        #expect(monitor.record(hasEntry: false, isBackgrounded: true, at: t0.addingTimeInterval(119)) == .none)
    }

    @Test func cooldownExpiresAndRecoversAgain() {
        var monitor = StaleEntryMonitor()
        _ = feed(&monitor, count: 5, backgrounded: true, at: t0)
        #expect(monitor.record(hasEntry: false, isBackgrounded: true, at: t0.addingTimeInterval(120)) == .recover(streak: 6))
    }

    @Test func cooldownDoublesWithEachAttemptUpToTheCap() {
        var monitor = StaleEntryMonitor(maxCooldown: 400)
        _ = feed(&monitor, count: 5, backgrounded: true, at: t0)
        #expect(monitor.attempts == 1)
        #expect(monitor.record(hasEntry: false, isBackgrounded: true, at: t0.addingTimeInterval(120)) == .recover(streak: 6))
        #expect(monitor.record(hasEntry: false, isBackgrounded: true, at: t0.addingTimeInterval(120 + 239)) == .none)
        #expect(monitor.record(hasEntry: false, isBackgrounded: true, at: t0.addingTimeInterval(120 + 240)) == .recover(streak: 8))
        #expect(monitor.record(hasEntry: false, isBackgrounded: true, at: t0.addingTimeInterval(360 + 399)) == .none)
        #expect(monitor.record(hasEntry: false, isBackgrounded: true, at: t0.addingTimeInterval(360 + 400)) == .recover(streak: 10))
        #expect(monitor.attempts == 4)
    }

    @Test func entryReturningResetsTheBackoff() {
        var monitor = StaleEntryMonitor()
        _ = feed(&monitor, count: 5, backgrounded: true, at: t0)
        _ = monitor.record(hasEntry: true, isBackgrounded: true, at: t0.addingTimeInterval(10))
        #expect(monitor.attempts == 0)
    }

    @Test func entryAfterStreakReportsRecovered() {
        var monitor = StaleEntryMonitor()
        _ = feed(&monitor, count: 7, backgrounded: false, at: t0)
        #expect(monitor.record(hasEntry: true, isBackgrounded: false, at: t0) == .recovered(streak: 7))
        #expect(monitor.record(hasEntry: true, isBackgrounded: false, at: t0) == .none)
    }

    @Test func entryResetsStreak() {
        var monitor = StaleEntryMonitor()
        _ = feed(&monitor, count: 4, backgrounded: true, at: t0)
        #expect(monitor.record(hasEntry: true, isBackgrounded: true, at: t0) == .none)
        #expect(feed(&monitor, count: 4, backgrounded: true, at: t0).allSatisfy { $0 == .none })
    }
}
