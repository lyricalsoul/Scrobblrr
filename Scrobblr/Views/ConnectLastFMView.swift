//
//  ConnectLastFMView.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//

import SwiftUI

struct ConnectLastFMView: View {
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text("Connect to Last.fm")
                .font(.title2)
                .fontWeight(.bold)

            Text("Sign in to your Last.fm account to start scrobbling the music you play.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Sign In to Last.fm…", action: onSignIn)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: 400)
    }
}
