//
//  TestPlayback.swift
//  Scroblrr
//
//  Created by Renan Martins on 11/3/26.
//

import Foundation

enum TestPlayback {
    #if DEBUG
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-testPlayback")

    private static let trackLength = 45
    private static let coverBase = "https://lastfm.freetls.fastly.net/i/u/1000x1000/"

    private static let tracks: [(artist: String, title: String, album: String, cover: String)] = [
        ("Yusef Lateef", "Michelle", "Suite 16", "9251bff5f4f3121933fd04ebaaf82bae"),
        ("Ella Fitzgerald", "In A Sentimental Mood", "Ella Fitzgerald Sings the Duke Ellington Song Book", "78e39b4aad28c839678e5282ed5e04a3"),
        ("Ana Frango Elétrico", "Electric Fish", "Me Chama De Gato Que Eu Sou Sua", "849720bdfd22419153476260db67cb33"),
        ("Nara Leão", "Diz Que Fui Por Ai", "Nara (1964)", "5f4617d59085d7b8940549c53a490adc"),
        ("Pantera Blue", "Lágrima", "Lágrima", "277a2c4b4e260de841a0b2c381073c14"),
        ("John Cale", "Andalucia - Remastered 2024", "Paris 1919 (Deluxe Edition)", "765d0e2bfa88db755a80832b92f01706"),
        ("Mahmundi", "Alegria", "Para Dias Ruins", "e802e3b7a7528a3b1cedbbc6fac444e8"),
        ("Françoise Hardy", "Le temps de l'amour - Stereo Mix", "Tous les garçons et les filles", "f24e1edd580aed118fbc5ddf93a18b86"),
    ]

    @MainActor
    static func run(on manager: ScrobblerManager) async {
        var index = 0
        while !Task.isCancelled {
            let track = tracks[index % tracks.count]
            for elapsed in 0..<trackLength {
                manager.update(GenericPlaybackInfo(title: track.title, artist: track.artist, album: track.album, durationSeconds: trackLength, elapsedTimeSeconds: elapsed, isPlaying: true, coverURL: URL(string: "\(coverBase)\(track.cover).jpg")))
                try? await Task.sleep(for: .seconds(1))
            }
            index += 1
        }
    }
    #else
    static let isEnabled = false
    #endif
}
