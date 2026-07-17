//
//  RemotePresenceClient.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/11/26.
//

#if os(macOS)
import Foundation
import os

@MainActor
@Observable
final class RemotePresenceClient {
    enum Status: Equatable {
        case disabled
        case connecting
        case connected
        case error(String)
    }

    private(set) var status: Status = .disabled
    private(set) var latest: GenericPlaybackInfo?
    /// The device string from the last push (e.g. "ios"), for attributing `latest` in the UI
    private(set) var latestDevice: String?
    /// When `latest` was recorded server-side
    private(set) var latestUpdatedAt: Date?

    /// Fired whenever `latest` changes from a WS push or the initial GET
    var onUpdate: (() -> Void)?

    @ObservationIgnored private var task: URLSessionWebSocketTask?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var receiveTask: Task<Void, Never>?
    @ObservationIgnored private var username: String?
    @ObservationIgnored private var pushKey: String?
    @ObservationIgnored private let epistolares = Epistolares()

    private static let reconnectInterval: Duration = .seconds(3)

    func start(username: String, pushKey: String) {
        guard task == nil else {
            guard self.username != username || self.pushKey != pushKey else { return }
            Logger.presence.info("Presence credentials changed, reconnecting")
            stop()
            self.username = username
            self.pushKey = pushKey
            connect()
            return
        }
        self.username = username
        self.pushKey = pushKey
        connect()
    }

    func stop() {
        guard task != nil || reconnectTask != nil else { return }
        Logger.presence.info("Stopping presence WS")
        reconnectTask?.cancel(); reconnectTask = nil
        receiveTask?.cancel(); receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        status = .disabled
        latest = nil
        latestDevice = nil
        latestUpdatedAt = nil
        username = nil
        pushKey = nil
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

        let wsTask = URLSession.shared.webSocketTask(with: request)
        task = wsTask
        wsTask.resume()

        fetchInitialState(username: username, pushKey: pushKey)
        receiveLoop()
    }

    /// So the Mac has current state immediately instead of waiting for the next push...
    private func fetchInitialState(username: String, pushKey: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let presence = try await self.epistolares.presence(username: username, pushKey: pushKey) else {
                    Logger.presence.info("No presence on record yet for \(username, privacy: .public)")
                    return
                }
                self.apply(presence)
            } catch {
                Logger.presence.error("Initial presence fetch failed: \(error.localizedDescription, privacy: .public)")
            }
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
                Logger.presence.error("WS receive failed: \(error.localizedDescription, privacy: .public)")
                self.status = .error(error.localizedDescription)
                self.scheduleReconnect()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message, let data = text.data(using: .utf8) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            apply(try decoder.decode(RemotePresence.self, from: data))
        } catch {
            Logger.presence.error("Couldn't decode presence message: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ presence: RemotePresence) {
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
        Logger.presence.info("Reconnecting to presence WS in \(Int(Self.reconnectInterval.components.seconds))s")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: Self.reconnectInterval)
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }
}
#endif
