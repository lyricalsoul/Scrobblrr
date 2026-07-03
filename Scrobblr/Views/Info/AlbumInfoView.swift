//
//  AlbumInfoView.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/2/26.
//

import SwiftUI
import os

struct AlbumInfoView: View {
    let id: String
    let name: String
    let manager: ScrobblerManager

    private enum LoadState {
        case loading
        case loaded(EpistolaresAlbumInfo)
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
                coverURL: info.cover?.url(),
                title: info.name,
                subtitle: info.artist,
                stats: stats(info),
                tags: info.tags,
                bioSummary: info.bio?.summary,
                bioContent: info.bio?.content,
                lastFMURL: info.url.flatMap(URL.init(string:))
            ) {
                if !info.tracks.isEmpty {
                    AlbumTrackSection(tracks: info.tracks)
                }
            }
        }
    }

    private func stats(_ info: EpistolaresAlbumInfo) -> [InfoStat] {
        var stats = [
            InfoStat(value: info.listeners, caption: "Listeners"),
            InfoStat(value: info.scrobbles, caption: "Scrobbles"),
        ]
        if let mine = info.userScrobbles?.playCount {
            stats.append(InfoStat(value: mine, caption: "Your Scrobbles"))
        }
        return stats
    }

    private func load() async {
        state = .loading
        do {
            let info = try await manager.epistolares.albumInfo(id: id, username: manager.lastFM.username)
            state = .loaded(info)
        } catch {
            Logger.epistolares.error("Couldn't fetch album \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            state = .failed
        }
    }
}
