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

    @State private var breathe = false
    @State private var hueShift = false

    var body: some View {
        ZStack {
            layer(scale: breathe ? 1.28 : 1.12)

            layer(scale: breathe ? 1.12 : 1.28)
                .blendMode(.colorBurn)
                .opacity(0.35)
        }
        .saturation(1.6)
        .hueRotation(.degrees(hueShift ? 14 : -14))
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeInOut(duration: 26).repeatForever(autoreverses: true)) {
                hueShift = true
            }
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
            Color.clear
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .opacity(0.5)
        .id(url)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.6), value: url)
    }
}
