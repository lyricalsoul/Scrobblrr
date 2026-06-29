//
//  WebAuthCoordinator.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//


import AuthenticationServices
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {

    /// The custom URL scheme registered for the Last.fm auth callback
    static let callbackScheme = "scrobblr"

    func signIn(_ scrobbler: LastFMScrobbler) async {
        let url = scrobbler.authorizationURL(callbackScheme: Self.callbackScheme)
        guard let token = await authenticate(url: url, callbackScheme: Self.callbackScheme) else { return }
        try? await scrobbler.completeAuthentication(token: token)
    }

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
