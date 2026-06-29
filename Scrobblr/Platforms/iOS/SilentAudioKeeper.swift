//
//  SilentAudioKeeper.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//
//

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

        // after interruption, keep playing empty audio
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleInterruption(note) }
        })

        // rebuild media services after timeout or reset
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Logger.playback.error("Audio media services were reset, rebuilding keeper")
                self?.player = nil
                self?.configureAndPlay()
            }
        })
    }

    func ensurePlaying() {
        guard player?.isPlaying != true else { return }
        Logger.playback.info("Silent keeper not playing, restarting")
        configureAndPlay()
    }

    private func configureAndPlay() {
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "mp3") else {
            assertionFailure("silence.mp3 not found in bundle")
            Logger.playback.error("silence.mp3 not found in bundle?")
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
