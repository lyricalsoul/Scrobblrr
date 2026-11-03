//
//  InfoRoute.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/2/26.
//

import SwiftUI

enum InfoRoute: Hashable {
    case artist(id: String, name: String)
    case album(id: String, name: String)
    case track(id: String, name: String)
}

extension View {
    func infoRouteDestination(manager: ScrobblerManager) -> some View {
        navigationDestination(for: InfoRoute.self) { route in
            switch route {
            case let .artist(id, name):
                ArtistInfoView(id: id, name: name, manager: manager)
            case let .album(id, name):
                AlbumInfoView(id: id, name: name, manager: manager)
            case let .track(id, name):
                TrackInfoView(id: id, name: name, manager: manager)
            }
        }
    }

    /// wraps the view in a plain navigation link when there is somewhere to go
    @ViewBuilder
    func infoLink(_ route: InfoRoute?) -> some View {
        if let route {
            NavigationLink(value: route) { self }
                .buttonStyle(.plain)
        } else {
            self
        }
    }
}