//
//  CorrectionQuickEditSheet.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/26/26.
//

import SwiftUI
import SwiftData

struct CorrectionQuickEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    let track: GenericPlaybackInfo
    let manager: ScrobblerManager

    @Query private var allManualRules: [ManualCorrection]

    @State private var editingEntity: CorrectionEntity?
    @State private var editingExistingRule: ManualCorrection?
    @State private var showingAutomaticCorrections = false

    private var matchingRules: [ManualCorrection] {
        allManualRules.filter { $0.matches(track: track.title, album: track.album, artist: track.artist) }
    }

    private func hasExistingRule(for kind: CorrectionEntity) -> Bool {
        matchingRules.contains { $0.kind == kind }
    }

    private func currentValue(for kind: CorrectionEntity) -> String {
        switch kind {
        case .track: return track.title
        case .album: return track.album ?? ""
        case .artist: return track.artist
        }
    }

    private func icon(for kind: CorrectionEntity) -> String {
        switch kind {
        case .track: return "music.note"
        case .album: return "square.stack"
        case .artist: return "person.fill"
        }
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            form
            Divider()
            HStack {
                Button("Automatic Corrections…") {
                    SettingsNavigation.shared.selectedTab = .automaticCorrections
                    dismiss()
                    openSettings()
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 360)
        #else
        form
        .presentationDetents([.medium, .large])
        #endif
    }

    private var form: some View {
        NavigationStack {
            Form {
                Section {
                    if !hasExistingRule(for: .track) {
                        Button { editingEntity = .track } label: {
                            Label("Correct Title", systemImage: icon(for: .track))
                        }
                    }
                    if let album = track.album, !album.isEmpty, !hasExistingRule(for: .album) {
                        Button { editingEntity = .album } label: {
                            Label("Correct Album", systemImage: icon(for: .album))
                        }
                    }
                    if !hasExistingRule(for: .artist) {
                        Button { editingEntity = .artist } label: {
                            Label("Correct Artist", systemImage: icon(for: .artist))
                        }
                    }
                }

                if !matchingRules.isEmpty {
                    Section("Existing Corrections") {
                        ForEach(matchingRules) { rule in
                            Button {
                                editingExistingRule = rule
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: icon(for: rule.kind))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rule.kind.title)
                                        rule.replacement.map { Text(verbatim: $0) } ?? Text("Don't scrobble")
                                            .font(.footnote)
                                            .foregroundStyle(rule.replacement == nil ? .secondary : .primary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                #if os(iOS)
                Section {
                    Button {
                        showingAutomaticCorrections = true
                    } label: {
                        Label("Go to Automatic Corrections", systemImage: "character.book.closed")
                    }
                }
                #endif
            }
            .formStyle(.grouped)
            .navigationTitle("Corrections")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
            .sheet(item: $editingEntity) { kind in
                ManualCorrectionEditor(
                    kind: kind,
                    trackName: track.title,
                    albumName: track.album ?? "",
                    artistName: track.artist,
                    replacement: currentValue(for: kind),
                    isContextLocked: true
                ) { kind, trackName, albumName, artistName, replacement in
                    context.insert(ManualCorrection(kind: kind, trackName: trackName, albumName: albumName, artistName: artistName, replacement: replacement))
                    try? context.save()
                    manager.refreshCurrentTrackCorrections()
                }
            }
            .sheet(item: $editingExistingRule) { rule in
                ManualCorrectionEditor(editing: rule, in: context, isContextLocked: true) {
                    manager.refreshCurrentTrackCorrections()
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingAutomaticCorrections) {
                NavigationStack {
                    AutomaticCorrectionsListView()
                }
            }
            #endif
        }
    }
}
