//
//  GenericPlaybackInfo.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//
import SwiftUI

#if os(macOS)
import AppKit
/// The native bitmap-image type for the current platform
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

    /// "Artist • Album", subtitle on the player
    var subtitle: String {
        "\(artist) • \(album ?? "Unknown Album")"
    }

    var id: String {
        "\(artist)\u{1}\(title)\u{1}\(album ?? "")"
    }

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
        // equal unless one of the images have changed
        && (lhs.image == nil) == (rhs.image == nil)
    }
}
