//
//  AutoCorrector.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//

import Foundation
import FoundationModels
import SwiftData

@Generable
struct ArtistFix {
    @Guide(description: "One short sentence: is this a single act whose name happens to contain a comma/&/+, or a list of separate performers? Do you know any of the artists? What is their name?")
    var reasoning: String

    @Guide(description: "The primary artist only, exactly as it should be displayed. No quotes, no extra text.")
    var mainArtist: String
}

let instructions = """
You are a music metadata cleaner. You receive an artist credit string and return only the primary artist — the act the track is credited to first.

If the string lists separate performers joined by a comma and/or "&", keep only the first-listed name and drop the rest.
If the comma, "&", "+", or "and" is actually part of one established act's own name — a band, duo, or stage name — return that full name unchanged instead of splitting it.
If there are two acts, their names will be separated by a "&". If there are more than 2, they will be separated by comma and "&", with the "&" appearing on the last artist only. If the text is in Japanese, it will be separated by "と".

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

struct CorrectedEntity {
    let originalTitle: String
    let correctedTitle: String?
    let reason: String?

    /// Whether this entity should be scrobbled at all. `false` means a rule
    /// explicitly marked it as ignored (replacement was `nil`).
    let shouldScrobble: Bool

    var title : String {
        return correctedTitle ?? originalTitle
    }
    
    static func from(corrected artist: ArtistFix, original: String) -> CorrectedEntity {
        .init(originalTitle: original, correctedTitle: artist.mainArtist, reason: artist.reasoning, shouldScrobble: true)
    }
    
    static func from(original: String) -> CorrectedEntity {
        .init(originalTitle: original, correctedTitle: nil, reason: nil, shouldScrobble: true)
    }

    /// An entity that should not be scrobbled.
    static func skip(original: String, reason: String? = nil) -> CorrectedEntity {
        .init(originalTitle: original, correctedTitle: nil, reason: reason, shouldScrobble: false)
    }
}

/// Runs artist-name correction off the main actor: the on-device language model
/// inference and the SwiftData auto-correct store both live on this actor's own
/// background `ModelContext`, so neither blocks the UI.
@ModelActor
actor AutoCorrector {
    private let session = LanguageModelSession(instructions: instructions)

    func correctOrPassthrough(artist: String) async -> CorrectedEntity {
        // check if present on autocorrect database - if so, return the replacement
        if let known = lookup(target: artist, entity: .artist) {
            print("\(artist) will be replaced to \(known.replacement ?? "<nil>")")
            guard let replacement = known.replacement else {
                return .skip(original: artist) 
            }
            return CorrectedEntity(originalTitle: artist, correctedTitle: replacement, reason: nil, shouldScrobble: true)
        }

        if (!needsCorrection(artist: artist)) {
            return .from(original: artist)
        }
        
        guard let corrected = try? await correct(artist: artist) else {
            print("Failed to correct artist: \(artist)")
            return .from(original: artist) // couldn't correct?
        }
        
        if (corrected.mainArtist != artist) {
            // save this correction to autocorrect dictionary
            save(target: artist, replacement: corrected.mainArtist, entity: .artist)
            return .from(corrected: corrected.self, original: artist)
        } else {
            // same thing, add this artist to autocorrect dictionary to avoid extra calls to FM
            //save(target: artist, replacement: artist, entity: .artist)
            return .from(original: artist)
        }
    }
    
    func needsCorrection(artist: String) -> Bool {
        return artist.contains(", ") || artist.contains(" & ")
    }
    
    func correct(artist: String) async throws -> ArtistFix {
        let result = try await session.respond(to: artist, generating: ArtistFix.self)
        return result.content
    }

    // MARK: - Auto-correct store

    private func lookup(target: String, entity: CorrectionEntity) -> AutoCorrect? {
        // 1. Assign the parameter to a local constant
        let localTarget = target
        
        // 2. Use the local constant in the predicate
        let descriptor = FetchDescriptor<AutoCorrect>(
            predicate: #Predicate { $0.target == localTarget }
        )
        
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        return matches.first { $0.kind == entity }
    }

    /// Inserts (or updates) a correction rule. A `nil` replacement marks the
    /// entity as "do not scrobble".
    func save(target: String, replacement: String?, entity: CorrectionEntity) {
        // TODO: put this in the logger struct
        print("Saved \(replacement ?? "nil") as replacement to \(target) for \(entity)")
        
        if let existing = lookup(target: target, entity: entity) {
            existing.replacement = replacement
        } else {
            modelContext.insert(AutoCorrect(target: target, replacement: replacement, kind: entity))
        }
        try? modelContext.save()
    }
}
