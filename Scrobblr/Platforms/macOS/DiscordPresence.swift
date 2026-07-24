//
//  DiscordPresence.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/10/26.
//

#if os(macOS)
import Foundation
import SwiftRPC
import os

@MainActor
@Observable
final class DiscordPresence {
    enum Status: Equatable {
        case disabled
        case connecting
        case connected
        case error(String)
    }

    private(set) var status: Status = .disabled

    @ObservationIgnored private var rpc: SwiftRPC?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var pendingUpdate: (info: GenericPlaybackInfo?, coverURL: URL?)?
    @ObservationIgnored private var isConnected = false

    private static let reconnectInterval: Duration = .seconds(3)

    func start() {
        guard rpc == nil else { return }
        status = .connecting

        let client = SwiftRPC(appId: Constants.discordAppId)
        rpc = client

        client.onConnect { [weak self] _ in
            Task { @MainActor [weak self] in
                Logger.discord.info("Connected to Discord")
                self?.status = .connected
                self?.isConnected = true
                self?.reconnectTask?.cancel()
                self?.reconnectTask = nil
                if let pending = self?.pendingUpdate {
                    self?.send(info: pending.info, coverURL: pending.coverURL)
                }
            }
        }
        client.onDisconnect { [weak self] _, _, _ in
            Task { @MainActor [weak self] in
                Logger.discord.info("Disconnected from Discord")
                self?.status = .connecting
                self?.isConnected = false
                self?.scheduleReconnect()
            }
        }
        client.onError { [weak self] _, code, msg in
            Task { @MainActor [weak self] in
                Logger.discord.error("Discord RPC error \(code, privacy: .public): \(msg, privacy: .public)")
                self?.status = .error(msg)
            }
        }

        attemptConnect()
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        rpc?.clearPresence()
        rpc = nil
        pendingUpdate = nil
        isConnected = false
        status = .disabled
    }

    func update(for info: GenericPlaybackInfo?, coverURL: URL?) {
        pendingUpdate = (info, coverURL)
        guard isConnected else { return }
        send(info: info, coverURL: coverURL)
    }

    private func send(info: GenericPlaybackInfo?, coverURL: URL?) {
        guard let rpc else { return }

        guard let info, info.isPlaying else {
            rpc.clearPresence()
            return
        }

        var presence = RichPresence()
        presence.type = .listening
        presence.statusDisplayType = .state
        presence.instance = false
        presence.details = info.title
        presence.state = info.artist

        let start = Date(timeIntervalSinceNow: -Double(info.elapsedTimeSeconds))
        presence.timestamps.start = start
        if info.durationSeconds > 0 {
            presence.timestamps.end = start.addingTimeInterval(Double(info.durationSeconds))
        }

        presence.assets.largeImage = coverURL?.absoluteString
        presence.assets.largeText = info.album.map(Self.discordSafeText)
        presence.buttons = [.init(label: "Scrobblrr for macOS", url: "https://lyricalsoul.io/scrobblrr")]

        rpc.setPresence(presence, immediate: true)
    }

    private static func discordSafeText(_ text: String) -> String {
        guard text.count <= 2 else { return text }
        return text + " \u{200B} \u{00A0} \u{200B}"
    }

    private func attemptConnect() {
        rpc?.connect()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: Self.reconnectInterval)
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            self.attemptConnect()
        }
    }
}
#endif
