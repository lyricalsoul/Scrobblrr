//
//  InfoView.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/2/26.
//

import SwiftUI
import CachedAsyncImage

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

    #if os(macOS)
    static func macCoverSide(for size: CGSize) -> CGFloat {
        let ideal = min(size.width * 0.42, size.height - 56)
        return max(240, min(ideal, 480))
    }
    #endif
}

struct InfoStat: Identifiable {
    let value: Int
    let caption: String
    var id: String { caption }
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
        #if os(macOS)
        GeometryReader { geo in
            ScrollView {
                macLayout(side: InfoMetrics.macCoverSide(for: geo.size))
            }
        }
        .background { AnimatedBackdrop(url: coverURL) }
        #else
        ScrollView {
            VStack(spacing: 22) {
                cover
                VStack(spacing: 22) {
                    titleBlock
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
        .ignoresSafeArea(edges: .top)
        .background { AnimatedBackdrop(url: coverURL) }
        #endif
    }

    #if os(macOS)
    private func macLayout(side: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 28) {
            macCover(side: side)
            VStack(alignment: .leading, spacing: 22) {
                titleBlock
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
    #endif

    // MARK: - Cover

    #if os(macOS)
    private func macCover(side: CGFloat) -> some View {
        CachedAsyncImage(url: coverURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Rectangle()
                .fill(.quaternary)
                .overlay(Image(systemName: "music.note").font(.system(size: 56)).foregroundStyle(.secondary))
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(radius: 18, y: 10)
    }
    #else
    private var cover: some View {
        CachedAsyncImage(url: coverURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Rectangle()
                .fill(.quaternary)
                .overlay(Image(systemName: "music.note").font(.system(size: 56)).foregroundStyle(.secondary))
        }
        .frame(width: 1, height: 450)
        .frame(maxWidth: .infinity)
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

    private var titleBlock: some View {
        VStack(alignment: InfoMetrics.titleAlignment, spacing: 4) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(InfoMetrics.titleTextAlignment)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: InfoMetrics.titleFrameAlignment)
        .padding(.horizontal, InfoMetrics.hMargin)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { TagChip(text: $0) }
            }
            .padding(.horizontal, InfoMetrics.hMargin)
        }
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

            ScrollView(.horizontal, showsIndicators: false) {
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

            DividedGlassCard(items: numberedTracks) { item in
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

struct DividedGlassCard<Item, Row: View>: View {
    let items: [Item]
    var dividerLeadingInset: CGFloat = 44
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Divider().padding(.leading, dividerLeadingInset)
                }
                row(item)
            }
        }
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

struct InfoLoadFailed: View {
    let name: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Load", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Something went wrong fetching \(name).")
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

extension View {
    func infoNavigationChrome() -> some View {
        self
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
    }
}

