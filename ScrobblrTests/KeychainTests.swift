//
//  KeychainTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
import Foundation
@testable import Scrobblr

private let keychainAvailable: Bool = {
    let service = "test.probe." + UUID().uuidString
    defer { Keychain.remove("probe", service: service) }
    Keychain.set("v", for: "probe", service: service)
    return Keychain.get("probe", service: service) == "v"
}()

@Suite(.enabled(if: keychainAvailable, "keychain unavailable under this test host")) struct KeychainTests {
    let service = "test." + UUID().uuidString

    @Test func setGetRoundTrip() {
        defer { Keychain.remove("a", service: service) }
        Keychain.set("secret", for: "a", service: service)
        #expect(Keychain.get("a", service: service) == "secret")
    }

    @Test func overwriteUpdates() {
        defer { Keychain.remove("a", service: service) }
        Keychain.set("one", for: "a", service: service)
        Keychain.set("two", for: "a", service: service)
        #expect(Keychain.get("a", service: service) == "two")
    }

    @Test func setNilRemoves() {
        defer { Keychain.remove("a", service: service) }
        Keychain.set("one", for: "a", service: service)
        Keychain.set(nil, for: "a", service: service)
        #expect(Keychain.get("a", service: service) == nil)
    }

    @Test func missingReturnsNil() {
        #expect(Keychain.get("missing", service: service) == nil)
    }

    @Test func accountsAreIsolated() {
        defer { Keychain.remove("a", service: service); Keychain.remove("b", service: service) }
        Keychain.set("one", for: "a", service: service)
        Keychain.set("two", for: "b", service: service)
        Keychain.remove("a", service: service)
        #expect(Keychain.get("a", service: service) == nil)
        #expect(Keychain.get("b", service: service) == "two")
    }

    @Test func servicesAreIsolated() {
        let other = "test." + UUID().uuidString
        defer { Keychain.remove("a", service: service); Keychain.remove("a", service: other) }
        Keychain.set("one", for: "a", service: service)
        #expect(Keychain.get("a", service: other) == nil)
        Keychain.set("two", for: "a", service: other)
        #expect(Keychain.get("a", service: service) == "one")
    }
}
