//
//  AppModelContainerTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
import SwiftData
@testable import Scrobblr

@Suite struct AppModelContainerTests {
    struct Boom: Error {}

    @Test func makeFallsBackToLocalWhenSyncedThrows() throws {
        let expected = try makeContainer()
        let result = try AppModelContainer.make(synced: { throw Boom() }, local: { expected })
        #expect(result === expected)
    }

    @Test func fallbackOpensSameStoresWithoutCloudKit() {
        let names = AppModelContainer.configurations(cloud: false).map(\.name)
        #expect(names == AppModelContainer.configurations(cloud: true).map(\.name))
        #expect(names == ["synced", "local"])
        #expect(AppModelContainer.configurations(cloud: false).allSatisfy { String(describing: $0.cloudKitDatabase) == String(describing: ModelConfiguration.CloudKitDatabase.none) })
    }

    @Test func makeThrowsWhenBothFail() {
        #expect(throws: Boom.self) {
            try AppModelContainer.make(synced: { throw Boom() }, local: { throw Boom() })
        }
    }
}
