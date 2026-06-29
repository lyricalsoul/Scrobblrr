//
//  MainView.swift (iOS)
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//

#if os(iOS)
import SwiftUI
import SwiftData

struct MainView: View {
    let model: MediaModel
    let manager: ScrobblerManager
    let settings: Settings

    @State private var webAuth = WebAuthCoordinator()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scroblrr")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView(settings: settings, scrobbler: manager.lastFM)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .disabled(!manager.lastFM.isAuthenticated)
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        if !model.isAuthorized {
            appleMusicAccessNeeded
        } else if !manager.lastFM.isAuthenticated {
            ConnectLastFMView(onSignIn: signIn)
        } else if let track = model.trackInfo {
            nowPlaying(
                artwork: track.artworkImage,
                title: track.title,
                subtitle: "\(track.artist) • \(track.album ?? "Unknown Album")"
            )
        } else {
            nowPlaying(
                artwork: nil,
                title: "No playback detected",
                subtitle: "Start playing something in Apple Music…"
            )
        }
    }

    // MARK: - Now playing

    private func nowPlaying(artwork: Image?, title: String, subtitle: String) -> some View {
        // Identity for the artwork slot: changes on a track change or when
        // late-arriving artwork appears, which drives the crossfade.
        let artworkID = "\(title)\u{1}\(artwork != nil)"

        return VStack(spacing: 28) {
            Group {
                if let artwork {
                    artwork
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "music.note.slash")
                        .font(.system(size: 72))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .id(artworkID)
            .transition(.opacity)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 360)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(radius: 16, y: 8)
            .animation(.smooth(duration: 0.35), value: artworkID)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title)
                    .fontWeight(.heavy)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Gates

    private var appleMusicAccessNeeded: some View {
        ContentUnavailableView {
            Label("Apple Music Access Needed", systemImage: "music.note")
        } description: {
            Text("Scroblrr needs access to Apple Music to see what you're playing and scrobble it.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Auth

    private func signIn() {
        Task {
            let url = manager.lastFM.authorizationURL(callbackScheme: "scrobblr")
            if let token = await webAuth.authenticate(url: url, callbackScheme: "scrobblr") {
                try? await manager.lastFM.completeAuthentication(token: token)
            }
        }
    }
}
#endif
