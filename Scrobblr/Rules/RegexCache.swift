//
//  RegexCache.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/1/26.
//

import Foundation

nonisolated final class RegexCache: @unchecked Sendable {
    static let shared = RegexCache()

    private let lock = NSLock()
    private var cache: [String: Regex<AnyRegexOutput>?] = [:]
    private var compiled = 0

    var compileCount: Int {
        lock.withLock { compiled }
    }

    func regex(for pattern: String) -> Regex<AnyRegexOutput>? {
        lock.withLock {
            if let cached = cache[pattern] { return cached }
            compiled += 1
            let regex = try? Regex(pattern).ignoresCase()
            cache[pattern] = .some(regex)
            return regex
        }
    }
}
