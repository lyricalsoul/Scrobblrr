//
//  SilentAudioKeeper.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//
//  Keeps an always-active, silent audio session so iOS doesn't suspend the app
//  in the background — letting it keep observing playback and posting scrobbles.
//  Mixes with other audio so it never interrupts the music being played.

#if os(iOS)
import AVFoundation
import os

@MainActor
final class SilentAudioKeeper {
    private var player: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []

    func start() {
        configureAndPlay()

        let center = NotificationCenter.default

        // After an interruption (e.g. a phone call) the session is deactivated;
        // reactivate and resume the silence once it ends.
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleInterruption(note) }
        })

        // The media server can reset after long runtime, invalidating both the
        // session and the player. Rebuild everything from scratch when it does —
        // otherwise the silence stops and the app eventually gets suspended.
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Logger.playback.error("Audio media services were reset — rebuilding silent keeper")
                self?.player = nil
                self?.configureAndPlay()
            }
        })
    }

    /// Re-asserts the session and silence. Safe to call repeatedly (e.g. from a
    /// heartbeat or on returning to the foreground); only acts if playback stalled.
    func ensurePlaying() {
        guard player?.isPlaying != true else { return }
        Logger.playback.info("Silent keeper not playing — re-asserting")
        configureAndPlay()
    }

    private func configureAndPlay() {
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "mp3") else {
            assertionFailure("silence.mp3 not found in bundle")
            Logger.playback.error("silence.mp3 not found in bundle")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            Logger.playback.error("Audio session setup failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        if player == nil {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1   // loop forever
            player?.volume = 0
        }
        player?.play()
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw),
              type == .ended else { return }

        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
#endif
