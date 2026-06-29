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

struct MainView : View {
    let model: MediaModel
    let manager: ScrobblerManager

    var body: some View {
        if !manager.lastFM.isAuthenticated {
            ConnectLastFMView(
                isAwaitingAuthorization: manager.lastFM.isAwaitingAuthorization,
                onSignIn: {
                    Task {
                        if let url = try? await manager.lastFM.beginAuthentication() {
                            NSWorkspace.shared.open(url)
                        }
                    }
                },
                onFinish: {
                    Task { try? await manager.lastFM.finishAuthentication() }
                }
            )
        } else if let trackInfo = model.trackInfo {
            nowPlaying(
                artwork: trackInfo.image,
                title: trackInfo.title,
                subtitle: "\(trackInfo.artist) • \(trackInfo.album ?? "Unknown Album")"
            )
        } else {
            nowPlaying(
                artwork: nil,
                title: "No playback detected",
                subtitle: "Start playing something…"
            )
        }
    }

    private func nowPlaying(artwork: NSImage?, title: String, subtitle: String) -> some View {
        // Identity for the artwork slot: changes when the track changes or when
        // late-arriving artwork appears/disappears, which drives the crossfade.
        let artworkID = "\(title)\u{1}\(artwork != nil)"

        return VStack(spacing: 0) {
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    // No artwork: show a smaller centered glyph instead of
                    // stretching the symbol across the whole artwork area.
                    Image(systemName: "music.note.slash")
                        .font(.system(size: Constants.imageDimensionOnMacOS * 0.28))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .id(artworkID)
            .transition(.opacity)
            .frame(width: Constants.imageDimensionOnMacOS, height: Constants.imageDimensionOnMacOS)
            .clipped()
            .ignoresSafeArea(.all, edges: .top)
            .animation(.smooth(duration: 0.35), value: artworkID)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title)
                    .fontWeight(.heavy)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)

                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
            }
            .padding([.horizontal, .bottom])
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
    
    MainView(model: MediaModel(manager: manager, settings: Settings()), manager: manager)
        .frame(width: Constants.imageDimensionOnMacOS, height: Constants.imageDimensionOnMacOS * 1.2)
    
}

#endif
