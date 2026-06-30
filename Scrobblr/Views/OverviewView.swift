//
//  OverviewView.swift
//  Scrobblr
//
//  Created by Renan Martins on 6/29/26.
//

import SwiftUI
import SwiftData
import CachedAsyncImage
import LastFM

struct OverviewView: View {
    let manager: ScrobblerManager

    var body: some View {
        #if os(macOS)
        GeometryReader { geo in
            if let track = manager.current {
                macCard(for: track, in: geo.size)
            } else {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Now Playing")
        #else
        ScrollView {
            if let track = manager.current {
                iosCard(for: track)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
            } else {
                emptyState.padding(.top, 80)
            }
        }
        .background { backdrop }
        .navigationTitle("Now Playing")
        #endif
    }


    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing Playing",
            systemImage: "music.note",
            description: Text("Start playing something to see it here.")
        )
    }

    // MARK: - Cards

    #if os(macOS)
    private func macCard(for track: GenericPlaybackInfo, in size: CGSize) -> some View {
        let ideal = min(size.width * 0.42, size.height - 56)
        let side = max(240, min(ideal, 480))

        return HStack(alignment: .top, spacing: 28) {
            albumArtImage
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(radius: 18, y: 10)

            VStack(alignment: .leading, spacing: 16) {
                header(for: track)
                Spacer(minLength: 16)
                statsCard(for: track)
            }
            .frame(maxWidth: .infinity, minHeight: side, maxHeight: side, alignment: .topLeading)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    #else
    private func iosCard(for track: GenericPlaybackInfo) -> some View {
        VStack(spacing: 24) {
            albumArtImage
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 360)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(radius: 16, y: 10)

            header(for: track)
            statsCard(for: track)
        }
        .padding(24)
    }
    #endif

    // MARK: - Header (title + artist)

    private func header(for track: GenericPlaybackInfo) -> some View {
        VStack(alignment: Self.hAlign, spacing: 4) {
            Text(track.title)
                .font(.title.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)

            Text(track.artist)
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .multilineTextAlignment(Self.textAlign)
        .frame(maxWidth: .infinity, alignment: Self.frameAlignment)
    }

    // MARK: - Stats card

    private func statsCard(for track: GenericPlaybackInfo) -> some View {
        VStack(spacing: 0) {
            StatRow(
                leading: iconBadge("music.note"),
                title: track.title,
                count: manager.currentTrackInfo?.userPlaycount
            )

            if let album = track.album, !album.isEmpty {
                rowDivider
                StatRow(
                    leading: coverThumb(size: 34),
                    title: album,
                    count: manager.currentAlbumInfo?.userPlaycount
                )
            }

            rowDivider
            StatRow(
                leading: artistPhoto(size: 34),
                title: track.artist,
                count: manager.currentArtistInfo?.stats.userPlaycount
            )
        }
        .glassEffect(in: .rect(cornerRadius: 14))
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 60)
    }

    // MARK: - Pieces

    /// The raw, unsized cover image; callers apply the frame/clip they need
    private var albumArtImage: some View {
        CachedAsyncImage(url: manager.coverImageUrl) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(.quaternary)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                )
        }
    }

    /// Small album cover used as the album stat row's leading thumbnail
    private func coverThumb(size: CGFloat) -> some View {
        CachedAsyncImage(url: manager.coverImageUrl) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.tint.opacity(0.15))
                .overlay(Image(systemName: "square.stack").foregroundStyle(.tint))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func iconBadge(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.tint.opacity(0.15))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
            )
            .frame(width: 34, height: 34)
    }

    private func artistPhoto(size: CGFloat) -> some View {
        let images = manager.currentArtistInfo?.image
        let url = images?.mega ?? images?.extraLarge ?? images?.large

        return CachedAsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Circle()
                .fill(.quaternary)
                .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    // MARK: - Layout constants

    #if os(macOS)
    static let hAlign = HorizontalAlignment.leading
    static let textAlign = TextAlignment.leading
    static let frameAlignment = Alignment.leading
    #else
    static let hAlign = HorizontalAlignment.center
    static let textAlign = TextAlignment.center
    static let frameAlignment = Alignment.center
    #endif
}

// MARK: - Stat row

private struct StatRow<Leading: View>: View {
    let leading: Leading
    let title: String
    let count: Int?

    var body: some View {
        HStack(spacing: 12) {
            leading
            Text(title)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 0) {
                Text(count.map(String.init) ?? "—")
                    .font(.body.weight(.semibold).monospacedDigit())
                Text("scrobbles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: AutoCorrect.self, Settings.self, QueuedScrobble.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let settings = Settings.shared(in: container.mainContext)
    let manager = ScrobblerManager(modelContainer: container)

    //RootView(manager: manager, settings: settings)
}
