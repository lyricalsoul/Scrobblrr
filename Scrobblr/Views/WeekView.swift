//
//  WeekView.swift
//  Scrobblr
//
//  Created by Renan Martins on 6/30/26.
//


import SwiftUI
import CachedAsyncImage
import LastFM

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
                    Picker("Period", selection: $period) {
                        Text("Last 7 Days").tag(LastFMPeriod.week)
                        Text("Last 30 Days").tag(LastFMPeriod.month)
                        Text("Last 90 Days").tag(LastFMPeriod.threeMonths)
                        Text("Last 180 Days").tag(LastFMPeriod.sixMonths)
                        Text("Last Year").tag(LastFMPeriod.twelveMonths)
                        Text("All Time").tag(LastFMPeriod.allTime)
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
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
    }

    @ViewBuilder
    private var columns: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            artistList
            Divider()
            albumList
            Divider()
            trackList
        }
        #else
        List {
            Section("Top artists") {
                ForEach(topArtists, id: \.name) { ArtistRow(data: $0) }
            }
            Section("Top albums") {
                ForEach(topAlbums, id: \.name) { AlbumRow(data: $0) }
            }
            Section("Top tracks") {
                ForEach(topTracks, id: \.name) { TrackRow(data: $0) }
            }
        }
        #endif
    }
    
    // MARK: - Data Fetching
    
    private func fetchTopData() async {
        isLoading = true
        
        // fire all three requests concurrently
        async let fetchedArtists = manager.lastFM.getUserTop(for: .artist, during: period)
        async let fetchedAlbums = manager.lastFM.getUserTop(for: .album, during: period)
        async let fetchedTracks = manager.lastFM.getUserTop(for: .track, during: period)
        
        topArtists = (await fetchedArtists) ?? []
        topAlbums = (await fetchedAlbums) ?? []
        topTracks = (await fetchedTracks) ?? []
        
        isLoading = false
    }

    // MARK: - Columns (macOS)

    private var artistList: some View {
        List {
            Section("Top artists") {
                ForEach(topArtists, id: \.name) { artist in
                    ArtistRow(data: artist)
                        .contextMenu {
                            Button("View artist") {}
                            Button("Copy name") {}
                        }
                }
            }
        }
        .listStyle(.inset)
    }

    private var albumList: some View {
        List {
            Section("Top albums") {
                ForEach(topAlbums, id: \.name) { album in
                    AlbumRow(data: album)
                        .contextMenu {
                            Button("View album") {}
                            Button("Copy title") {}
                        }
                }
            }
        }
        .listStyle(.inset)
    }

    private var trackList: some View {
        List {
            Section("Top tracks") {
                ForEach(topTracks, id: \.name) { track in
                    TrackRow(data: track)
                        .contextMenu {
                            Button("View track") {}
                            Button("Copy title") {}
                        }
                }
            }
        }
        .listStyle(.inset)
    }
}

// MARK: - Rows

// TODO: artist and track images won't show because we need to use entity.getInfo - the image supplied is empty.
private struct ArtistRow: View {
    let data: SimpleTopData
    var body: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: data.image.large) { image in
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
        .padding(.vertical, 2)
    }
}

private struct AlbumRow: View {
    let data: SimpleTopData
    var body: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: data.image.large) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } placeholder: {
                return RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.gradient)
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "opticaldisc").font(.caption).foregroundStyle(.white.opacity(0.9)))
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
        .padding(.vertical, 2)
    }
}

private struct TrackRow: View {
    let data: SimpleTopData
    var body: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: data.image.large) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } placeholder: {
                return RoundedRectangle(cornerRadius: 6)
                    .fill(Color.purple.gradient)
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "music.note").font(.caption).foregroundStyle(.white.opacity(0.9)))
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
        .padding(.vertical, 2)
    }
}
