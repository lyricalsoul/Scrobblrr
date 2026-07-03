//
//  TrackInfoView.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/3/26.
//

import SwiftUI
import os

struct TrackInfoView: View {
    let id: String
    let name: String
    let manager: ScrobblerManager

    private enum LoadState {
        case loading
        case loaded(EpistolaresTrackInfo)
        case failed
    }

    @State private var state: LoadState = .loading

    var body: some View {
        content
            .infoNavigationChrome()
            .task(id: id) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            InfoLoadFailed(name: name) { Task { await load() } }
        case let .loaded(info):
            InfoView(
                coverURL: info.track.cover?.url() ?? info.album?.cover?.url() ?? info.artist.cover?.url(),
                title: info.track.name,
                subtitle: info.artist.name,
                stats: stats(info),
                tags: info.track.tags
            ) {
                TrackRelatedSection(artist: info.artist, album: info.album)
            }
        }
    }

    private func stats(_ info: EpistolaresTrackInfo) -> [InfoStat] {
        var stats = [
            InfoStat(value: info.track.listeners, caption: "Listeners"),
            InfoStat(value: info.track.scrobbles, caption: "Scrobbles"),
        ]
        if let mine = info.track.userScrobbles?.playCount {
            stats.append(InfoStat(value: mine, caption: "Your Scrobbles"))
        }
        return stats
    }

    private func load() async {
        state = .loading
        do {
            let info = try await manager.epistolares.trackInfo(id: id, username: manager.lastFM.username)
            state = .loaded(info)
        } catch {
            Logger.epistolares.error("Couldn't fetch track \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            state = .failed
        }
    }
}
