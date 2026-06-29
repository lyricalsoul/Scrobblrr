//
//  ConnectLastFMView.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//
//  Onboarding view shown until the user connects a Last.fm account. Purely
//  presentational — each platform injects the sign-in behavior (browser open
//  on macOS, ASWebAuthenticationSession on iOS).

import SwiftUI

struct ConnectLastFMView: View {
    /// Whether a sign-in has been started and is waiting for the user to finish.
    var isAwaitingAuthorization: Bool = false

    /// Begins sign-in.
    let onSignIn: () -> Void

    /// Optional second step (macOS desktop flow). When provided and awaiting,
    /// a "Finish Sign-In" button replaces the sign-in button.
    var onFinish: (() -> Void)? = nil

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

            if isAwaitingAuthorization, let onFinish {
                Button("Finish Sign-In", action: onFinish)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Sign In to Last.fm…", action: onSignIn)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(maxWidth: 400)
    }
}
