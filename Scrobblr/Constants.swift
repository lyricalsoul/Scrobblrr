//
//  Constants.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/17/26.
//

import CoreFoundation

// TODO: add - single suffix for albums
struct Constants {
    static let lfmApiKey = "573c000d85b8fd294e09fbf4bcc50bf0"
    static let lfmApiSecret = "a2eaf6c578c8d0bfda2c4846205aad0c"

    static let trackNoiseKeywords = [
        "remaster(?:ed)?",
        "single version",
        "album version",
        "mono version",
        "stereo version",
        "original mix",
        "original version",
    ]
    
    static let albumNoiseKeywords = [
        "deluxe version",
        "deluxe edition",
        "remaster(?:ed)?",
    ]
}
