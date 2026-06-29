//
//  Logging.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//
//  Unified logging. View in Console.app or `log stream --predicate
//  'subsystem == "io.lyricalsoul.Scroblrr"'`.

import os

extension Logger {
    private static let subsystem = "io.lyricalsoul.Scroblrr"

    /// Playback detection and scrobble timing.
    static let playback = Logger(subsystem: subsystem, category: "playback")
    /// Submission to scrobbling services.
    static let scrobbler = Logger(subsystem: subsystem, category: "scrobbler")
    /// The offline retry queue.
    static let queue = Logger(subsystem: subsystem, category: "queue")
    /// Last.fm authentication.
    static let auth = Logger(subsystem: subsystem, category: "auth")
    /// Keychain access.
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
}
