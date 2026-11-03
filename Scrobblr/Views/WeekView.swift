//
//  WeekView.swift
//  Scrobblr
//
//  Created by Renan Martins on 6/30/26.
//


import SwiftUI
import CachedAsyncImage
import os

struct WeekView: View {
    let manager: ScrobblerManager
    
    @State private var period: LastFMPeriod = .week
    
    // TODO: cache meeee!
    @State private var topArtists: [SimpleTopData] = []
    @State private var topAlbums: [SimpleTopData] = []
    @State private var topTracks: [SimpleTopData] = []
    
    @State private var isLoading = false

    var body: some View {
        columns
            .navigationTitle("Your stats on Last.fm")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(LastFMPeriod.allCases) { candidate in
                            Button(candidate.title) { period = candidate }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(period.title)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
            }
            .task(id: period) {
                await fetchTopData()
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            #if os(iOS)
            .background { AnimatedBackdrop(url: manager.coverImageUrl) }
            #endif
    }

    @ViewBuilder
    private var columns: some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 20) {
            artistColumn
            albumColumn
            trackColumn
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .ignoresSafeArea(edges: .bottom)
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                artistColumn
                albumColumn
                trackColumn
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        #endif
    }
    
    // MARK: - Data Fetching
    
    private func fetchTopData() async {
        guard let username = manager.lastFM.username else {
            topArtists = []; topAlbums = []; topTracks = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let charts = try await Epistolares().userChartsAll(username: username, period: period, limit: 10)
            topArtists = charts.artists.items.map(SimpleTopData.init)
            topAlbums = charts.albums.items.map(SimpleTopData.init)
            topTracks = charts.tracks.items.map(SimpleTopData.init)
        } catch {
            Logger.epistolares.error("Couldn't fetch charts: \(error.localizedDescription, privacy: .public)")
            topArtists = []; topAlbums = []; topTracks = []
        }
    }

    // MARK: - Columns (macOS)

    private var artistColumn: some View {
        chartColumn(title: "Top artists", items: topArtists) { artist in
            ArtistRow(data: artist)
                .infoLink(artist.id.map { .artist(id: $0, name: artist.name) })
        }
    }

    private var albumColumn: some View {
        chartColumn(title: "Top albums", items: topAlbums) { album in
            CoverRow(data: album, color: .blue, symbol: "opticaldisc")
                .infoLink(album.id.map { .album(id: $0, name: album.name) })
        }
    }

    private var trackColumn: some View {
        chartColumn(title: "Top tracks", items: topTracks) { track in
            CoverRow(data: track, color: .purple, symbol: "music.note")
                .infoLink(track.id.map { .track(id: $0, name: track.name) })
        }
    }

    private func chartColumn<Row: View>(
        title: String,
        items: [SimpleTopData],
        @ViewBuilder row: @escaping (SimpleTopData) -> Row
    ) -> some View {
        #if os(macOS)
        ScrollView {
            chartSection(title: title, items: items, row: row)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 20)
        }
        .scrollEdgeEffectHidden(true, for: .bottom)
        .frame(maxWidth: .infinity)
        #else
        chartSection(title: title, items: items, row: row)
        #endif
    }

    private func chartSection<Row: View>(
        title: String,
        items: [SimpleTopData],
        @ViewBuilder row: @escaping (SimpleTopData) -> Row
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .fixedSize()

            DividedGlassCard(items: items, id: \.listKey, dividerLeadingInset: 54) { item in
                row(item)
                    .padding(.horizontal, 14)
            }
        }
    }
}

// MARK: - Rows

private struct ArtistRow: View {
    let data: SimpleTopData
    var body: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: data.coverURL) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
            } placeholder: {
                return Circle()
                    .fill(Color.red.gradient)
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "music.mic").font(.caption).foregroundStyle(.white.opacity(0.9)))
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(data.name).font(.body).lineLimit(1).truncationMode(.tail)
                Text("\(data.scrobbles) scrobbles").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }
}

private struct CoverRow: View {
    let data: SimpleTopData
    let color: Color
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: data.coverURL) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } placeholder: {
                return RoundedRectangle(cornerRadius: 6)
                    .fill(color.gradient)
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: symbol).font(.caption).foregroundStyle(.white.opacity(0.9)))
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(data.name).font(.body).lineLimit(1).truncationMode(.tail)
                if let artist = data.artist {
                    Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer()
            Text("\(data.scrobbles) scrobbles").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }
}
