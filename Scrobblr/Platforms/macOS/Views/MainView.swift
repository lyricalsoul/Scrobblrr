//
//  MainView.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//

#if os(macOS)

import SwiftUI
import SwiftData
import AppKit
import CachedAsyncImage

struct MainView : View {
    let manager: ScrobblerManager

    @State private var webAuth = WebAuthCoordinator()

    var body: some View {
        content
            .frame(width: Constants.imageDimensionOnMacOS)
            .background { backdrop }
            .animation(.smooth(duration: 0.4), value: coverKey)
            .hideTitlebar()
    }

    private var coverKey: String {
        let base = manager.current?.id ?? "none"
        return manager.coverImageUrl == nil ? "noart.\(base)" : "art.\(base)"
    }

    @ViewBuilder private var content: some View {
        if !manager.lastFM.isAuthenticated {
            ConnectLastFMView {
                Task { await webAuth.signIn(manager.lastFM) }
            }
        } else if let trackInfo = manager.current {
            nowPlaying(
                title: trackInfo.title,
                subtitle: trackInfo.subtitle
            )
        } else {
            nowPlaying(
                title: "No playback detected",
                subtitle: "Start playing something…"
            )
        }
    }

    @ViewBuilder private var backdrop: some View {
        if let artwork = manager.coverImageUrl {
            ZStack {
                CachedAsyncImage(url: artwork) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(1.3)
                        .blur(radius: 64, opaque: true)
                } placeholder: {
                    Image(systemName: "music.note.slash")
                }

                LinearGradient(
                    colors: [.black.opacity(0.05), .black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
            .id(coverKey)
            .transition(.opacity)
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private func nowPlaying(title: String, subtitle: String) -> some View {
        let onArtwork = manager.coverImageUrl != nil

        return VStack(spacing: 0) {
            Group {
                CachedAsyncImage(url: manager.coverImageUrl) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "music.note.slash")
                        .font(.system(size: Constants.imageDimensionOnMacOS * 0.28))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: Constants.imageDimensionOnMacOS, height: Constants.imageDimensionOnMacOS)
            .clipped()
            .id(coverKey)            // identity change drives the crossfade
            .transition(.opacity)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title)
                    .fontWeight(.heavy)
                    .foregroundStyle(onArtwork ? Color.white : Color.primary)
                    .shadow(color: .black.opacity(onArtwork ? 0.5 : 0), radius: 8, y: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)

                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(onArtwork ? Color.white.opacity(0.85) : Color.secondary)
                    .shadow(color: .black.opacity(onArtwork ? 0.4 : 0), radius: 6, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
            }
            .padding([.horizontal, .top, .bottom])
        }
        .padding([.bottom])
    }
}

#Preview {
    let container = try! ModelContainer(
        for: AutoCorrect.self, Settings.self, QueuedScrobble.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let manager = ScrobblerManager(modelContainer: container)
    
    MainView(manager: manager)
        .frame(width: Constants.imageDimensionOnMacOS, height: Constants.imageDimensionOnMacOS * 1.2)
    
}

#endif
