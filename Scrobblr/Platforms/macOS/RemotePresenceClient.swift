//
//  RemotePresenceClient.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/11/26.
//

#if os(macOS)
import Foundation
import AppKit
import os

@MainActor
@Observable
final class RemotePresenceClient {
    private(set) var status: ConnectionStatus = .disabled
    private(set) var latest: GenericPlaybackInfo?
    /// device string from the last push, e.g. "ios"
    private(set) var latestDevice: String?
    private(set) var latestUpdatedAt: Date?

    /// fired when `latest` changes from a push or the initial fetch
    var onUpdate: (() -> Void)?

    @ObservationIgnored private var task: URLSessionWebSocketTask?
    @ObservationIgnored private(set) var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var receiveTask: Task<Void, Never>?
    @ObservationIgnored var username: String?
    @ObservationIgnored var pushKey: String?
    @ObservationIgnored var openSocket: (URLRequest) -> URLSessionWebSocketTask? = {
        let task = URLSession.shared.webSocketTask(with: $0)
        task.resume()
        return task
    }
    @ObservationIgnored var fetchPresence: (String, String) async throws -> RemotePresence? = { try await Epistolares().presence(username: $0, pushKey: $1) }
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    @ObservationIgnored private(set) var backoff = Backoff()
    @ObservationIgnored private var keyRejected = false

    func start(username: String, pushKey: String) {
        if wakeObserver == nil {
            // sleep can leave the socket dead without erroring, so reconnect on wake
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    Logger.presence.info("Mac woke from sleep, forcing presence WS reconnect")
                    self?.forceReconnect()
                }
            }
        }

        // called on every broadcast, so same credentials must not retry a rejected key or reset the backoff
        let changed = username != self.username || pushKey != self.pushKey
        guard changed || !keyRejected else { return }
        if changed {
            keyRejected = false
            backoff.reset()
        }
        if task != nil || reconnectTask != nil {
            guard changed else { return }
            Logger.presence.info("Presence credentials changed, reconnecting")
            stop(keepingWakeObserver: true)
        }
        self.username = username
        self.pushKey = pushKey
        connect()
    }

    func stop() {
        stop(keepingWakeObserver: false)
    }

    private func stop(keepingWakeObserver: Bool) {
        if !keepingWakeObserver, let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        guard task != nil || reconnectTask != nil || keyRejected else { return }
        Logger.presence.info("Stopping presence WS")
        disconnect(.goingAway)
        keyRejected = false
        status = .disabled
        latest = nil
        latestDevice = nil
        latestUpdatedAt = nil
        username = nil
        pushKey = nil
    }

    private func forceReconnect() {
        guard username != nil, pushKey != nil, !keyRejected else { return }
        disconnect(.goingAway)
        connect()
    }

    private func disconnect(_ code: URLSessionWebSocketTask.CloseCode) {
        reconnectTask?.cancel(); reconnectTask = nil
        receiveTask?.cancel(); receiveTask = nil
        task?.cancel(with: code, reason: nil)
        task = nil
    }

    private func connect() {
        guard let username, let pushKey else { return }
        status = .connecting
        Logger.presence.info("Connecting to presence WS for \(username, privacy: .public)")

        var components = URLComponents(url: Constants.epistolaresBaseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path += "/user/presence/\(username)/ws"

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(pushKey)", forHTTPHeaderField: "Authorization")

        task = openSocket(request)

        fetchInitialState(username: username, pushKey: pushKey)
        receiveLoop()
    }

    // gets current state without waiting for the next push
    private func fetchInitialState(username: String, pushKey: String) {
        Task { [weak self] in
            guard let self else { return }
            let result: Result<RemotePresence?, Error>
            do { result = .success(try await self.fetchPresence(username, pushKey)) } catch { result = .failure(error) }
            self.initialFetched(result, username: username, pushKey: pushKey)
        }
    }

    func initialFetched(_ result: Result<RemotePresence?, Error>, username: String, pushKey: String) {
        guard username == self.username, pushKey == self.pushKey else { return }
        switch result {
        case .success(let presence):
            if let presence { apply(presence) } else { Logger.presence.info("No presence on record yet for \(username, privacy: .public)") }
        case .failure(let error):
            if case EpistolaresError.unauthorized = error { connectionFailed(statusCode: 401, message: error.localizedDescription) }
            Logger.presence.error("Initial presence fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func receiveLoop() {
        receiveTask = Task { [weak self] in
            guard let self, let task = self.task else { return }
            do {
                let message = try await task.receive()
                guard !Task.isCancelled else { return }
                if self.status != .connected {
                    Logger.presence.info("Connected to presence WS")
                }
                self.status = .connected
                self.reconnectTask?.cancel()
                self.reconnectTask = nil
                self.handle(message)
                self.receiveLoop()
            } catch {
                guard !Task.isCancelled else { return }
                self.connectionFailed(statusCode: (task.response as? HTTPURLResponse)?.statusCode, message: error.localizedDescription)
            }
        }
    }

    func connectionFailed(statusCode: Int?, message: String) {
        Logger.presence.error("WS receive failed (\(statusCode ?? 0, privacy: .public)): \(message, privacy: .public)")
        guard statusCode == 401 else {
            status = .error(message)
            scheduleReconnect()
            return
        }
        keyRejected = true
        disconnect(.policyViolation)
        status = .error("Presence key rejected")
    }

    func handle(_ message: URLSessionWebSocketTask.Message) {
        backoff.reset()
        guard case .string(let text) = message, let data = text.data(using: .utf8) else { return }
        do {
            apply(try Epistolares.decoder.decode(RemotePresence.self, from: data))
        } catch {
            Logger.presence.error("Couldn't decode presence message: \(error.localizedDescription, privacy: .public)")
        }
    }

    func apply(_ presence: RemotePresence) {
        if let latestUpdatedAt, presence.updatedAt < latestUpdatedAt { return }
        latest = presence.info
        latestDevice = presence.device
        latestUpdatedAt = presence.updatedAt
        Logger.presence.info("Presence update from \(presence.device, privacy: .public): \(presence.info?.displayName ?? "stopped", privacy: .public)")
        onUpdate?()
    }

    private func scheduleReconnect() {
        task?.cancel(with: .abnormalClosure, reason: nil)
        task = nil
        guard reconnectTask == nil else { return }
        let delay = backoff.next()
        Logger.presence.info("Reconnecting to presence WS in \(Int(delay.components.seconds))s")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }
}
#endif
