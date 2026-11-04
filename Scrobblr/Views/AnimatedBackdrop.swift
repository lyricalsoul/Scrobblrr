//
//  AnimatedBackdrop.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/2/26.
//

import SwiftUI
import CachedAsyncImage

struct AnimatedBackdrop: View {
    let url: URL?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: scenePhase != .active)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let breathe = (sin(time * 2 * .pi / 36) + 1) / 2
            let hueShift = sin(time * 2 * .pi / 52) * 14

            GeometryReader { geo in
                ZStack {
                    layer(scale: 1.45 + 0.2 * breathe)

                    layer(scale: 1.65 - 0.2 * breathe)
                        .blendMode(.colorBurn)
                        .opacity(0.35)
                }
                .animation(nil, value: geo.size)
            }
            .saturation(1.6)
            .hueRotation(.degrees(hueShift))
        }
        .ignoresSafeArea()
    }

    private func layer(scale: CGFloat) -> some View {
        Color.clear.overlay {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 120, opaque: true)
                    .drawingGroup()
                    .scaleEffect(scale)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
        }
        .clipped()
        .opacity(0.5)
        .id(url)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.6), value: url)
    }
}

@Observable @MainActor
final class BackdropState {
    private(set) var override: URL?
    @ObservationIgnored private var owner: UUID?

    func set(_ url: URL?, by owner: UUID) {
        self.owner = owner
        override = url
    }

    func clear(by owner: UUID) {
        guard self.owner == owner else { return }
        override = nil
    }
}

private struct BackdropModifier: ViewModifier {
    let url: URL?
    @Environment(BackdropState.self) private var state
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { state.set(url, by: id) }
            .onChange(of: url) { _, new in state.set(new, by: id) }
            .onDisappear { state.clear(by: id) }
    }
}

extension View {
    func backdrop(_ url: URL?) -> some View { modifier(BackdropModifier(url: url)) }
}

private struct SharedBackdropModifier: ViewModifier {
    let manager: ScrobblerManager
    @Environment(BackdropState.self) private var state

    func body(content: Content) -> some View {
        #if os(iOS)
        content.containerBackground(for: .navigation) {
            AnimatedBackdrop(url: state.override ?? manager.coverImageUrl)
        }
        #else
        content
        #endif
    }
}

extension View {
    /// iOS: gives a navigation destination the shared backdrop, macOS draws it once at the root instead
    func sharedBackdrop(_ manager: ScrobblerManager) -> some View { modifier(SharedBackdropModifier(manager: manager)) }
}
