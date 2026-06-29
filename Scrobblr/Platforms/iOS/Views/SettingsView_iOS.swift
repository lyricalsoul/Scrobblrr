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

    var body: some View {
        Form {
            ScrobblingSection(settings: settings)
            AccountSection(scrobbler: scrobbler)
            Section {
                NavigationLink {
                    CorrectionsListView()
                } label: {
                    Label("Corrections", systemImage: "character.book.closed")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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
            Toggle("Correct artist names with on-device AI", isOn: $settings.useArtistFix)
        } header: {
            Text("Scrobbling")
        } footer: {
            Text("A track scrobbles once you've listened to this much of it, or after the maximum time — whichever comes first. Tracks shorter than the minimum are never scrobbled.")
        }
    }
}

// MARK: - Account

private struct AccountSection: View {
    let scrobbler: LastFMScrobbler
    @State private var webAuth = WebAuthCoordinator()

    var body: some View {
        Section("Last.fm") {
            if scrobbler.isAuthenticated {
                LabeledContent("Signed in as", value: scrobbler.username ?? "—")
                Button("Sign Out", role: .destructive) {
                    scrobbler.signOut()
                }
            } else {
                Button("Sign In to Last.fm…", action: signIn)
            }
        }
    }

    private func signIn() {
        Task {
            let url = scrobbler.authorizationURL(callbackScheme: "scrobblr")
            if let token = await webAuth.authenticate(url: url, callbackScheme: "scrobblr") {
                try? await scrobbler.completeAuthentication(token: token)
            }
        }
    }
}

// MARK: - Corrections

private struct CorrectionsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AutoCorrect.target) private var rules: [AutoCorrect]
    @State private var showingEditor = false

    var body: some View {
        List {
            ForEach(CorrectionEntity.allCases, id: \.self) { kind in
                let kindRules = rules.filter { $0.kind == kind }
                if !kindRules.isEmpty {
                    Section(kind.rawValue.capitalized) {
                        ForEach(kindRules) { rule in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.target)
                                Text(rule.replacement ?? "Don't scrobble")
                                    .font(.footnote)
                                    .foregroundStyle(rule.replacement == nil ? .secondary : .primary)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(kindRules[index]) }
                            try? context.save()
                        }
                    }
                }
            }
        }
        .overlay {
            if rules.isEmpty {
                ContentUnavailableView("No Corrections", systemImage: "character.book.closed", description: Text("Add a rule to rewrite or skip tracks before scrobbling."))
            }
        }
        .navigationTitle("Corrections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingEditor = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingEditor) {
            CorrectionEditor { target, replacement, kind in
                context.insert(AutoCorrect(target: target, replacement: replacement, kind: kind))
                try? context.save()
            }
        }
    }
}

private struct CorrectionEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var target = ""
    @State private var replacement = ""
    @State private var doNotScrobble = false
    @State private var kind: CorrectionEntity = .artist

    /// Called with the entered values; a `nil` replacement means "don't scrobble".
    let onAdd: (String, String?, CorrectionEntity) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Target", text: $target)
                Picker("Type", selection: $kind) {
                    ForEach(CorrectionEntity.allCases, id: \.self) { entity in
                        Text(entity.rawValue.capitalized).tag(entity)
                    }
                }
                Toggle("Don't scrobble matches", isOn: $doNotScrobble)
                if !doNotScrobble {
                    TextField("Replacement", text: $replacement)
                }
            }
            .navigationTitle("New Correction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(target, doNotScrobble ? nil : replacement, kind)
                        dismiss()
                    }
                    .disabled(target.isEmpty || (!doNotScrobble && replacement.isEmpty))
                }
            }
        }
    }
}
#endif
