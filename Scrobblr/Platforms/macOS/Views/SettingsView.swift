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

struct SettingsView: View {
    @Bindable var settings: Settings
    let scrobbler: LastFMScrobbler

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }

            ScrobblingSettingsView(settings: settings)
                .tabItem { Label("Scrobbling", systemImage: "music.note") }

            AccountSettingsView(scrobbler: scrobbler)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }

            CorrectionsSettingsView()
                .tabItem { Label("Corrections", systemImage: "character.book.closed") }
        }
        .frame(width: 480)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Bindable var settings: Settings
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
                Text("Long tracks scrobble after this time even if the percentage hasn't been reached — whichever comes first.")
            }

            Section {
                Stepper("Minimum length: \(settings.minTrackSeconds) s", value: $settings.minTrackSeconds, in: 0...120, step: 5)
            } footer: {
                Text("Tracks shorter than this are never scrobbled.")
            }

            Section {
                Toggle("Correct artist names with on-device AI", isOn: $settings.useArtistFix)
            } footer: {
                Text("Keeps only the primary artist when a track credits several, e.g. \u{201C}A, B & C\u{201D} \u{2192} \u{201C}A\u{201D}. Runs entirely on device.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Account

private struct AccountSettingsView: View {
    let scrobbler: LastFMScrobbler

    var body: some View {
        Form {
            Section("Last.fm") {
                if scrobbler.isAuthenticated {
                    LabeledContent("Signed in as", value: scrobbler.username ?? "—")
                    Button("Sign Out", role: .destructive) {
                        scrobbler.signOut()
                    }
                } else if scrobbler.isAwaitingAuthorization {
                    Text("Authorize Scroblrr in the browser, then finish signing in.")
                        .foregroundStyle(.secondary)
                    Button("Finish Sign-In") {
                        Task { try? await scrobbler.finishAuthentication() }
                    }
                } else {
                    Text("Connect your Last.fm account to start scrobbling.")
                        .foregroundStyle(.secondary)
                    Button("Sign In to Last.fm…") {
                        Task {
                            if let url = try? await scrobbler.beginAuthentication() {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Corrections

private struct CorrectionsSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AutoCorrect.target) private var rules: [AutoCorrect]
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var selectedKind: CorrectionEntity = .artist

    /// Rules belonging to the currently selected entity tab.
    private var visibleRules: [AutoCorrect] {
        rules.filter { $0.kind == selectedKind }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedKind) {
                ForEach(CorrectionEntity.allCases, id: \.self) { entity in
                    Text(entity.rawValue.capitalized).tag(entity)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Table(visibleRules, selection: $selection) {
                TableColumn("Target") { rule in
                    TextField("Target", text: Binding(
                        get: { rule.target },
                        set: { rule.target = $0; try? context.save() }
                    ))
                    .textFieldStyle(.plain)
                }
                TableColumn("Replacement") { rule in
                    // An empty replacement means "don't scrobble" (stored as nil).
                    TextField("Don't scrobble", text: Binding(
                        get: { rule.replacement ?? "" },
                        set: { rule.replacement = $0.isEmpty ? nil : $0; try? context.save() }
                    ))
                    .textFieldStyle(.plain)
                    .foregroundStyle(rule.replacement == nil ? .secondary : .primary)
                }
            }

            Divider()

            HStack(spacing: 4) {
                Button {
                    addRule()
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    deleteSelected()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection.isEmpty)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    private func addRule() {
        let rule = AutoCorrect(target: "", replacement: "", kind: selectedKind)
        context.insert(rule)
        try? context.save()
        selection = [rule.persistentModelID]
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
