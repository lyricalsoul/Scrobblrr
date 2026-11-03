//
//  ManualCorrection.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/26/26.
//

import Foundation
import SwiftData

/// exact override for one track, album or artist, keyed by the raw values
@Model
final class ManualCorrection {
    var kind: CorrectionEntity = CorrectionEntity.artist
    var trackName: String = ""
    var albumName: String = ""
    var artistName: String = ""
    var replacement: String?
    var isAutomatic: Bool = false

    init(kind: CorrectionEntity, trackName: String = "", albumName: String = "", artistName: String, replacement: String?, isAutomatic: Bool = false) {
        self.kind = kind
        self.trackName = trackName
        self.albumName = albumName
        self.artistName = artistName
        self.replacement = replacement
        self.isAutomatic = isAutomatic
    }
}

extension ManualCorrection {
    func matches(track: String, album: String?, artist: String) -> Bool {
        switch kind {
        case .artist:
            return artistName == artist
        case .album:
            return albumName == (album ?? "") && artistName == artist
        case .track:
            return trackName == track && albumName == (album ?? "") && artistName == artist
        }
    }
}
