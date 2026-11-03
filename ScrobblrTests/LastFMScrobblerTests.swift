//
//  LastFMScrobblerTests.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Testing
import Foundation
@testable import Scrobblr

@Suite @MainActor struct LastFMScrobblerTests {
    let transport = FakeLastFMTransport()
    let epistolares = FakeEpistolares()

    nonisolated static let signedIn = ["lastfm.sessionKey": "sk", "lastfm.username": "tester", "lastfm.presencePushKey": "pk"]

    func make(_ credentials: MemoryCredentials = MemoryCredentials(signedIn)) -> LastFMScrobbler {
        LastFMScrobbler(transport: transport, epistolares: epistolares, credentials: credentials.store)
    }

    static func scrobble(_ track: String = "Song", artist: String = "Artist", album: String? = "Album", duration: Int? = 200, at timestamp: Date = Date(timeIntervalSince1970: 1_000_000)) -> Scrobble {
        Scrobble(artist: artist, track: track, album: album, durationSeconds: duration, timestamp: timestamp)
    }

    static func item(_ track: String = "Song", artist: String = "Artist", playedAt: Date? = Date(timeIntervalSince1970: 1_000_000), nowPlaying: Bool = false) -> EpistolaresRecentTracks.Item {
        EpistolaresRecentTracks.Item(
            nowPlaying: nowPlaying,
            playedAt: playedAt,
            track: .init(id: nil, name: track, cover: nil, listeners: 0, scrobbles: 0, tags: [], userScrobbles: nil),
            album: nil,
            artist: .init(id: nil, name: artist, cover: nil, listeners: 0, scrobbles: 0, userScrobbles: nil)
        )
    }

    static func page(_ items: [EpistolaresRecentTracks.Item]) -> EpistolaresRecentTracks {
        EpistolaresRecentTracks(page: 1, totalPages: 1, total: items.count, items: items)
    }

    @Test func notAuthenticatedThrows() async {
        let scrobbler = make(MemoryCredentials())
        #expect(!scrobbler.isAuthenticated)
        await #expect(throws: ScrobblerError.notAuthenticated) { try await scrobbler.updateNowPlaying(Self.scrobble()) }
        await #expect(throws: ScrobblerError.notAuthenticated) { try await scrobbler.scrobble(Self.scrobble()) }
        #expect(transport.state.value.nowPlaying.isEmpty && transport.state.value.scrobbled.isEmpty)
    }

    @Test func updateNowPlayingForwardsFields() async throws {
        try await make().updateNowPlaying(Self.scrobble())
        let call = try #require(transport.state.value.nowPlaying.first)
        #expect(call.scrobble == Self.scrobble())
        #expect(call.sessionKey == "sk")
    }

    @Test func scrobbleForwardsTimestampAlbumDuration() async throws {
        try await make().scrobble(Self.scrobble())
        let call = try #require(transport.state.value.scrobbled.first)
        #expect(call.scrobble.timestamp == Date(timeIntervalSince1970: 1_000_000))
        #expect(call.scrobble.album == "Album")
        #expect(call.scrobble.durationSeconds == 200)
        #expect(call.sessionKey == "sk")
    }

    @Test func nilDurationAndAlbumAreForwardedAsNil() async throws {
        let scrobble = Self.scrobble(album: nil, duration: nil)
        let scrobbler = make()
        try await scrobbler.updateNowPlaying(scrobble)
        try await scrobbler.scrobble(scrobble)
        #expect(transport.state.value.nowPlaying.map(\.scrobble) == [scrobble])
        #expect(transport.state.value.scrobbled.map(\.scrobble) == [scrobble])
    }

    @Test func firstScrobbleSkipsDuplicateAlreadyOnLastFM() async throws {
        epistolares.state.value.recentTracks = .success(Self.page([Self.item()]))
        try await make().scrobble(Self.scrobble())
        #expect(transport.state.value.scrobbled.isEmpty)
    }

    @Test func afterRealScrobbleNoMoreDedupeLookups() async throws {
        epistolares.state.value.recentTracks = .success(Self.page([]))
        let scrobbler = make()
        try await scrobbler.scrobble(Self.scrobble("One"))
        try await scrobbler.scrobble(Self.scrobble("Two"))
        #expect(epistolares.state.value.recentTracksCalls == 1)
        #expect(transport.state.value.scrobbled.map(\.scrobble.track) == ["One", "Two"])
    }

    @Test func dedupeLookupFailureStillScrobbles() async throws {
        epistolares.state.value.recentTracks = .failure(URLError(.timedOut))
        try await make().scrobble(Self.scrobble())
        #expect(transport.state.value.scrobbled.count == 1)
    }

    @Test func completeAuthenticationStoresKeysAndRegistersPresence() async throws {
        let credentials = MemoryCredentials()
        let scrobbler = make(credentials)
        transport.state.value.sessionResult = (key: "new-sk", name: "newuser")
        try await scrobbler.completeAuthentication(token: "tok")
        #expect(transport.state.value.tokens == ["tok"])
        #expect(scrobbler.isAuthenticated && scrobbler.username == "newuser")
        #expect(credentials.values["lastfm.sessionKey"] == "new-sk")
        #expect(credentials.values["lastfm.username"] == "newuser")
        #expect(await waitUntil { scrobbler.pushKey == "push-key" })
        #expect(credentials.values["lastfm.presencePushKey"] == "push-key")
        #expect(epistolares.state.value.registrations == ["new-sk"])
    }

    @Test func signOutClearsKeychainAndKeys() {
        let credentials = MemoryCredentials(Self.signedIn)
        let scrobbler = make(credentials)
        scrobbler.signOut()
        #expect(!scrobbler.isAuthenticated && scrobbler.username == nil && scrobbler.pushKey == nil)
        #expect(credentials.values.isEmpty)
    }

    @Test func initWithSessionButNoPushKeyRegistersPresence() async {
        let credentials = MemoryCredentials(["lastfm.sessionKey": "sk", "lastfm.username": "tester"])
        let scrobbler = make(credentials)
        #expect(await waitUntil { scrobbler.pushKey == "push-key" })
        #expect(credentials.values["lastfm.presencePushKey"] == "push-key")
        #expect(epistolares.state.value.registrations == ["sk"])
    }

    @Test func transportErrorPropagates() async {
        epistolares.state.value.recentTracks = .success(Self.page([]))
        transport.state.value.scrobbleError = URLError(.timedOut)
        transport.state.value.nowPlayingError = URLError(.badServerResponse)
        let scrobbler = make()
        await #expect(throws: URLError(.timedOut)) { try await scrobbler.scrobble(Self.scrobble()) }
        await #expect(throws: URLError(.badServerResponse)) { try await scrobbler.updateNowPlaying(Self.scrobble()) }
    }

    @Test func rapidPresencePushesSendOnlyLatest() async {
        let sleeper = ManualSleeper()
        epistolares.state.value.pushGate = { [sleeper] in try? await sleeper.sleep(.zero) }
        let scrobbler = make()
        scrobbler.pushPresence(info("A"), device: "ios")
        #expect(await waitUntil { sleeper.requested.count == 1 })
        scrobbler.pushPresence(info("B"), device: "ios")
        scrobbler.pushPresence(info("C"), device: "ios")
        #expect(await waitUntil { sleeper.requested.count == 2 })
        sleeper.advance()
        #expect(await waitUntil { epistolares.state.value.pushes.last??.title == "C" })
        #expect(epistolares.state.value.pushes.map { $0?.title } == ["A", "C"])
    }

    @Test(arguments: [
        ("Song", "Artist", 0, false, true),
        ("SONG", "artist", 0, false, true),
        ("Song", "Artist", 120, false, true),
        ("Song", "Artist", -120, false, true),
        ("Song", "Artist", 121, false, false),
        ("Song", "Artist", 0, true, false),
        ("Song", "Artist", nil, false, false),
        ("Song", "Other", 0, false, false),
        ("Other", "Artist", 0, false, false),
    ] as [(String, String, TimeInterval?, Bool, Bool)])
    func isDuplicate(track: String, artist: String, offset: TimeInterval?, nowPlaying: Bool, expected: Bool) {
        let item = Self.item(track, artist: artist, playedAt: offset.map { Date(timeIntervalSince1970: 1_000_000 + $0) }, nowPlaying: nowPlaying)
        #expect(LastFMScrobbler.isDuplicate([item], of: Self.scrobble()) == expected)
    }
}
