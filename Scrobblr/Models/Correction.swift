//
//  Correction.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/26/26.
//

import Foundation
import SwiftData

enum CorrectionEntity: String, Codable, CaseIterable, Identifiable {
    case track
    case album
    case artist

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .track:  "Track"
        case .album:  "Album"
        case .artist: "Artist"
        }
    }
}

/// automatic regex rule: a title matching `pattern` is rewritten to `replacement`
@Model
final class Correction {
    var title: String = ""
    var pattern: String = ""
    var replacement: String?
    var entities: [CorrectionEntity] = []
    var isEnabled: Bool = true

    init(title: String, pattern: String, replacement: String?, entities: [CorrectionEntity], isEnabled: Bool = true) {
        self.title = title
        self.pattern = pattern
        self.replacement = replacement
        self.entities = entities
        self.isEnabled = isEnabled
    }
}

extension Correction {
    static func seedDefaultsIfNeeded(in context: ModelContext) {
        let existingPatterns = Set((try? context.fetch(FetchDescriptor<Correction>()))?.map(\.pattern) ?? [])

        for (title, keyword, entities) in defaultRules {
            let pattern = trailingNoisePattern(keyword)
            guard !existingPatterns.contains(pattern) else { continue }
            context.insert(Correction(title: title, pattern: pattern, replacement: "", entities: entities))
        }
        dedupeDefaults(in: context)
    }

    static func dedupeDefaults(in context: ModelContext) {
        let groups = Dictionary(grouping: (try? context.fetch(FetchDescriptor<Correction>())) ?? [], by: { "\($0.pattern)\u{0}\($0.replacement ?? "\u{1}")\u{0}\($0.entities.map(\.rawValue).sorted())" })
        for group in groups.values where group.count > 1 {
            if group.contains(where: { !$0.isEnabled }) { group[0].isEnabled = false }
            group.dropFirst().forEach { context.delete($0) }
        }
        try? context.save()
    }

    static let defaultRules: [(title: String, keyword: String, entities: [CorrectionEntity])] = [
        ("Remove - Remaster(ed)", "remaster(?:ed)?", [.track, .album]),
        ("Remove - Single Version", "single version", [.track]),
        ("Remove - Album Version", "album version", [.track]),
        ("Remove - Mono Version", "mono version", [.track]),
        ("Remove - Stereo Version", "stereo version", [.track]),
        ("Remove - Original Mix", "original mix", [.track]),
        ("Remove - Original Version", "original version", [.track]),
        ("Remove - Feat.", "\\bfeat\\.?", [.track]),
        ("Remove - Ft.", "\\bft\\.?", [.track]),
        ("Remove - Featuring", "\\bfeaturing\\b", [.track]),
        ("Remove - Deluxe Version", "deluxe version", [.album]),
        ("Remove - Deluxe Edition", "deluxe edition", [.album]),
        ("Remove - EP Suffix", "\\bep\\b", [.album]),
        ("Remove - Single Suffix", "\\bsingle\\b", [.album]),
    ]

    static func trailingNoisePattern(_ keyword: String) -> String {
        "\\s*(?:[\\(\\[][^\\)\\]]*\(keyword)[^\\)\\]]*[\\)\\]]|\\s+-\\s+[^-]*\(keyword)[^-]*)\\s*$"
    }
}
