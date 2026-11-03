//
//  AutoCorrectorTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Scrobblr

final class SplitterStub: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let result: Result<String, Error>

    init(_ result: Result<String, Error>) { self.result = result }

    var calls: Int { lock.withLock { count } }

    var splitter: @Sendable (String) async throws -> String {
        { [self] _ in
            lock.withLock { count += 1 }
            return try result.get()
        }
    }
}

struct AutoCorrectorTests {
    private struct Failure: Error {}

    private func corrector(_ stub: SplitterStub) throws -> (AutoCorrector, ModelContainer) {
        let container = try makeContainer()
        return (AutoCorrector(modelContainer: container, splitter: stub.splitter), container)
    }

    @Test func returnsOriginalWhenNoSeparator() async throws {
        let stub = SplitterStub(.success("Drake"))
        let (sut, _) = try corrector(stub)
        let result = await sut.correct(artist: "Drake")
        #expect(result.correctedTitle == nil)
        #expect(stub.calls == 0)
    }

    @Test func splitsAndPersistsAutomaticCorrection() async throws {
        let stub = SplitterStub(.success("PinkPantheress"))
        let (sut, container) = try corrector(stub)
        let result = await sut.correct(artist: "PinkPantheress, Zara Larsson & Bree Runway")
        #expect(result.correctedTitle == "PinkPantheress")
        let rows = try ModelContext(container).fetch(FetchDescriptor<ManualCorrection>())
        #expect(rows.count == 1)
        #expect(rows.first?.isAutomatic == true)
        #expect(rows.first?.replacement == "PinkPantheress")
    }

    @Test func rejectsMidWordPrefix() async throws {
        let stub = SplitterStub(.success("Ear"))
        let (sut, container) = try corrector(stub)
        let result = await sut.correct(artist: "Earth, Wind & Fire")
        #expect(result.correctedTitle == nil)
        #expect(try ModelContext(container).fetch(FetchDescriptor<ManualCorrection>()).isEmpty)
    }

    @Test func rejectsNonPrefix() async throws {
        let stub = SplitterStub(.success("Fire"))
        let (sut, _) = try corrector(stub)
        let result = await sut.correct(artist: "Earth, Wind & Fire")
        #expect(result.correctedTitle == nil)
    }

    @Test func splitterErrorFallsBackToOriginal() async throws {
        let stub = SplitterStub(.failure(Failure()))
        let (sut, _) = try corrector(stub)
        let result = await sut.correct(artist: "A, B & C")
        #expect(result.correctedTitle == nil)
        #expect(result.shouldScrobble)
    }

    @Test func secondCallUsesStoredCorrection() async throws {
        let stub = SplitterStub(.success("A"))
        let (sut, _) = try corrector(stub)
        _ = await sut.correct(artist: "A, B & C")
        let second = await sut.correct(artist: "A, B & C")
        #expect(second.correctedTitle == "A")
        #expect(stub.calls == 1)
    }

    @Test func manualRuleWinsBeforeSplitter() async throws {
        let stub = SplitterStub(.success("Earth"))
        let (sut, container) = try corrector(stub)
        let context = ModelContext(container)
        context.insert(ManualCorrection(kind: .artist, artistName: "Earth, Wind & Fire", replacement: "EWF"))
        try context.save()
        let result = await sut.correct(artist: "Earth, Wind & Fire")
        #expect(result.correctedTitle == "EWF")
        #expect(stub.calls == 0)
    }

    @Test func identityResultIsStoredOnceAndNotRerun() async throws {
        let stub = SplitterStub(.success("Tyler, The Creator"))
        let (sut, container) = try corrector(stub)
        _ = await sut.correct(artist: "Tyler, The Creator")
        let second = await sut.correct(artist: "Tyler, The Creator")
        #expect(second.correctedTitle == "Tyler, The Creator")
        #expect(stub.calls == 1)
        #expect(try ModelContext(container).fetch(FetchDescriptor<ManualCorrection>()).count == 1)
    }

    @Test func nonMatchingArtistStillReachesSplitter() async throws {
        let stub = SplitterStub(.success("A"))
        let (sut, container) = try corrector(stub)
        let context = ModelContext(container)
        context.insert(ManualCorrection(kind: .artist, artistName: "Other, Act", replacement: "Other"))
        try context.save()
        let result = await sut.correct(artist: "A, B & C")
        #expect(result.correctedTitle == "A")
        #expect(stub.calls == 1)
    }

    @Test(arguments: [
        ("三宅純", "三宅純と椎名林檎", true),
        ("Florence", "Florence + the Machine", true),
        ("Beyoncé", "Beyoncé & Jay-Z", true),
        ("Tyler", "Tyler, The Creator", true),
        ("Drake", "Drake", true),
        ("drake", "Drake & Future", true),
        ("Ear", "Earth, Wind & Fire", false),
        ("Fire", "Earth, Wind & Fire", false),
        ("", "Drake & Future", false),
    ])
    func isValidPrefix(candidate: String, credit: String, expected: Bool) {
        #expect(AutoCorrector.isValidPrefix(candidate, of: credit) == expected)
    }
}
#endif
