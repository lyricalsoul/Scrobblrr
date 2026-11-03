//
//  StaleEntryMonitor.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Foundation

struct StaleEntryMonitor {
    enum Decision: Equatable { case none, recovered(streak: Int), recover(streak: Int) }

    var threshold = 5
    var cooldown: TimeInterval = 120
    var maxCooldown: TimeInterval = 3600
    private var streak = 0
    private(set) var attempts = 0
    private var lastRecovery: Date?

    mutating func record(hasEntry: Bool, isBackgrounded: Bool, at now: Date) -> Decision {
        if hasEntry {
            defer { streak = 0; attempts = 0 }
            return streak >= threshold ? .recovered(streak: streak) : .none
        }
        streak += 1
        guard streak >= threshold, isBackgrounded else { return .none }
        if let lastRecovery, now.timeIntervalSince(lastRecovery) < min(cooldown * pow(2, Double(attempts - 1)), maxCooldown) { return .none }
        lastRecovery = now
        attempts += 1
        return .recover(streak: streak)
    }
}
