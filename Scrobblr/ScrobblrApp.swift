//
//  ScrobblrApp.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/2/26.
//

import SwiftUI
import SwiftData
import Sentry

@main struct MyApp: App {
    @State private var manager: ScrobblerManager
    @State private var model: MediaModel
    @State private var webAuth = WebAuthCoordinator()
    #if os(macOS)
    @State private var updater = SparkleUpdater()
    @Environment(\.openWindow) private var openWindow
    #endif

    private let modelContainer: ModelContainer
    private let settings: Settings

    init() {
        SentrySDK.start { options in
            options.dsn = "https://dcb7bad1545563d59006da73925fa1d9@o1160503.ingest.us.sentry.io/4511828284276736"
            options.tracesSampleRate = 0
            options.enableLogs = true
        }
        SentrySDK.logger.info("App launched")

        let container: ModelContainer
        do {
            container = try AppModelContainer.make()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        Correction.seedDefaultsIfNeeded(in: container.mainContext)
        CachedArtist.dedupe(in: container.mainContext)

        let settings = Settings.shared(in: container.mainContext)
        let manager = ScrobblerManager(modelContainer: container, settings: settings)

        modelContainer = container
        self.settings = settings

        _manager = State(initialValue: manager)
        _model = State(initialValue: MediaModel(manager: manager, settings: settings, modelContainer: container))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            #if os(macOS)
            RootView(manager: manager, settings: settings, updater: updater)
            #else
            RootView(manager: manager, settings: settings, model: model)
                .task { await model.start() }
            #endif
        }
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif
        .modelContainer(modelContainer)

        #if os(macOS)
        MenuBarExtra(
            "Scroblrr",
            systemImage: (manager.displayInfo != nil) ? "music.note" : "music.note.slash"
        ) {
            let scrobbler = manager.lastFM
            if scrobbler.isAuthenticated {
                Text("Signed in as \(scrobbler.username ?? "—")")
            } else {
                Button("Sign In to Last.fm…") {
                    Task { await webAuth.signIn(scrobbler) }
                }
            }
            Divider()

            if settings.showNowPlayingInMenu {
                if let device = manager.displayDeviceName {
                    Text("\(manager.displayInfo?.displayName ?? "No playback detected") · \(device)")
                } else {
                    Text(manager.displayInfo?.displayName ?? "No playback detected")
                }
                if settings.discordPresenceEnabled {
                    discordStatusLabel
                }
                Divider()
            }

            Button("Open Scroblrr") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)

            SettingsLink {
                Text("Settings…")
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }

        SwiftUI.Settings {
            SettingsView(settings: settings, scrobbler: manager.lastFM, updater: updater, onSignOut: { manager.signOut() })
                .modelContainer(modelContainer)
        }
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var discordStatusLabel: some View {
        switch manager.discordPresence.status {
        case .disabled:
            Label("Discord integration disabled", systemImage: "circle")
        case .connecting:
            Label("Connecting to Discord...", systemImage: "circle.dotted")
        case .connected:
            Label("Broadcasting to Discord", systemImage: "checkmark.circle.fill")
        case .error(let message):
            Label("Discord: \(message)", systemImage: "exclamationmark.circle.fill")
        }
    }
    #endif
}
