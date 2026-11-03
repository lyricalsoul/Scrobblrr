//
//  ArtistInfoView.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/2/26.
//

import SwiftUI

struct ArtistInfoView: View {
    let id: String
    let name: String
    let manager: ScrobblerManager

    var body: some View {
        InfoLoader(id: id, name: name) {
            try await Epistolares().artistInfo(id: id, username: manager.lastFM.username)
        } content: { info in
            InfoView(
                coverURL: info.cover?.url(),
                title: info.name,
                stats: InfoStat.counts(listeners: info.listeners, scrobbles: info.scrobbles, mine: info.userScrobbles?.playCount),
                tags: info.tags,
                bioSummary: info.bio?.summary,
                bioContent: info.bio?.content,
                lastFMURL: info.url.flatMap(URL.init(string:))
            ) {
                if !info.similarArtists.isEmpty {
                    ArtistSimilarSection(artists: info.similarArtists)
                }
            }
        }
    }
}
