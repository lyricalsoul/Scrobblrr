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

private struct InfoDestination: View {
    let route: InfoRoute
    let manager: ScrobblerManager

    var body: some View {
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

extension View {
    func infoRouteDestination(manager: ScrobblerManager) -> some View {
        navigationDestination(for: InfoRoute.self) { route in
            InfoDestination(route: route, manager: manager)
                .sharedBackdrop(manager)
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