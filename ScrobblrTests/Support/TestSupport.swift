//
//  TestSupport.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import Foundation
import SwiftData
@testable import Scrobblr

func makeContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Schema([Correction.self, ManualCorrection.self, CachedArtist.self, Settings.self, QueuedScrobble.self]),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    )
}

final class FakeScrobbler: Scrobbable, @unchecked Sendable {
    let name = "Last.fm"
    var isAuthenticated = true
    var nowPlaying: [Scrobble] = []
    var scrobbled: [Scrobble] = []
    var scrobbleError: Error?
    var gate: (() async -> Void)?

    func updateNowPlaying(_ scrobble: Scrobble) async throws {
        nowPlaying.append(scrobble)
    }

    func scrobble(_ scrobble: Scrobble) async throws {
        await gate?()
        if let scrobbleError { throw scrobbleError }
        scrobbled.append(scrobble)
    }
}

final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var durations: [Duration] = []
    private var credits = 0

    var requested: [Duration] { lock.withLock { durations } }
    var waiting: Int { lock.withLock { waiters.count } }

    var sleep: (Duration) async throws -> Void {
        { [self] duration in try await wait(duration) }
    }

    private func wait(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                durations.append(duration)
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else if credits > 0 {
                    credits -= 1
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters[id] = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            let waiter = lock.withLock { waiters.removeValue(forKey: id) }
            waiter?.resume(throwing: CancellationError())
        }
    }

    func advance() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            if waiters.isEmpty { credits += 1 }
            defer { waiters = [:] }
            return Array(waiters.values)
        }
        pending.forEach { $0.resume() }
    }

    func cancelAll() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            defer { waiters = [:] }
            return Array(waiters.values)
        }
        pending.forEach { $0.resume(throwing: CancellationError()) }
    }
}

final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private(set) var entered = 0

    func wait() async {
        entered += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }

    func close() { isOpen = false }
}

func info(_ title: String = "Song", artist: String = "Artist", album: String? = "Album", duration: Int = 200, elapsed: Int = 0, playing: Bool = true) -> GenericPlaybackInfo {
    GenericPlaybackInfo(title: title, artist: artist, album: album, durationSeconds: duration, elapsedTimeSeconds: elapsed, isPlaying: playing)
}

struct CapturedRequest {
    let request: URLRequest
    let body: Data?
}

nonisolated final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (URLResponse, Data)

    private static let idHeader = "X-Stub-ID"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var captured: [String: [CapturedRequest]] = [:]

    static func session(handler: @escaping Handler) -> URLSession {
        let id = UUID().uuidString
        lock.withLock { handlers[id] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [idHeader: id]
        return URLSession(configuration: configuration)
    }

    static func requests(of session: URLSession) -> [CapturedRequest] {
        guard let id = session.configuration.httpAdditionalHeaders?[idHeader] as? String else { return [] }
        return lock.withLock { captured[id] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.idHeader) ?? ""
        let handler = Self.lock.withLock { () -> Handler? in
            Self.captured[id, default: []].append(CapturedRequest(request: request, body: bodyData()))
            return Self.handlers[id]
        }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func bodyData() -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}

#if os(macOS)
final class FakeDiscord: DiscordSink {
    var starts = 0
    var stops = 0
    var updates: [(info: GenericPlaybackInfo?, coverURL: URL?)] = []

    func start() { starts += 1 }
    func stop() { stops += 1 }
    func update(for info: GenericPlaybackInfo?, coverURL: URL?) { updates.append((info, coverURL)) }
}

final class FakeRemote: RemoteSink {
    var starts: [String] = []
    var stops = 0

    func start(username: String, pushKey: String) { starts.append("\(username):\(pushKey)") }
    func stop() { stops += 1 }
}
#endif

func fakePresence(settings: Settings, lastFM: LastFMScrobbler) -> PresenceCoordinator {
    #if os(macOS)
    PresenceCoordinator(settings: settings, discord: FakeDiscord(), remote: FakeRemote(), lastFM: lastFM, trackInfo: FakeEpistolares())
    #else
    PresenceCoordinator(settings: settings, lastFM: lastFM)
    #endif
}
