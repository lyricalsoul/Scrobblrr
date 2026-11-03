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
    @State private var breathe = false
    @State private var hueShift = false

    var body: some View {
        ZStack {
            layer(scale: breathe ? 1.65 : 1.45)

            layer(scale: breathe ? 1.45 : 1.65)
                .blendMode(.colorBurn)
                .opacity(0.35)
        }
        .saturation(1.6)
        .hueRotation(.degrees(hueShift ? 14 : -14))
        .ignoresSafeArea()
        .onAppear { updateAnimation(active: scenePhase == .active) }
        .onChange(of: scenePhase) { _, newPhase in updateAnimation(active: newPhase == .active) }
    }

    private func updateAnimation(active: Bool) {
        guard active else {
            withAnimation(.none) {
                breathe = false
                hueShift = false
            }
            return
        }
        withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
            breathe = true
        }
        withAnimation(.easeInOut(duration: 26).repeatForever(autoreverses: true)) {
            hueShift = true
        }
    }

    private func layer(scale: CGFloat) -> some View {
        CachedAsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFill()
                .blur(radius: 120, opaque: true)
                .scaleEffect(scale)
        } placeholder: {
            Rectangle().fill(.quaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .opacity(0.5)
        .id(url)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.6), value: url)
    }
}
