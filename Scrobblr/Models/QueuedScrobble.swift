//
//  QueuedScrobble.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//
//  A scrobble that failed to submit (e.g. offline) and is awaiting retry.
//  One row per (scrobble, service) so each destination retries independently.

import Foundation
import SwiftData

@Model
final class QueuedScrobble {
    /// `Scrobbable.name` of the destination this row is pending for.
    var serviceName: String

    /// JSON-encoded `Scrobble` payload.
    var payloadData: Data

    /// How many submission attempts have already failed.
    var attempt: Int

    /// Earliest time the next attempt should be made (drives backoff).
    var nextAttempt: Date

    var createdAt: Date

    init(serviceName: String, scrobble: Scrobble, nextAttempt: Date, createdAt: Date) throws {
        self.serviceName = serviceName
        self.payloadData = try JSONEncoder().encode(scrobble)
        self.attempt = 0
        self.nextAttempt = nextAttempt
        self.createdAt = createdAt
    }

    /// The decoded payload, or `nil` if it can no longer be read.
    var scrobble: Scrobble? {
        try? JSONDecoder().decode(Scrobble.self, from: payloadData)
    }
}
