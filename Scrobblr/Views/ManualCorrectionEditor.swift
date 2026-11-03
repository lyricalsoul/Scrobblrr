//
//  ManualCorrectionEditor.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/26/26.
//

import SwiftUI
import SwiftData

struct ManualCorrectionEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var kind: CorrectionEntity
    @State private var trackName: String
    @State private var albumName: String
    @State private var artistName: String
    @State private var replacement: String
    @State private var doNotScrobble: Bool

    private let isContextLocked: Bool
    let onSave: (CorrectionEntity, String, String, String, String?) -> Void

    init(
        kind: CorrectionEntity = .artist,
        trackName: String = "",
        albumName: String = "",
        artistName: String = "",
        replacement: String = "",
        doNotScrobble: Bool = false,
        isContextLocked: Bool = false,
        onSave: @escaping (CorrectionEntity, String, String, String, String?) -> Void
    ) {
        _kind = State(initialValue: kind)
        _trackName = State(initialValue: trackName)
        _albumName = State(initialValue: albumName)
        _artistName = State(initialValue: artistName)
        _replacement = State(initialValue: replacement)
        _doNotScrobble = State(initialValue: doNotScrobble)
        self.isContextLocked = isContextLocked
        self.onSave = onSave
    }

    private var isValid: Bool {
        guard !artistName.isEmpty else { return false }
        if kind == .album || kind == .track, albumName.isEmpty { return false }
        if kind == .track, trackName.isEmpty { return false }
        return doNotScrobble || !replacement.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if isContextLocked {
                    if kind == .track { LabeledContent("Track", value: trackName) }
                    if kind == .track || kind == .album { LabeledContent("Album", value: albumName) }
                    LabeledContent("Artist", value: artistName)
                } else {
                    Picker("Type", selection: $kind) {
                        ForEach(CorrectionEntity.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    if kind == .track {
                        TextField("Track", text: $trackName)
                    }
                    if kind == .track || kind == .album {
                        TextField("Album", text: $albumName)
                    }
                    TextField("Artist", text: $artistName)
                }

                Toggle("Don't scrobble matches", isOn: $doNotScrobble)
                if !doNotScrobble {
                    Section("Correct to") {
                        TextField("Correct to", text: $replacement)
                            .labelsHidden()
                    }
                }
            }
            .navigationTitle("Manual Correction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(kind, trackName, albumName, artistName, doNotScrobble ? nil : replacement)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

extension ManualCorrectionEditor {
    /// edits `rule` in place and saves the context
    init(editing rule: ManualCorrection, in context: ModelContext, isContextLocked: Bool = false, onSaved: @escaping () -> Void = {}) {
        self.init(kind: rule.kind, trackName: rule.trackName, albumName: rule.albumName, artistName: rule.artistName, replacement: rule.replacement ?? "", doNotScrobble: rule.replacement == nil, isContextLocked: isContextLocked) { kind, trackName, albumName, artistName, replacement in
            rule.kind = kind
            rule.trackName = trackName
            rule.albumName = albumName
            rule.artistName = artistName
            rule.replacement = replacement
            try? context.save()
            onSaved()
        }
    }
}

extension View {
    func manualCorrectionSheets(isAdding: Binding<Bool>, editing: Binding<ManualCorrection?>, in context: ModelContext) -> some View {
        sheet(isPresented: isAdding) {
            ManualCorrectionEditor { kind, trackName, albumName, artistName, replacement in
                context.insert(ManualCorrection(kind: kind, trackName: trackName, albumName: albumName, artistName: artistName, replacement: replacement))
                try? context.save()
            }
        }
        .sheet(item: editing) { ManualCorrectionEditor(editing: $0, in: context) }
    }
}
