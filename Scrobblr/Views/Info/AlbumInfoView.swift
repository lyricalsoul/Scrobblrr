//
//  AlbumInfoView.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/2/26.
//

import SwiftUI

struct AlbumInfoView: View {
    let id: String
    let name: String
    let manager: ScrobblerManager

    var body: some View {
        InfoLoader(id: id, name: name) {
            try await Epistolares().albumInfo(id: id, username: manager.lastFM.username)
        } content: { info in
            InfoView(
                coverURL: info.cover?.url(),
                title: info.name,
                subtitle: info.artist,
                stats: InfoStat.counts(listeners: info.listeners, scrobbles: info.scrobbles, mine: info.userScrobbles?.playCount),
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
}
