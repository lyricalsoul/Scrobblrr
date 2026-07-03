//
//  CorrectionStore.swift
//  Scrobblr
//
//  Created by Renan Martins on 7/3/26.
//

import Foundation
import SwiftData
import os

enum CorrectionStore {
    static func storedCorrection(for value: String, entity: CorrectionEntity, in context: ModelContext) -> CorrectedEntity? {
        guard let known = lookup(target: value, entity: entity, in: context) else { return nil }
        guard let replacement = known.replacement else { return .skip(original: value) }
        return CorrectedEntity(originalTitle: value, correctedTitle: replacement, reason: nil, shouldScrobble: true)
    }

    static func save(target: String, replacement: String?, entity: CorrectionEntity, in context: ModelContext) {
        Logger.rules.debug("Saved \(entity.rawValue, privacy: .public) rule: “\(target, privacy: .public)” becomes \(replacement ?? "<don't scrobble>", privacy: .public)")

        if let existing = lookup(target: target, entity: entity, in: context) {
            existing.replacement = replacement
        } else {
            context.insert(AutoCorrect(target: target, replacement: replacement, kind: entity))
        }
        try? context.save()
    }

    private static func lookup(target: String, entity: CorrectionEntity, in context: ModelContext) -> AutoCorrect? {
        let localTarget = target

        let descriptor = FetchDescriptor<AutoCorrect>(
            predicate: #Predicate { $0.target == localTarget }
        )

        let matches = (try? context.fetch(descriptor)) ?? []
        return matches.first { $0.kind == entity }
    }
}
