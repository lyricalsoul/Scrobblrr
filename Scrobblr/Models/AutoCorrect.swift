//
//  AutoCorrect.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//
// Defines titles (target) to be replaced, and what they should be replaced for.
// Entities is an enum, TRACK, ALBUM, ARTIST
// If replacement is nil, that means this should not be scrobbled.

import Foundation
import SwiftData

/// The kind of metadata an ``AutoCorrect`` rule applies to.
enum CorrectionEntity: String, Codable, CaseIterable {
    case track
    case album
    case artist
}

/// A single auto-correction rule: when an entity's title matches `target`,
/// it is rewritten to `replacement`. A `nil` value means the entity should not be scrobbled.
@Model
final class AutoCorrect {
    /// The original title to match against.
    var target: String

    /// What `target` should be replaced with, or `nil`
    var replacement: String?

    // note to self, "entity" clashes with core data, do not use that as a name ever again
    /// Which kind of metadata this rule applies to.
    var kind: CorrectionEntity

    init(target: String, replacement: String?, kind: CorrectionEntity) {
        self.target = target
        self.replacement = replacement
        self.kind = kind
    }
}
