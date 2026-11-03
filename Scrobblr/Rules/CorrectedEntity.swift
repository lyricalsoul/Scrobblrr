//
//  CorrectedEntity.swift
//  Scrobblr
//
//  Created by Renan Martins on 7/3/26.
//

import Foundation

struct CorrectedEntity {
    let originalTitle: String
    let correctedTitle: String?
    let reason: String?

    let shouldScrobble: Bool

    var title: String {
        return correctedTitle ?? originalTitle
    }

    #if os(macOS)
    static func from(corrected artist: String, original: String) -> CorrectedEntity {
        .init(originalTitle: original, correctedTitle: artist, reason: "Automatic split", shouldScrobble: true)
    }
    #endif

    static func from(original: String) -> CorrectedEntity {
        .init(originalTitle: original, correctedTitle: nil, reason: nil, shouldScrobble: true)
    }

    static func skip(original: String, reason: String? = nil) -> CorrectedEntity {
        .init(originalTitle: original, correctedTitle: nil, reason: reason, shouldScrobble: false)
    }
}
