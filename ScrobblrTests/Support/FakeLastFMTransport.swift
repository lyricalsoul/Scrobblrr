//
//  FakeLastFMTransport.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Foundation
@testable import Scrobblr

nonisolated final class Locked<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    init(_ state: State) { self.state = state }

    var value: State {
        get { lock.withLock { state } }
        set { lock.withLock { state = newValue } }
    }

    func mutate<T>(_ body: (inout State) -> T) -> T { lock.withLock { body(&state) } }
}

nonisolated final class FakeLastFMTransport: LastFMTransport {
    struct State {
        var sessionResult = (key: "session-key", name: "tester")
        var sessionError: Error?
        var nowPlayingError: Error?
        var scrobbleError: Error?
        var gate: (@Sendable () async -> Void)?
        var tokens: [String] = []
        var nowPlaying: [(scrobble: Scrobble, sessionKey: String)] = []
        var scrobbled: [(scrobble: Scrobble, sessionKey: String)] = []
    }

    let state = Locked(State())

    func session(token: String) async throws -> (key: String, name: String) {
        let current = state.mutate { $0.tokens.append(token); return $0 }
        await current.gate?()
        if let error = current.sessionError { throw error }
        return current.sessionResult
    }

    func updateNowPlaying(_ scrobble: Scrobble, sessionKey: String) async throws {
        let current = state.mutate { $0.nowPlaying.append((scrobble, sessionKey)); return $0 }
        await current.gate?()
        if let error = current.nowPlayingError { throw error }
    }

    func scrobble(_ scrobble: Scrobble, sessionKey: String) async throws {
        let current = state.mutate { $0.scrobbled.append((scrobble, sessionKey)); return $0 }
        await current.gate?()
        if let error = current.scrobbleError { throw error }
    }
}

nonisolated final class FakeEpistolares: EpistolaresAPI {
    struct State {
        var recentTracks: Result<EpistolaresRecentTracks, Error> = .failure(URLError(.notConnectedToInternet))
        var registration: Result<PresenceRegistration, Error> = .success(PresenceRegistration(username: "tester", pushKey: "push-key"))
        var pushGate: (@Sendable () async -> Void)?
        var recentTracksCalls = 0
        var registrations: [String] = []
        var pushes: [GenericPlaybackInfo?] = []
        var trackInfoCalls: [String] = []
        var trackInfoHandler: (@Sendable (String) async throws -> EpistolaresTrackInfo)?
    }

    let state = Locked(State())

    func trackInfo(track: String, artist: String, album: String?, username: String?) async throws -> EpistolaresTrackInfo {
        let handler = state.mutate { $0.trackInfoCalls.append(track); return $0.trackInfoHandler }
        guard let handler else { throw URLError(.unsupportedURL) }
        return try await handler(track)
    }

    func recentTracks(username: String, limit: Int) async throws -> EpistolaresRecentTracks {
        try state.mutate { $0.recentTracksCalls += 1; return $0.recentTracks }.get()
    }

    func registerPresence(sessionKey: String) async throws -> PresenceRegistration {
        try state.mutate { $0.registrations.append(sessionKey); return $0.registration }.get()
    }

    func pushPresence(username: String, pushKey: String, device: String, info: GenericPlaybackInfo?) async throws {
        let gate = state.mutate { $0.pushes.append(info); return $0.pushGate }
        await gate?()
    }

    func presence(username: String, pushKey: String) async throws -> RemotePresence? { nil }

    func invalidateTrackInfoCache() {}
}

final class MemoryCredentials {
    var values: [String: String] = [:]

    init(_ values: [String: String] = [:]) { self.values = values }

    var store: CredentialStore {
        CredentialStore(get: { self.values[$0] }, set: { self.values[$1] = $0 })
    }
}
