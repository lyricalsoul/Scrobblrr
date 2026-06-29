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
/// it is rewritten to `replacement`. A `nil` replacement means the matched
/// entity should not be scrobbled at all.
@Model
final class AutoCorrect {
    /// The original title to match against.
    var target: String

    /// What `target` should be replaced with. `nil` means "don't scrobble".
    var replacement: String?

    /// Which kind of metadata this rule applies to.
    /// NOTE: do NOT name this `entity` — that's a reserved Core Data property
    /// name and SwiftData mis-stores it as a broken composite attribute.
    var kind: CorrectionEntity

    init(target: String, replacement: String?, kind: CorrectionEntity) {
        self.target = target
        self.replacement = replacement
        self.kind = kind
    }
}
