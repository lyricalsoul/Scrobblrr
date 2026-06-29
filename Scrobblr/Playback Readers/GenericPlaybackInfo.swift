//
//  GenericPlaybackInfo.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//
import SwiftUI

#if os(macOS)
import AppKit
/// The native bitmap-image type for the current platform.
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

struct GenericPlaybackInfo : Equatable {
    let title: String
    let artist: String
    let album: String?
    
    let durationSeconds: Int
    let elapsedTimeSeconds: Int

    let isPlaying: Bool

    var image: PlatformImage?
    
    var displayName: String {
        "\(artist) - \(title)"
    }

    /// Stable identity for a track, independent of playback position/state.
    var id: String {
        "\(artist)\u{1}\(title)\u{1}\(album ?? "")"
    }

    /// The artwork as a SwiftUI `Image`, or `nil` when there's no artwork.
    var artworkImage: Image? {
        guard let image else { return nil }
        #if os(macOS)
        return Image(nsImage: image)
        #else
        return Image(uiImage: image)
        #endif
    }
    
    static func == (lhs: GenericPlaybackInfo, rhs: GenericPlaybackInfo) -> Bool {
        lhs.displayName == rhs.displayName
        && lhs.album == rhs.album
        // Artwork often arrives in a later event for the same track (the OS has
        // to decode the cover first). Treat the appearance/disappearance of
        // artwork as a real change so SwiftUI refreshes the displayed image.
        && (lhs.image == nil) == (rhs.image == nil)
    }
}
