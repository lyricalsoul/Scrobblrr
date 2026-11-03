//
//  TrackInfoView.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/3/26.
//

import SwiftUI

struct TrackInfoView: View {
    let id: String
    let name: String
    let manager: ScrobblerManager

    var body: some View {
        InfoLoader(id: id, name: name) {
            try await Epistolares().trackInfo(id: id, username: manager.lastFM.username)
        } content: { info in
            InfoView(
                coverURL: info.track.cover?.url() ?? info.album?.cover?.url() ?? info.artist.cover?.url(),
                title: info.track.name,
                subtitle: info.artist.name,
                stats: InfoStat.counts(listeners: info.track.listeners, scrobbles: info.track.scrobbles, mine: info.track.userScrobbles?.playCount),
                tags: info.track.tags
            ) {
                TrackRelatedSection(artist: info.artist, album: info.album)
            }
        }
    }
}
