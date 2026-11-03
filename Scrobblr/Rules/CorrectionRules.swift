//
//  CorrectionRules.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/26/26.
//

import Foundation
import SwiftData
import os

enum CorrectionRules {
    static func applyCorrections(for value: String, type: CorrectionEntity, album: String? = nil, artist: String? = nil, in context: ModelContext) -> CorrectedEntity {
        if let manual = manualOverride(for: value, type: type, album: album, artist: artist, in: context) {
            guard let replacement = manual.replacement else {
                return .skip(original: value, reason: "Manual override")
            }
            return CorrectedEntity(originalTitle: value, correctedTitle: replacement, reason: "Manual override", shouldScrobble: true)
        }

        let rules = enabledRules(for: type, in: context)
        if let stripped = applyRegexRules(rules, to: value) {
            return stripped
        }

        return .from(original: value)
    }

    private static func manualOverride(for value: String, type: CorrectionEntity, album: String?, artist: String?, in context: ModelContext) -> ManualCorrection? {
        let effectiveTrack = type == .track ? value : ""
        let effectiveAlbum = type == .album ? value : album
        let effectiveArtist = type == .artist ? value : (artist ?? "")

        let descriptor = FetchDescriptor<ManualCorrection>(predicate: #Predicate { $0.artistName == effectiveArtist })
        let rules = (try? context.fetch(descriptor)) ?? []
        return rules.first { $0.kind == type && $0.matches(track: effectiveTrack, album: effectiveAlbum, artist: effectiveArtist) }
    }

    private static func enabledRules(for type: CorrectionEntity, in context: ModelContext) -> [Correction] {
        let descriptor = FetchDescriptor<Correction>(predicate: #Predicate { $0.isEnabled == true })
        let rules = (try? context.fetch(descriptor)) ?? []
        return rules.filter { $0.entities.contains(type) }
    }

    private static func applyRegexRules(_ rules: [Correction], to value: String) -> CorrectedEntity? {
        var result = value.trimmingCharacters(in: .whitespaces)
        var matchedTitle: String?

        var strippedSomething = true
        while strippedSomething {
            strippedSomething = false
            for rule in rules {
                guard let regex = RegexCache.shared.regex(for: rule.pattern) else { continue }
                guard let match = try? regex.firstMatch(in: result) else { continue }

                guard let replacement = rule.replacement else {
                    return .skip(original: value, reason: rule.title)
                }

                let candidate = (result[..<match.range.lowerBound] + replacement + result[match.range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                // an unchanged or empty candidate means this match was a no-op or ate the whole title, skip it
                guard candidate != result, !candidate.isEmpty else { continue }

                result = candidate
                matchedTitle = matchedTitle ?? rule.title
                strippedSomething = true
                break
            }
        }

        guard let matchedTitle, result != value else { return nil }
        Logger.rules.debug("Matched “\(matchedTitle, privacy: .public)” for “\(value, privacy: .public)”")
        return CorrectedEntity(originalTitle: value, correctedTitle: result, reason: matchedTitle, shouldScrobble: true)
    }
}
