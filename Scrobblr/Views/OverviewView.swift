//
//  OverviewView.swift
//  Scrobblr
//
//  Created by Renan Martins on 6/29/26.
//

import SwiftUI
import SwiftData
import CachedAsyncImage

struct OverviewView: View {
    let manager: ScrobblerManager
    @State private var correctionsTrack: GenericPlaybackInfo?

    var body: some View {
        Group {
            #if os(macOS)
            GeometryReader { geo in
                if let track = manager.displayInfo {
                    macCard(for: track, in: geo.size)
                } else {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Now Playing")
            #else
            GeometryReader { geo in
                if let track = manager.current, InfoMetrics.isWide(geo.size) {
                    wideColumns(for: track, side: InfoMetrics.macCoverSide(for: geo.size))
                } else {
                    ScrollView {
                        if let track = manager.current {
                            iosCard(for: track)
                                .frame(maxWidth: 520)
                                .frame(maxWidth: .infinity)
                        } else {
                            emptyState.padding(.top, 80)
                        }
                    }
                }
            }
            .navigationTitle("Now Playing")
            #endif
        }
        .sheet(item: $correctionsTrack) { track in
            CorrectionQuickEditSheet(track: track, manager: manager)
        }
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
        let side = InfoMetrics.macCoverSide(for: size)

        return HStack(alignment: .top, spacing: 28) {
            albumArtImage
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(radius: 18, y: 10)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    if let device = manager.displayDeviceName {
                        Label("Playing on \(device)", systemImage: "iphone")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    header(for: track)
                }
                Spacer(minLength: 16)
                statsCard(for: track)
            }
            .frame(maxWidth: .infinity, minHeight: side, maxHeight: side, alignment: .topLeading)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    #else
    private func wideColumns(for track: GenericPlaybackInfo, side: CGFloat) -> some View {
        HStack(spacing: 28) {
            albumArtImage
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(radius: 18, y: 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header(for: track, leading: true, large: true)
                    statsCard(for: track)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(height: side)
        }
        .padding(.horizontal, 28)
        .frame(maxHeight: .infinity)
    }

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

    private func header(for track: GenericPlaybackInfo, leading: Bool = InfoMetrics.titleAlignment == .leading, large: Bool = false) -> some View {
        VStack(alignment: leading ? .leading : .center, spacing: 4) {
            Text(track.title)
                .font((large ? Font.largeTitle : .title).weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)

            HStack(spacing: 6) {
                Text(track.artist)
                    .font(large ? .title2 : .title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)

                Button {
                    correctionsTrack = (track.id == manager.current?.id) ? (manager.rawCurrent ?? track) : track
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(large ? .title2 : .title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .multilineTextAlignment(leading ? .leading : .center)
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }

    // MARK: - Stats card

    private func statsCard(for track: GenericPlaybackInfo) -> some View {
        VStack(spacing: 0) {
            StatRow(
                leading: iconBadge("music.note"),
                title: track.title,
                count: manager.currentTrackScrobbles
            )
            .infoLink(manager.displayTrackInfo?.track.id.map { .track(id: $0, name: track.title) })

            if let album = track.album, !album.isEmpty {
                rowDivider
                StatRow(
                    leading: coverThumb(size: 34),
                    title: album,
                    count: manager.currentAlbumScrobbles
                )
                .infoLink(manager.displayTrackInfo?.album?.id.map { .album(id: $0, name: album) })
            }

            rowDivider
            StatRow(
                leading: artistPhoto(size: 34),
                title: track.artist,
                count: manager.currentArtistScrobbles
            )
            .infoLink(manager.displayTrackInfo?.artist.id.map { .artist(id: $0, name: track.artist) })
        }
        .glassEffect(in: .rect(cornerRadius: 14))
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 60)
    }

    // MARK: - Pieces

    private var resolvedCoverURL: URL? {
        #if os(macOS)
        manager.displayCoverURL
        #else
        manager.coverImageUrl
        #endif
    }

    /// raw cover image, callers apply the frame and clip they need
    private var albumArtImage: some View {
        CachedAsyncImage(url: resolvedCoverURL) { image in
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
        .id(resolvedCoverURL)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.4), value: resolvedCoverURL)
    }

    private func coverThumb(size: CGFloat) -> some View {
        CachedAsyncImage(url: manager.albumOnlyCoverURL) { image in
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
        CachedAsyncImage(url: manager.currentArtistCoverURL) { image in
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

#if DEBUG
#Preview {
    let track = GenericPlaybackInfo(
        title: "Underdressed at the Symphony",
        artist: "Faye Webster",
        album: "Underdressed at the Symphony",
        durationSeconds: 200,
        elapsedTimeSeconds: 42,
        isPlaying: true
    )
    let cover = URL(string: "https://m.media-amazon.com/images/I/91RKxwbtb8L._UF1000,1000_QL80_.jpg")

    OverviewView(manager: .preview(current: track, coverImageUrl: cover))
        .preferredColorScheme(.dark)
}
#endif
