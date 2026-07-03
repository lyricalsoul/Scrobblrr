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
    private let session = LanguageModelSession(instructions: instructions)

    func correct(artist: String) async -> CorrectedEntity {
        // A stored rule (manual, or a previously learned correction) wins
        if let stored = CorrectionStore.storedCorrection(for: artist, entity: .artist, in: modelContext) {
            return stored
        }

        guard needsCorrection(artist: artist) else {
            return .from(original: artist)
        }

        guard let generated = try? await session.respond(to: artist, generating: ArtistFix.self) else {
            Logger.intelligence.error("Failed to correct artist \(artist, privacy: .public)")
            return .from(original: artist)
        }

        let corrected = generated.content
        if !artist.lowercased().hasPrefix(corrected.mainArtist.lowercased()) {
            Logger.intelligence.debug("Model returned “\(corrected.mainArtist, privacy: .public)” (\(corrected.reasoning, privacy: .public) for “\(artist, privacy: .public)”, ignoring")
            return .from(original: artist)
        }

        Logger.intelligence.debug("Corrected “\(artist, privacy: .public)” to “\(corrected.mainArtist, privacy: .public)” (\(corrected.reasoning, privacy: .public))")

        // Persist so we don't re-run the model for this artist again
        CorrectionStore.save(target: artist, replacement: corrected.mainArtist, entity: .artist, in: modelContext)
        return corrected.mainArtist == artist
            ? .from(original: artist)
            : .from(corrected: corrected, original: artist)
    }

    func needsCorrection(artist: String) -> Bool {
        return artist.contains(", ") || artist.contains(" & ")
    }
}
#endif
