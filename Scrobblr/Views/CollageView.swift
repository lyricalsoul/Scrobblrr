//
//  CollageView.swift
//  Scrobblr
//
//  Created by Renan Martins on 6/30/26.
//

import SwiftUI
import CachedAsyncImage
import os

struct CollageView: View {
    let manager: ScrobblerManager

    @State private var theme: CollageTheme = .classic
    @State private var type: LastFMEntity = .album
    @State private var period: LastFMPeriod = .week
    @State private var rows = 4
    @State private var columns = 4
    @State private var showLabels = true
    @State private var showPlayCount = false
    @State private var padded = false

    @State private var generatedURL: URL?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private let maxGrid = 15

    private var isSignedIn: Bool { manager.lastFM.username != nil }

    var body: some View {
        #if os(macOS)
        HSplitView {
            controlsPane
                .scrollContentBackground(.hidden)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380, maxHeight: .infinity)

            preview
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Collage")
        #else
        VStack(spacing: 0) {
            Form {
                controlSections
                previewSection
            }
            bottomBar
        }
        .navigationTitle("Collage")
        .toolbar { shareButton }
        #endif
    }

    // MARK: - Controls

    #if os(macOS)
    private var controlsPane: some View {
        VStack(spacing: 0) {
            Form { controlSections }
                .formStyle(.grouped)
            Divider()
            bottomBar
        }
    }
    #endif

    @ViewBuilder
    private var controlSections: some View {
        Section("Source") {
            Picker("Theme", selection: $theme) {
                ForEach(CollageTheme.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Type", selection: $type) {
                ForEach(LastFMEntity.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Time period", selection: $period) {
                ForEach(LastFMPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
        }

        Section("Layout") {
            if theme.supportsGrid {
                Stepper("Rows: \(rows)", value: $rows, in: 1...maxGrid)
                Stepper("Columns: \(columns)", value: $columns, in: 1...maxGrid)
                Toggle("Padding between covers", isOn: $padded)
            } else {
                Text("Asymmetric layouts size themselves.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Toggle("Show labels", isOn: $showLabels)
            Toggle("Show play counts", isOn: $showPlayCount)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button {
                Task { await generate() }
            } label: {
                Label("Generate", systemImage: "wand.and.stars")
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .controlSize(.large)
            .disabled(isGenerating || !isSignedIn)

            footerMessage
        }
        .padding()
    }

    @ViewBuilder
    private var footerMessage: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !isSignedIn {
            Text("Sign in to Last.fm to generate a collage.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Collage Preview

    #if os(macOS)
    @ViewBuilder
    private var preview: some View {
        if isGenerating {
            ProgressView("Generating…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let url = generatedURL {
            // TODO: this is still getting clipped on iOS...
            GeometryReader { geo in
                let side = max(0, min(geo.size.width, geo.size.height) - 40)
                collageImage(url: url)
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar { shareButton }
        } else {
            ContentUnavailableView(
                "No Collage Yet",
                systemImage: "square.grid.3x3",
                description: Text("Choose your options and tap Generate.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    #else
    @ViewBuilder
    private var previewSection: some View {
        if isGenerating {
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                    .listRowBackground(Color.clear)
            }
        } else if let url = generatedURL {
            Section("Preview") {
                collageImage(url: url)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 420)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }
    #endif

    private func collageImage(url: URL) -> some View {
        CachedAsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            Rectangle()
                .fill(.quaternary)
                .overlay { ProgressView() }
        }
    }

    @ToolbarContentBuilder
    private var shareButton: some ToolbarContent {
        ToolbarItem {
            if let url = generatedURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Share")
            }
        }
    }

    // MARK: - Generation

    @MainActor
    private func generate() async {
        guard let username = manager.lastFM.username else {
            errorMessage = "Sign in to Last.fm first."
            return
        }

        isGenerating = true
        errorMessage = nil

        do {
            let remoteURL = try await Ditto(username: username).generateCollage(
                theme: theme,
                entity: type,
                period: period,
                rows: rows,
                columns: columns,
                showLabels: showLabels,
                showPlayCount: showPlayCount,
                padded: padded
            )


            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(remoteURL.lastPathComponent)
            try data.write(to: fileURL, options: .atomic)
            generatedURL = fileURL
        } catch {
            errorMessage = error.localizedDescription
            Logger.ditto.error("Collage generation failed: \(error.localizedDescription, privacy: .public)")
        }

        isGenerating = false
    }
}
