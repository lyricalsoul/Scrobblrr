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

    static let playback = Logger(subsystem: subsystem, category: "playback")
    static let scrobbler = Logger(subsystem: subsystem, category: "scrobbler")
    static let queue = Logger(subsystem: subsystem, category: "queue")
    static let intelligence = Logger(subsystem: subsystem, category: "intelligence")
    static let rules = Logger(subsystem: subsystem, category: "rules")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
    static let epistolares = Logger(subsystem: subsystem, category: "epistolares")
    static let ditto = Logger(subsystem: subsystem, category: "ditto")
    static let musicKit = Logger(subsystem: subsystem, category: "musickit")
    static let discord = Logger(subsystem: subsystem, category: "discord")
    static let presence = Logger(subsystem: subsystem, category: "presence")
}
