//
//  WebAuthCoordinator.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//
//  Drives Last.fm sign-in via ASWebAuthenticationSession (iOS and macOS) and
//  returns the token captured from the `scrobblr://auth?token=…` callback.

import AuthenticationServices
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {

    /// Presents `url` and returns the `token` query item from the callback,
    /// or `nil` if the user cancelled or no token came back.
    func authenticate(url: URL, callbackScheme: String) async -> String? {
        await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, _ in
                let token = callbackURL
                    .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
                    .flatMap { $0.queryItems?.first { $0.name == "token" }?.value }
                continuation.resume(returning: token)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(iOS)
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
            #elseif os(macOS)
            return NSApplication.shared.keyWindow
                ?? NSApplication.shared.windows.first
                ?? ASPresentationAnchor()
            #endif
        }
    }
}
