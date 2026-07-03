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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tracks")
                .font(.headline)

            DividedGlassCard(items: tracks) { track in
                NavigationLink(value: InfoRoute.track(id: track.id, name: track.name)) {
                    AlbumTrackRow(number: track.rank + 1, name: track.name)
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

#if DEBUG
extension EpistolaresArtistInfo {
    static let sample: EpistolaresArtistInfo = {
        let json = """
        {
          "id": "AFE9DCB9-1EE4-44BF-9762-C5440BBB3076",
          "name": "Ariana Grande",
          "mbid": "f4fdbb4c-e4b7-47a0-b83b-d91bbfcfa387",
          "listeners": 4594478,
          "scrobbles": 1172235264,
          "userScrobbles": { "playCount": 3821 },
          "url": "https://www.last.fm/music/Ariana+Grande",
          "cover": {
            "template": "https://lastfm.freetls.fastly.net/i/u/{w}x{h}/fe323e8a58439d8a501284eb848da13a.jpg",
            "defaultURL": "https://lastfm.freetls.fastly.net/i/u/300x300/fe323e8a58439d8a501284eb848da13a.jpg"
          },
          "aliases": [],
          "tags": ["female vocalists", "american", "rnb", "pop", "Ariana Grande"],
          "bio": {
            "summary": "Ariana Grande-Butera, better known professionally as simply Ariana Grande, is an American singer, songwriter and actress. She is a multi-platinum, Grammy Award-winning recording artist.",
            "content": "Ariana Grande-Butera, better known professionally as simply Ariana Grande, is an American singer, songwriter and actress. She is a multi-platinum, Grammy Award-winning recording artist. Born in Boca Raton, Florida, Grande began her career in 2008 in the Broadway musical \\"13\\". She rose to prominence for her role as Cat Valentine in the Nickelodeon television series, Victorious.",
            "license": "CC BY-SA"
          },
          "similarArtists": [
            {
              "id": "5B0A4414-F829-45D4-8020-CAE8DC5B4D66",
              "name": "Madison Beer",
              "cover": { "template": "https://lastfm.freetls.fastly.net/i/u/{w}x{h}/31c2e5d8d3322dbacaa9cd2a8e54b2ff.jpg", "defaultURL": "https://lastfm.freetls.fastly.net/i/u/300x300/31c2e5d8d3322dbacaa9cd2a8e54b2ff.jpg" }
            },
            {
              "id": "C8A13103-DC2D-4CBB-A449-030035FA98B9",
              "name": "Sabrina Carpenter",
              "cover": { "template": "https://lastfm.freetls.fastly.net/i/u/{w}x{h}/21f87266d1753bff9082accbc06d7271.jpg", "defaultURL": "https://lastfm.freetls.fastly.net/i/u/300x300/21f87266d1753bff9082accbc06d7271.jpg" }
            },
            {
              "id": "449C7CEA-DC42-4150-AB69-1760A6C427FA",
              "name": "Doja Cat",
              "cover": { "template": "https://lastfm.freetls.fastly.net/i/u/{w}x{h}/dcdfe7eabba5e975d13d19304354e051.jpg", "defaultURL": "https://lastfm.freetls.fastly.net/i/u/300x300/dcdfe7eabba5e975d13d19304354e051.jpg" }
            }
          ]
        }
        """
        return try! JSONDecoder().decode(EpistolaresArtistInfo.self, from: Data(json.utf8))
    }()
}

extension EpistolaresAlbumInfo {
    static let sample: EpistolaresAlbumInfo = {
        let json = """
        {
          "id": "E01327DB-7D48-4D8B-ABD9-4733625E4E2A",
          "name": "U",
          "artist": "underscores",
          "mbid": "fa198feb-af0b-4d07-a65f-3f53fb8bff46",
          "listeners": 264200,
          "scrobbles": 11512811,
          "userScrobbles": { "playCount": 18 },
          "url": "https://www.last.fm/music/underscores/U",
          "cover": {
            "template": "https://lastfm.freetls.fastly.net/i/u/{w}x{h}/82573426631c6de14959f4753eafe666.jpg",
            "defaultURL": "https://lastfm.freetls.fastly.net/i/u/300x300/82573426631c6de14959f4753eafe666.jpg"
          },
          "tags": ["dance-pop", "2026", "hyperpop", "electro house", "electropop"],
          "bio": {
            "summary": "U is the third studio album by American musician underscores. It was released on March 20, 2026, under Mom + Pop Music and Corporate Rockmusic.",
            "content": "U is the third studio album by American musician underscores. It was released on March 20, 2026. At only 9 tracks, U features a shift back to EDM influenced sounds compared to the pop rock and folk of her previous record Wallsocket. With no features, the entire album was written, produced, mixed and mastered by underscores herself.",
            "license": "CC BY-SA"
          },
          "tracks": [
            { "id": "C129F1D7-66BD-453D-8C6C-ECBC4EF55CF8", "name": "Innuendo (I Get U)", "rank": 0 },
            { "id": "95035C68-6A44-49F4-A791-1CEA2A4B8434", "name": "Tell Me (U Want It)", "rank": 1 },
            { "id": "9AE121CC-737B-4C2B-A81D-CFE4015DDFC1", "name": "Music", "rank": 2 },
            { "id": "EE3CF749-784A-4003-B5E3-9CD17BDD19C2", "name": "Hollywood Forever", "rank": 3 },
            { "id": "5BC78C18-06AA-48D9-9945-48AB1B025208", "name": "The Peace", "rank": 4 },
            { "id": "D49A9B29-1605-4A94-81EA-D7BC540B4CDE", "name": "Innuendo (I Get It)", "rank": 5 },
            { "id": "7DB59F88-EBF0-4CD9-9998-2F81AA55E0BF", "name": "Lovefield", "rank": 6 },
            { "id": "F3C952EC-9671-40AA-AE3C-CD56771D8EBC", "name": "Do It", "rank": 7 },
            { "id": "BFCD744D-018D-4A82-A276-A9C51815C434", "name": "Bodyfeeling", "rank": 8 },
            { "id": "BB433F46-784B-467F-B37A-17D7DFE36012", "name": "Wish U Well", "rank": 9 }
          ]
        }
        """
        return try! JSONDecoder().decode(EpistolaresAlbumInfo.self, from: Data(json.utf8))
    }()
}

#Preview("Artist") {
    let artist = EpistolaresArtistInfo.sample
    NavigationStack {
        InfoView(
            coverURL: artist.cover?.url(),
            title: artist.name,
            stats: [
                InfoStat(value: artist.listeners, caption: "Listeners"),
                InfoStat(value: artist.scrobbles, caption: "Scrobbles"),
                InfoStat(value: artist.userScrobbles?.playCount ?? 0, caption: "Your Scrobbles"),
            ],
            tags: artist.tags,
            bioSummary: artist.bio?.summary,
            bioContent: artist.bio?.content,
            lastFMURL: artist.url.flatMap(URL.init(string:))
        ) {
            ArtistSimilarSection(artists: artist.similarArtists)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Album") {
    let album = EpistolaresAlbumInfo.sample
    NavigationStack {
        InfoView(
            coverURL: album.cover?.url(),
            title: album.name,
            subtitle: album.artist,
            stats: [
                InfoStat(value: album.listeners, caption: "Listeners"),
                InfoStat(value: album.scrobbles, caption: "Scrobbles"),
                InfoStat(value: album.userScrobbles?.playCount ?? 0, caption: "Your Scrobbles"),
            ],
            tags: album.tags,
            bioSummary: album.bio?.summary,
            bioContent: album.bio?.content,
            lastFMURL: album.url.flatMap(URL.init(string:))
        ) {
            AlbumTrackSection(tracks: album.tracks)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Track") {
    NavigationStack {
        InfoView(
            coverURL: URL(string: "https://lastfm.freetls.fastly.net/i/u/300x300/82573426631c6de14959f4753eafe666.jpg"),
            title: "Music",
            subtitle: "underscores",
            stats: [
                InfoStat(value: 264200, caption: "Listeners"),
                InfoStat(value: 1200000, caption: "Scrobbles"),
                InfoStat(value: 42, caption: "Your Scrobbles"),
            ],
            tags: ["hyperpop", "electropop", "dance-pop", "2026"],
            bioSummary: "\"Music\" is a single from underscores' third studio album, U.",
            bioContent: nil,
            lastFMURL: URL(string: "https://www.last.fm/music/underscores")
        ) {
            EmptyView()
        }
    }
    .preferredColorScheme(.dark)
}
#endif
