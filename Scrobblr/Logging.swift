//
//  Logging.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//
//  Unified logging

import os

extension Logger {
    private static let subsystem = "io.lyricalsoul.Scrobblrr"

    /// Playback detection and scrobble things
    static let playback = Logger(subsystem: subsystem, category: "playback")
    /// Submission to scrobbling services
    static let scrobbler = Logger(subsystem: subsystem, category: "scrobbler")
    /// The offline retry queue
    static let queue = Logger(subsystem: subsystem, category: "queue")
    /// On-device AI metadata correction
    static let intelligence = Logger(subsystem: subsystem, category: "intelligence")
    /// Regle title correction and persistence
    static let rules = Logger(subsystem: subsystem, category: "rules")
    /// Last.fm authentication
    static let auth = Logger(subsystem: subsystem, category: "auth")
    /// Keychain access
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
    /// Last.fm functionality
    static let fm = Logger(subsystem: subsystem, category: "lastfm")
    /// Epistolares
    static let epistolares = Logger(subsystem: subsystem, category: "epistolares")
    /// Ditto collage generation
    static let ditto = Logger(subsystem: subsystem, category: "ditto")
    /// MusicKit integration
    static let musicKit = Logger(subsystem: subsystem, category: "musickit")
    /// Discord Rich Presence
    static let discord = Logger(subsystem: subsystem, category: "discord")
}
