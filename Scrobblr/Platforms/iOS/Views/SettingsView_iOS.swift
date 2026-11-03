//
//  SettingsView.swift (iOS)
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//

#if os(iOS)
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var settings: Settings
    let scrobbler: LastFMScrobbler
    let onSignOut: () -> Void

    var body: some View {
        Form {
            ScrobblingSection(settings: settings)
            AutomaticCorrectionSection()
            ManualCorrectionSection()
            AccountSection(scrobbler: scrobbler, onSignOut: onSignOut)
            PresenceSection(settings: settings)
            ExperimentalSection(settings: settings)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Presence

private struct PresenceSection: View {
    @Bindable var settings: Settings

    var body: some View {
        Section {
            Toggle("Share now playing across devices", isOn: $settings.crossDevicePresenceEnabled)
        } footer: {
            Text("Lets a Mac with Scrobblrr and Discord open show what you're listening to here. Your data is protected and only your last.fm account can access it.")
        }
    }
}

// MARK: - Experimental

private struct ExperimentalSection: View {
    @Bindable var settings: Settings

    var body: some View {
        Section {
            Toggle("Use MPMusicPlayerController recovery", isOn: $settings.useMPMusicPlayerRecovery)
        } header: {
            Text("Experimental")
        } footer: {
            Text("Recovers a stale now-playing connection by resetting MPMusicPlayerController instead of the silent audio session.")
        }
    }
}

// MARK: - Scrobbling

private struct ScrobblingSection: View {
    @Bindable var settings: Settings

    var body: some View {
        Section {
            VStack(alignment: .leading) {
                Slider(value: $settings.scrobbleThreshold, in: 0.25...1.0, step: 0.05) {
                    Text("Listen threshold")
                } minimumValueLabel: {
                    Text("25%")
                } maximumValueLabel: {
                    Text("100%")
                }
                Text("Scrobble after \(Int((settings.scrobbleThreshold * 100).rounded()))% of the track")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Stepper("Maximum: \(settings.maxScrobbleSeconds / 60) min", value: $settings.maxScrobbleSeconds, in: 60...600, step: 60)
            Stepper("Minimum length: \(settings.minTrackSeconds) s", value: $settings.minTrackSeconds, in: 0...120, step: 5)
        } header: {
            Text("Scrobbling")
        } footer: {
            Text("A track scrobbles once you've listened to this much of it, or after the maximum time — whichever comes first. Tracks shorter than the minimum are never scrobbled.")
        }
    }
}

// MARK: - Corrections

private struct AutomaticCorrectionSection: View {
    var body: some View {
        Section {
            NavigationLink {
                AutomaticCorrectionsListView()
            } label: {
                Text("Automatic Corrections")
            }
        } footer: {
            Text("Pattern-based rules that rewrite or skip tracks and albums before scrobbling.")
        }
    }
}

private struct ManualCorrectionSection: View {
    var body: some View {
        Section {
            NavigationLink {
                ManualCorrectionsListView()
            } label: {
                Text("Manual Corrections")
            }
        } footer: {
            Text("Exact overrides for specific tracks, albums, or artists.")
        }
    }
}

// MARK: - Account

private struct AccountSection: View {
    let scrobbler: LastFMScrobbler
    let onSignOut: () -> Void
    @State private var webAuth = WebAuthCoordinator()

    var body: some View {
        Section("Last.fm") {
            if scrobbler.isAuthenticated {
                LabeledContent("Signed in as", value: scrobbler.username ?? "—")
                Button("Sign Out", role: .destructive, action: onSignOut)
            } else {
                Button("Sign In to Last.fm…") {
                    Task { await webAuth.signIn(scrobbler) }
                }
            }
        }
    }
}

// MARK: - Manual Corrections

private struct ManualCorrectionsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ManualCorrection.artistName) private var rules: [ManualCorrection]
    @State private var isAddingRule = false
    @State private var editingRule: ManualCorrection?

    var body: some View {
        List {
            ForEach(rules) { rule in
                Button {
                    editingRule = rule
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.kind == .track ? rule.trackName : (rule.kind == .album ? rule.albumName : rule.artistName))
                        rule.replacement.map { Text(verbatim: $0) } ?? Text("Don't scrobble")
                            .font(.footnote)
                            .foregroundStyle(rule.replacement == nil ? .secondary : .primary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets { context.delete(rules[index]) }
                try? context.save()
            }
        }
        .overlay {
            if rules.isEmpty {
                ContentUnavailableView("No Manual Corrections", systemImage: "pencil.and.list.clipboard", description: Text("Add an exact override for a specific track, album, or artist."))
            }
        }
        .navigationTitle("Manual Corrections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAddingRule = true } label: { Image(systemName: "plus") }
            }
        }
        .manualCorrectionSheets(isAdding: $isAddingRule, editing: $editingRule, in: context)
    }
}
#endif
