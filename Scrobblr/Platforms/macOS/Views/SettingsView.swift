//
//  SettingsView.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//

#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

enum SettingsTab: Hashable {
    case general, scrobbling, account, automaticCorrections, manualCorrections
}

/// lets other windows ask settings to open on a specific tab
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var selectedTab: SettingsTab = .general
    private init() {}
}

struct SettingsView: View {
    @Bindable var settings: Settings
    let scrobbler: LastFMScrobbler
    let updater: SparkleUpdater
    let onSignOut: () -> Void

    @State private var navigation = SettingsNavigation.shared

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            GeneralSettingsView(settings: settings, updater: updater)
                .tag(SettingsTab.general)
                .tabItem { Label("General", systemImage: "gearshape") }

            ScrobblingSettingsView(settings: settings)
                .tag(SettingsTab.scrobbling)
                .tabItem { Label("Scrobbling", systemImage: "music.note") }

            AccountSettingsView(scrobbler: scrobbler, onSignOut: onSignOut)
                .tag(SettingsTab.account)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }

            AutomaticCorrectionsSettingsView()
                .tag(SettingsTab.automaticCorrections)
                .tabItem { Label("Automatic Corrections", systemImage: "character.book.closed") }

            ManualCorrectionsSettingsView()
                .tag(SettingsTab.manualCorrections)
                .tabItem { Label("Manual Corrections", systemImage: "pencil.and.list.clipboard") }
        }
        .frame(width: 480)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Bindable var settings: Settings
    let updater: SparkleUpdater
    @State private var login = LoginItemController()

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { login.isEnabled },
                    set: { login.setEnabled($0) }
                ))
                if login.requiresApproval {
                    LabeledContent("Approval needed") {
                        Button("Open Login Items…") { login.openSystemSettings() }
                    }
                }
            } footer: {
                Text("Start Scroblrr automatically when you log in.")
            }

            Section {
                Toggle("Show current track in the menu", isOn: $settings.showNowPlayingInMenu)
            }

            Section {
                Toggle("Show Discord Rich Presence", isOn: $settings.discordPresenceEnabled)
                Toggle("Show what's playing on other devices", isOn: $settings.receiveCrossDevicePresenceEnabled)
            } footer: {
                Text("Broadcasts what you're listening to on Discord. Requires the Discord app to be running. When nothing is playing on this computer, falls back to what's playing on your phone (if cross-presence is enabled).")
            }

            Section {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Scrobbling

private struct ScrobblingSettingsView: View {
    @Bindable var settings: Settings

    var body: some View {
        Form {
            Section {
                Slider(value: $settings.scrobbleThreshold, in: 0.25...1.0, step: 0.05) {
                    Text("Listen threshold")
                } minimumValueLabel: {
                    Text("25%")
                } maximumValueLabel: {
                    Text("100%")
                }
                LabeledContent("Scrobble after", value: "\(Int((settings.scrobbleThreshold * 100).rounded()))% of the track")
            } footer: {
                Text("A track scrobbles once you've listened to this much of it. Last.fm's default is 50%.")
            }

            Section {
                Stepper("Maximum: \(settings.maxScrobbleSeconds / 60) min", value: $settings.maxScrobbleSeconds, in: 60...600, step: 60)
            } footer: {
                Text("Long tracks scrobble after this time even if the percentage hasn't been reached - whichever comes first.")
            }

            Section {
                Stepper("Minimum length: \(settings.minTrackSeconds) s", value: $settings.minTrackSeconds, in: 0...120, step: 5)
            } footer: {
                Text("Tracks shorter than this are never scrobbled.")
            }

            Section {
                Toggle("Correct artist names with on-device AI", isOn: $settings.useArtistFix)
            } footer: {
                Text("Keeps only the primary artist when a track credits several, e.g. \"A, B & C\" becomes \"A\". Runs entirely on device.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Account

private struct AccountSettingsView: View {
    let scrobbler: LastFMScrobbler
    let onSignOut: () -> Void
    @State private var webAuth = WebAuthCoordinator()

    var body: some View {
        Form {
            Section("Last.fm") {
                if scrobbler.isAuthenticated {
                    LabeledContent("Signed in as", value: scrobbler.username ?? "—")
                    Button("Sign Out", role: .destructive, action: onSignOut)
                } else {
                    Text("Connect your Last.fm account to start scrobbling.")
                        .foregroundStyle(.secondary)
                    Button("Sign In to Last.fm…") {
                        Task { await webAuth.signIn(scrobbler) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Automatic Corrections

private struct AutomaticCorrectionsSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Correction.title) private var rules: [Correction]
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var isAddingRule = false
    @State private var editingRule: Correction?

    var body: some View {
        VStack(spacing: 0) {
            Table(rules, selection: $selection) {
                TableColumn("Title") { rule in
                    Text(rule.title)
                }
                TableColumn("Pattern") { rule in
                    Text(rule.pattern)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                TableColumn("Applies To") { rule in
                    Text(rule.entities.map { String(localized: $0.title) }.joined(separator: ", "))
                }
                TableColumn("Enabled") { rule in
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { rule.isEnabled = $0; try? context.save() }
                    ))
                    .labelsHidden()
                }
            }

            Divider()

            HStack(spacing: 4) {
                Button { isAddingRule = true } label: { Image(systemName: "plus") }
                Button { deleteSelected() } label: { Image(systemName: "minus") }
                    .disabled(selection.isEmpty)
                Divider().frame(height: 16)
                Button("Edit…") {
                    if let id = selection.first {
                        editingRule = rules.first { $0.persistentModelID == id }
                    }
                }
                .disabled(selection.count != 1)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
        .correctionSheets(isAdding: $isAddingRule, editing: $editingRule, in: context)
    }

    private func deleteSelected() {
        for id in selection {
            if let rule = rules.first(where: { $0.persistentModelID == id }) {
                context.delete(rule)
            }
        }
        try? context.save()
        selection.removeAll()
    }
}

// MARK: - Manual Corrections

private struct ManualCorrectionsSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ManualCorrection.artistName) private var rules: [ManualCorrection]
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var isAddingRule = false
    @State private var editingRule: ManualCorrection?

    var body: some View {
        VStack(spacing: 0) {
            Table(rules, selection: $selection) {
                TableColumn("Type") { rule in
                    Text(rule.kind.title)
                }
                TableColumn("Track") { rule in
                    Text(rule.kind == .track ? rule.trackName : "")
                }
                TableColumn("Album") { rule in
                    Text(rule.kind == .track || rule.kind == .album ? rule.albumName : "")
                }
                TableColumn("Artist") { rule in
                    Text(rule.artistName)
                }
                TableColumn("Replacement") { rule in
                    rule.replacement.map { Text(verbatim: $0) } ?? Text("Don't scrobble")
                        .foregroundStyle(rule.replacement == nil ? .secondary : .primary)
                }
            }

            Divider()

            HStack(spacing: 4) {
                Button { isAddingRule = true } label: { Image(systemName: "plus") }
                Button { deleteSelected() } label: { Image(systemName: "minus") }
                    .disabled(selection.isEmpty)
                Divider().frame(height: 16)
                Button("Edit…") {
                    if let id = selection.first {
                        editingRule = rules.first { $0.persistentModelID == id }
                    }
                }
                .disabled(selection.count != 1)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
        .manualCorrectionSheets(isAdding: $isAddingRule, editing: $editingRule, in: context)
    }

    private func deleteSelected() {
        for id in selection {
            if let rule = rules.first(where: { $0.persistentModelID == id }) {
                context.delete(rule)
            }
        }
        try? context.save()
        selection.removeAll()
    }
}
#endif
