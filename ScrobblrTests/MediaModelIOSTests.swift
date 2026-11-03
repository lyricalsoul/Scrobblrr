//
//  MediaModelIOSTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

#if os(iOS)
import Testing
@testable import Scrobblr

@MainActor @Suite struct MediaModelIOSTests {
    @Test func attachObserversIsIdempotent() throws {
        let container = try makeContainer()
        let settings = Settings()
        let manager = ScrobblerManager(modelContainer: container, settings: settings)
        let model = MediaModel(manager: manager, settings: settings, modelContainer: container)
        model.attachObservers()
        let count = model.observerCount
        model.attachObservers()
        #expect(model.isObserving)
        #expect(model.observerCount == count)
        #expect(count > 0)
    }
}
#endif
