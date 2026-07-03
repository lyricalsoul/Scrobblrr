//
//  TitleRules.swift
//  Scrobblr
//
//  Created by Renan Martins on 7/3/26.
//

import Foundation
import SwiftData

enum TitleRules {
    static func correct(track title: String, in context: ModelContext) -> CorrectedEntity {
        ruleBasedCorrection(for: title, entity: .track, noise: trackTrailingNoise, in: context)
    }

    static func correct(album title: String, in context: ModelContext) -> CorrectedEntity {
        ruleBasedCorrection(for: title, entity: .album, noise: albumTrailingNoise, in: context)
    }

    private static func ruleBasedCorrection(for value: String, entity: CorrectionEntity, noise: Regex<AnyRegexOutput>, in context: ModelContext) -> CorrectedEntity {
        if let stored = CorrectionStore.storedCorrection(for: value, entity: entity, in: context) {
            return stored
        }
        let cleaned = strippingNoise(value, using: noise)
        guard cleaned != value, !cleaned.isEmpty else {
            return .from(original: value)
        }
        CorrectionStore.save(target: value, replacement: cleaned, entity: entity, in: context)
        return CorrectedEntity(originalTitle: value, correctedTitle: cleaned, reason: "Removed version/remaster suffix", shouldScrobble: true)
    }

    private static func strippingNoise(_ title: String, using regex: Regex<AnyRegexOutput>) -> String {
        var result = title.trimmingCharacters(in: .whitespaces)
        while let match = try? regex.firstMatch(in: result),
              match.range.lowerBound != result.startIndex {
            result = String(result[..<match.range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func trailingNoiseRegex(_ keywords: [String]) -> Regex<AnyRegexOutput> {
        let alt = keywords.joined(separator: "|")
        let pattern = "\\s*(?:[\\(\\[][^\\)\\]]*(?:\(alt))[^\\)\\]]*[\\)\\]]|-\\s+[^-]*(?:\(alt))[^-]*)\\s*$"
        return try! Regex(pattern).ignoresCase()
    }

    private static let trackNoiseKeywords = [
        "remaster(?:ed)?",
        "single version",
        "album version",
        "mono version",
        "stereo version",
        "original mix",
        "original version",
        "\\bfeat\\.?",
        "\\bft\\.?",
        "\\bfeaturing\\b",
    ]

    // TODO: make these customizable
    private static let albumNoiseKeywords = [
        "deluxe version",
        "deluxe edition",
        "remaster(?:ed)?",
        // "Album Name - EP" / "Album Name - Single"
        "\\bep\\b",
        "\\bsingle\\b",
    ]

    private static let trackTrailingNoise = trailingNoiseRegex(trackNoiseKeywords)
    private static let albumTrailingNoise = trailingNoiseRegex(albumNoiseKeywords)
}
