//
//  CorrectionEditor.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/26/26.
//

import SwiftUI
import SwiftData

struct CorrectionEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var pattern: String
    @State private var replacement: String
    @State private var doNotScrobble: Bool
    @State private var entities: Set<CorrectionEntity>

    private let sampleText: String
    let onSave: (String, String, String?, [CorrectionEntity]) -> Void

    init(
        title: String = "",
        pattern: String = "",
        replacement: String = "",
        doNotScrobble: Bool = false,
        entities: [CorrectionEntity] = [.track],
        sampleText: String = "Do It (Single)",
        onSave: @escaping (String, String, String?, [CorrectionEntity]) -> Void
    ) {
        _title = State(initialValue: title)
        _pattern = State(initialValue: pattern)
        _replacement = State(initialValue: replacement)
        _doNotScrobble = State(initialValue: doNotScrobble)
        _entities = State(initialValue: Set(entities))
        self.sampleText = sampleText
        self.onSave = onSave
    }

    private var previewText: String? {
        guard !pattern.isEmpty else { return nil }
        if doNotScrobble {
            return "\(sampleText) → (won't scrobble)"
        }
        guard let regex = try? Regex(pattern).ignoresCase(),
              let match = try? regex.firstMatch(in: sampleText) else { return nil }
        let result = sampleText.replacingCharacters(in: match.range, with: replacement)
        return "\(sampleText) → \(result)"
    }

    private var isValid: Bool {
        guard !title.isEmpty, !pattern.isEmpty, !entities.isEmpty else { return false }
        return (try? Regex(pattern)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Pattern", text: $pattern)
                    .font(.system(.body, design: .monospaced))

                Toggle("Don't scrobble matches", isOn: $doNotScrobble)
                if !doNotScrobble {
                    TextField("Replacement", text: $replacement)
                }

                if let previewText {
                    Section {
                        Text(previewText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Applies to") {
                    ForEach(CorrectionEntity.allCases) { entity in
                        Toggle(entity.title, isOn: Binding(
                            get: { entities.contains(entity) },
                            set: { isOn in
                                if isOn { entities.insert(entity) } else { entities.remove(entity) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Correction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, pattern, doNotScrobble ? nil : replacement, Array(entities))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

extension View {
    func correctionSheets(isAdding: Binding<Bool>, editing: Binding<Correction?>, in context: ModelContext) -> some View {
        sheet(isPresented: isAdding) {
            CorrectionEditor { title, pattern, replacement, entities in
                context.insert(Correction(title: title, pattern: pattern, replacement: replacement, entities: entities))
                try? context.save()
            }
        }
        .sheet(item: editing) { rule in
            CorrectionEditor(title: rule.title, pattern: rule.pattern, replacement: rule.replacement ?? "", doNotScrobble: rule.replacement == nil, entities: rule.entities) { title, pattern, replacement, entities in
                rule.title = title
                rule.pattern = pattern
                rule.replacement = replacement
                rule.entities = entities
                try? context.save()
            }
        }
    }
}
