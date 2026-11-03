//
//  AutomaticCorrectionsListView.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/26/26.
//

import SwiftUI
import SwiftData

struct AutomaticCorrectionsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Correction.title) private var rules: [Correction]
    @State private var isAddingRule = false
    @State private var editingRule: Correction?

    var body: some View {
        List {
            ForEach(rules) { rule in
                HStack {
                    Button {
                        editingRule = rule
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.title)
                            Text(rule.entities.map { String(localized: $0.title) }.joined(separator: ", "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { rule.isEnabled = $0; try? context.save() }
                    ))
                    .labelsHidden()
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(rules[index]) }
                try? context.save()
            }
        }
        .overlay {
            if rules.isEmpty {
                ContentUnavailableView("No Corrections", systemImage: "character.book.closed", description: Text("Add a rule to rewrite or skip tracks before scrobbling."))
            }
        }
        .navigationTitle("Automatic Corrections")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAddingRule = true } label: { Image(systemName: "plus") }
            }
        }
        .correctionSheets(isAdding: $isAddingRule, editing: $editingRule, in: context)
    }
}
