//
//  RegexCacheTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/1/26.
//

import Testing
@testable import Scrobblr

@Suite struct RegexCacheTests {
    @Test func sameCompiledOnce() {
        let cache = RegexCache()
        #expect(cache.regex(for: "foo") != nil)
        #expect(cache.regex(for: "foo") != nil)
        #expect(cache.compileCount == 1)
    }

    @Test func invalidPatternReturnsNilAndIsCached() {
        let cache = RegexCache()
        #expect(cache.regex(for: "(") == nil)
        #expect(cache.regex(for: "(") == nil)
        #expect(cache.compileCount == 1)
    }

    @Test func patternsMatchCaseInsensitively() throws {
        let cache = RegexCache()
        let regex = try #require(cache.regex(for: "remaster"))
        #expect(try regex.firstMatch(in: "Song REMASTER") != nil)
    }
}
