//
//  AutoCorrector.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//

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

struct CorrectedEntity {
    let originalTitle: String
    let correctedTitle: String?
    let reason: String?

    /// Whether this entity should be scrobbled at all. `false` means a rule
    /// explicitly marked it as ignored (replacement was `nil`)
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

@ModelActor
actor AutoCorrector {
    private let session = LanguageModelSession(instructions: instructions)

    func correct(artist: String) async -> CorrectedEntity {
        // A stored rule (manual, or a previously learned correction) wins
        if let stored = storedCorrection(for: artist, entity: .artist) {
            return stored
        }
        guard needsCorrection(artist: artist) else {
            return await .from(original: artist)
        }

        guard let generated = try? await session.respond(to: artist, generating: ArtistFix.self) else {
            await Logger.intelligence.error("Failed to correct artist \(artist, privacy: .public)")
            return await .from(original: artist)
        }

        let corrected = generated.content
        if !artist.starts(with: corrected.mainArtist) {
            await Logger.intelligence.debug("Model returned “\(corrected.mainArtist, privacy: .public)” (\(corrected.reasoning, privacy: .public) for “\(artist, privacy: .public)”, ignoring")
            return await .from(original: artist)

        }
        
        await Logger.intelligence.debug("Corrected “\(artist, privacy: .public)” to “\(corrected.mainArtist, privacy: .public)” (\(corrected.reasoning, privacy: .public))")

        // Persist so we don't re-run the model for this artist again
        save(target: artist, replacement: corrected.mainArtist, entity: .artist)
        return await corrected.mainArtist == artist
            ? .from(original: artist)
            : .from(corrected: corrected, original: artist)
    }

    func needsCorrection(artist: String) -> Bool {
        return artist.contains(", ") || artist.contains(" & ")
    }


    // MARK: - Track & album correction

    /// Corrects a track title: a stored rule if one exists, otherwise strips a
    /// trailing version/remaster suffix.
    func correct(track title: String) -> CorrectedEntity {
        ruleBasedCorrection(for: title, entity: .track, noise: Self.trackTrailingNoise)
    }

    /// Corrects an album title: a stored rule if one exists, otherwise strips a
    /// trailing edition/remaster suffix.
    func correct(album title: String) -> CorrectedEntity {
        ruleBasedCorrection(for: title, entity: .album, noise: Self.albumTrailingNoise)
    }

    /// Applies a stored rule, otherwise strips trailing noise. Automatic stripping is saved to the correction database so users can overwrite it.
    private func ruleBasedCorrection(for value: String, entity: CorrectionEntity, noise: Regex<AnyRegexOutput>) -> CorrectedEntity {
        if let stored = storedCorrection(for: value, entity: entity) {
            return stored
        }
        let cleaned = strippingNoise(value, using: noise)
        guard cleaned != value, !cleaned.isEmpty else {
            return .from(original: value)
        }
        save(target: value, replacement: cleaned, entity: entity)
        return CorrectedEntity(originalTitle: value, correctedTitle: cleaned, reason: "Removed version/remaster suffix", shouldScrobble: true)
    }

    /// Returns the stored correction for `value`/`entity`, or `nil` if no rule matches
    private func storedCorrection(for value: String, entity: CorrectionEntity) -> CorrectedEntity? {
        guard let known = lookup(target: value, entity: entity) else { return nil }
        guard let replacement = known.replacement else { return .skip(original: value) }
        return CorrectedEntity(originalTitle: value, correctedTitle: replacement, reason: nil, shouldScrobble: true)
    }

    /// Builds a regex matching a trailing `(…)`/`[…]` group or `- …` suffix that
    /// contains any of `keywords`, anchored at end of string. Case-insensitive
    private static func trailingNoiseRegex(_ keywords: [String]) -> Regex<AnyRegexOutput> {
        let alt = keywords.joined(separator: "|")
        let pattern = "\\s*(?:[\\(\\[][^\\)\\]]*(?:\(alt))[^\\)\\]]*[\\)\\]]|-\\s+[^-]*(?:\(alt))[^-]*)\\s*$"
        return try! Regex(pattern).ignoresCase()
    }

    private static let trackTrailingNoise = trailingNoiseRegex(Constants.trackNoiseKeywords)
    private static let albumTrailingNoise = trailingNoiseRegex(Constants.albumNoiseKeywords)

    private func strippingNoise(_ title: String, using regex: Regex<AnyRegexOutput>) -> String {
        var result = title.trimmingCharacters(in: .whitespaces)
        while let match = try? regex.firstMatch(in: result),
              match.range.lowerBound != result.startIndex {
            result = String(result[..<match.range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    // MARK: - Auto-correct store

    private func lookup(target: String, entity: CorrectionEntity) -> AutoCorrect? {
        let localTarget = target
        
        let descriptor = FetchDescriptor<AutoCorrect>(
            predicate: #Predicate { $0.target == localTarget }
        )
        
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        return matches.first { $0.kind == entity }
    }

    /// Inserts (or updates) a correction rule. A `nil` replacement marks the
    /// entity as "do not scrobble"
    func save(target: String, replacement: String?, entity: CorrectionEntity) {
        Logger.intelligence.debug("Saved \(entity.rawValue, privacy: .public) rule: “\(target, privacy: .public)” becomes \(replacement ?? "<don't scrobble>", privacy: .public)")

        if let existing = lookup(target: target, entity: entity) {
            existing.replacement = replacement
        } else {
            modelContext.insert(AutoCorrect(target: target, replacement: replacement, kind: entity))
        }
        try? modelContext.save()
    }
}
