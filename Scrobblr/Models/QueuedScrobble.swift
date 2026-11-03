//
//  QueuedScrobble.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//

import Foundation
import SwiftData

@Model
final class QueuedScrobble {
    /// `Scrobbable.name` of the destination
    var serviceName: String

    var payloadData: Data

    var attempt: Int

    var nextAttempt: Date

    var createdAt: Date

    init(serviceName: String, scrobble: Scrobble, nextAttempt: Date, createdAt: Date) throws {
        self.serviceName = serviceName
        self.payloadData = try JSONEncoder().encode(scrobble)
        self.attempt = 0
        self.nextAttempt = nextAttempt
        self.createdAt = createdAt
    }

    /// `nil` if the payload can no longer be read
    var scrobble: Scrobble? {
        try? JSONDecoder().decode(Scrobble.self, from: payloadData)
    }
}
