//
//  AutoCorrector.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//

#if os(macOS)
import Foundation
import FoundationModels
import SwiftData
import os

@Generable
struct ArtistFix {
    @Guide(description: "One short sentence: is this a single act whose name happens to contain a comma/&/+, or a list of separate performers? Do you know any of the artists? What is their name? Does the original sentence start with the artist's name?")
    var reasoning: String

    @Guide(description: "The primary artist only, exactly as it should be displayed. No quotes, no extra text.")
    var mainArtist: String
}

let instructions = """
You are a music metadata cleaner. You receive an artist credit string and return only the primary artist — the act the track is credited to first.

If the string lists separate performers joined by a comma and/or &, keep only the first-listed name and drop the rest.
If the comma or & is actually part of one established act's own name — a band, duo, or stage name — return that full name unchanged instead of splitting it.
If there are two acts, their names will be separated by a &, such as Drake & Travis Scott.
If there are more than two acts, their names will be separated by comma and &, with the & appearing near the last artist only, such as Artist 1, Artist 2 & Artist 3.
If the text is in Japanese, it will be separated by "と".
If you know one of the names in the credit belongs to an artist, then it's probably 2 or more acts. If the credit is PinkPantheress & Beyoncé, there are no artist with that name, nor will there ever be - the name to be returned is PinkPantheress.
The returned value must be the prefix of the original text. On the examples, notice how the returned artists are always the prefix.

Examples:
"PinkPantheress, Zara Larsson & Bree Runway" → PinkPantheress
"Tyler, The Creator" → Tyler, The Creator
"Beyoncé & Jay-Z" → Beyoncé
"Florence + the Machine" → Florence + the Machine
"Travis Scott & Drake" → Travis Scott
"Earth, Wind & Fire" → Earth, Wind & Fire
"三宅純と椎名林檎" → 三宅純
"AKRIILA, FaceBrooklyn & Milo j" → AKRIILA
"""

@ModelActor
actor AutoCorrector {
    typealias Splitter = @Sendable (String) async throws -> String

    private var splitter: Splitter = AutoCorrector.splitWithModel

    init(modelContainer: ModelContainer, splitter: @escaping Splitter) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.splitter = splitter
    }

    nonisolated static func splitWithModel(_ artist: String) async throws -> String {
        let generated = try await LanguageModelSession(instructions: instructions).respond(to: artist, generating: ArtistFix.self).content
        Logger.intelligence.debug("Model split “\(artist, privacy: .public)” into “\(generated.mainArtist, privacy: .public)” (\(generated.reasoning, privacy: .public))")
        return generated.mainArtist
    }

    nonisolated static func isValidPrefix(_ candidate: String, of credit: String) -> Bool {
        guard !candidate.isEmpty, credit.lowercased().hasPrefix(candidate.lowercased()) else { return false }
        let remainder = credit.dropFirst(candidate.count).drop { $0 == " " }
        return remainder.isEmpty || ",&+と".contains(remainder.first!)
    }

    func correct(artist: String) async -> CorrectedEntity {
        let ruleBased = CorrectionRules.applyCorrections(for: artist, type: .artist, in: modelContext)
        guard ruleBased.shouldScrobble, ruleBased.reason == nil else { return ruleBased }

        guard artist.contains(", ") || artist.contains(" & ") else {
            return .from(original: artist)
        }

        guard let split = try? await splitter(artist) else {
            Logger.intelligence.error("Failed to correct artist \(artist, privacy: .public)")
            return .from(original: artist)
        }

        guard Self.isValidPrefix(split, of: artist) else {
            Logger.intelligence.debug("Model returned “\(split, privacy: .public)” for “\(artist, privacy: .public)”, ignoring")
            return .from(original: artist)
        }

        // persist so we don't re-run the model for this artist again
        let row = ManualCorrection(kind: .artist, artistName: artist, replacement: split, isAutomatic: true)
        modelContext.insert(row)
        try? modelContext.save()
        return split == artist ? .from(original: artist) : .from(corrected: split, original: artist)
    }
}
#endif
