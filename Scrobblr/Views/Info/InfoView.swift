//
//  InfoView.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/2/26.
//

import SwiftUI
import CachedAsyncImage
import os

enum InfoMetrics {
    #if os(macOS)
    static let hMargin: CGFloat = 0
    static let titleAlignment = HorizontalAlignment.leading
    static let titleTextAlignment = TextAlignment.leading
    static let titleFrameAlignment = Alignment.leading
    #else
    static let hMargin: CGFloat = 24
    static let titleAlignment = HorizontalAlignment.center
    static let titleTextAlignment = TextAlignment.center
    static let titleFrameAlignment = Alignment.center
    #endif

    static func macCoverSide(for size: CGSize) -> CGFloat {
        let ideal = min(size.width * 0.42, size.height - 56)
        return max(240, min(ideal, 480))
    }

    static func isWide(_ size: CGSize) -> Bool {
        size.width >= 700 || size.width > size.height
    }
}

struct InfoStat: Identifiable {
    let value: Int
    let caption: String
    var id: String { caption }

    static func counts(listeners: Int, scrobbles: Int, mine: Int?) -> [InfoStat] {
        var stats = [InfoStat(value: listeners, caption: "Listeners"), InfoStat(value: scrobbles, caption: "Scrobbles")]
        if let mine { stats.append(InfoStat(value: mine, caption: "Your Scrobbles")) }
        return stats
    }
}

/// fetches an entity for an info page, with loading and retry states
struct InfoLoader<Info, Content: View>: View {
    let id: String
    let name: String
    let fetch: () async throws -> Info
    @ViewBuilder let content: (Info) -> Content

    private enum LoadState {
        case loading
        case loaded(Info)
        case failed
    }

    @State private var state: LoadState = .loading

    var body: some View {
        loadedContent
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .task(id: id) { await load() }
    }

    @ViewBuilder
    private var loadedContent: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ContentUnavailableView {
                Label("Couldn't Load", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Something went wrong fetching \(name).")
            } actions: {
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
        case let .loaded(info):
            content(info)
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await fetch())
        } catch {
            Logger.epistolares.error("Couldn't fetch \(name, privacy: .public) (\(id, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            state = .failed
        }
    }
}

struct InfoView<Extra: View>: View {
    let coverURL: URL?
    let title: String

    var subtitle: String? = nil
    let stats: [InfoStat]
    let tags: [String]
    var bioSummary: String? = nil
    var bioContent: String? = nil
    var lastFMURL: URL? = nil
    @ViewBuilder var extra: () -> Extra

    @State private var bioExpanded = false

    var body: some View {
        GeometryReader { geo in
            #if os(macOS)
            ScrollView {
                sideBySideLayout(side: InfoMetrics.macCoverSide(for: geo.size))
            }
            #else
            if InfoMetrics.isWide(geo.size) {
                wideColumns(side: InfoMetrics.macCoverSide(for: geo.size))
            } else {
                ScrollView { stackedLayout }
                    .ignoresSafeArea(edges: .top)
            }
            #endif
        }
        .background { AnimatedBackdrop(url: coverURL) }
    }

    #if os(iOS)
    private func wideColumns(side: CGFloat) -> some View {
        HStack(spacing: 28) {
            sideBySideCover(side: side)
                .frame(maxHeight: .infinity)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleBlock(leading: true)
                    if !stats.isEmpty { statsRow }
                    if !tags.isEmpty { tagsRow }
                    bioBlock
                    extra()
                }
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 28)
    }

    private var stackedLayout: some View {
        VStack(spacing: 22) {
            cover
            VStack(spacing: 22) {
                titleBlock()
                if !stats.isEmpty { statsRow }
                if !tags.isEmpty { tagsRow }
                bioBlock
                extra()
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
    }
    #endif

    private func sideBySideLayout(side: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 28) {
            sideBySideCover(side: side)
            VStack(alignment: .leading, spacing: 22) {
                titleBlock(leading: true)
                if !stats.isEmpty { statsRow }
                if !tags.isEmpty { tagsRow }
                bioBlock
                extra()
            }
            .frame(maxWidth: .infinity, minHeight: side, alignment: .topLeading)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Cover

    private var coverImage: some View {
        CachedAsyncImage(url: coverURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Rectangle()
                .fill(.quaternary)
                .overlay(Image(systemName: "music.note").font(.system(size: 56)).foregroundStyle(.secondary))
        }
    }

    private func sideBySideCover(side: CGFloat) -> some View {
        coverImage
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(radius: 18, y: 10)
    }

    #if os(iOS)
    private var cover: some View {
        Color.clear
            .frame(height: 450)
            .overlay { coverImage }
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.62),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
    #endif

    // MARK: - Title

    private func titleBlock(leading: Bool = InfoMetrics.titleAlignment == .leading) -> some View {
        VStack(alignment: leading ? .leading : .center, spacing: 4) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(leading ? .leading : .center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
        .padding(.horizontal, InfoMetrics.hMargin)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            ForEach(stats.enumerated(), id: \.element.id) { index, stat in
                if index > 0 { Divider().frame(height: 34) }
                StatPill(value: stat.value, caption: stat.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassEffect(in: .rect(cornerRadius: 14))
        .padding(.horizontal, InfoMetrics.hMargin)
    }

    // MARK: - Tags

    private var tagsRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { TagChip(text: $0) }
            }
            .padding(.horizontal, InfoMetrics.hMargin)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Biography

    @ViewBuilder
    private var bioBlock: some View {
        let summary = (bioSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = (bioContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMore = !full.isEmpty && full.count > summary.count

        if !summary.isEmpty || !full.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("About")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(bioExpanded ? full : summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    if hasMore {
                        Button(bioExpanded ? "Read less" : "Read more") {
                            withAnimation { bioExpanded.toggle() }
                        }
                    }
                    if let lastFMURL {
                        Link("View on Last.fm", destination: lastFMURL)
                    }
                }
                .font(.callout.weight(.semibold))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .glassEffect(in: .rect(cornerRadius: 14))
            .padding(.horizontal, InfoMetrics.hMargin)
        }
    }
}

// MARK: - Entity sections

struct ArtistSimilarSection: View {
    let artists: [EpistolaresArtistInfo.SimilarArtist]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Similar Artists")
                .font(.headline)
                .padding(.horizontal, InfoMetrics.hMargin)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(artists) { artist in
                        NavigationLink(value: InfoRoute.artist(id: artist.id, name: artist.name)) {
                            SimilarArtistBubble(artist: artist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, InfoMetrics.hMargin)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AlbumTrackSection: View {
    let tracks: [EpistolaresAlbumInfo.Track]

    private var numberedTracks: [(number: Int, track: EpistolaresAlbumInfo.Track)] {
        var seen = Set<String>()
        return tracks
            .filter { seen.insert($0.name).inserted }
            .enumerated()
            .map { (number: $0.offset + 1, track: $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tracks")
                .font(.headline)

            DividedGlassCard(items: numberedTracks, id: \.track.id) { item in
                NavigationLink(value: InfoRoute.track(id: item.track.id, name: item.track.name)) {
                    AlbumTrackRow(number: item.number, name: item.track.name)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, InfoMetrics.hMargin)
    }
}

struct TrackRelatedSection: View {
    let artist: EpistolaresTrackInfo.Artist
    let album: EpistolaresTrackInfo.Album?

    var body: some View {
        VStack(spacing: 0) {
            if let album, let albumID = album.id {
                NavigationLink(value: InfoRoute.album(id: albumID, name: album.name)) {
                    TrackRelatedRow(icon: "square.stack", caption: "Album", name: album.name)
                }
                .buttonStyle(.plain)
                if artist.id != nil {
                    Divider().padding(.leading, 44)
                }
            }
            if let artistID = artist.id {
                NavigationLink(value: InfoRoute.artist(id: artistID, name: artist.name)) {
                    TrackRelatedRow(icon: "person.fill", caption: "Artist", name: artist.name)
                }
                .buttonStyle(.plain)
            }
        }
        .glassEffect(in: .rect(cornerRadius: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, InfoMetrics.hMargin)
    }
}

private struct TrackRelatedRow: View {
    let icon: String
    let caption: String
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(caption).font(.caption).foregroundStyle(.secondary)
                Text(name).font(.body).lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - Shared pieces

struct DividedGlassCard<Item, ID: Hashable, Row: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    var dividerLeadingInset: CGFloat = 44
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: id) { item in
                if item[keyPath: id] != items.first?[keyPath: id] {
                    Divider().padding(.leading, dividerLeadingInset)
                }
                row(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 14))
    }
}

struct StatPill: View {
    let value: Int
    let caption: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value.formatted(.number))
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
    }
}

// TODO: still looking weird on light backgrounds
struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .capsule)
            .overlay {
                Capsule().strokeBorder(.tint.opacity(0.4), lineWidth: 1)
            }
            .foregroundStyle(.primary)
    }
}

private struct SimilarArtistBubble: View {
    let artist: EpistolaresArtistInfo.SimilarArtist

    var body: some View {
        VStack(spacing: 8) {
            CachedAsyncImage(url: artist.cover?.url()) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.red.gradient)
                    .overlay(Image(systemName: "music.mic").foregroundStyle(.white.opacity(0.9)))
            }
            .frame(width: 76, height: 76)
            .clipShape(Circle())

            Text(artist.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 84)
        }
    }
}

private struct AlbumTrackRow: View {
    let number: Int
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            Text(name)
                .font(.body)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
