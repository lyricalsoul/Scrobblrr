//
//  InfoView+Previews.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/2/26.
//

import SwiftUI

#if DEBUG
extension EpistolaresArtistInfo {
    static let sample: EpistolaresArtistInfo = {
        let json = """
        {
          "id": "AFE9DCB9-1EE4-44BF-9762-C5440BBB3076",
          "name": "Ariana Grande",
          "mbid": "f4fdbb4c-e4b7-47a0-b83b-d91bbfcfa387",
          "listeners": 4594478,
          "scrobbles": 1172235264,
          "userScrobbles": { "playCount": 3821 },
          "url": "https://www.last.fm/music/Ariana+Grande",
          "cover": {
            "template": "https://lastfm.freetls.fastly.net/i/u/{w}x{h}/fe323e8a58439d8a501284eb848da13a.jpg",
            "defaultURL": "https://lastfm.freetls.fastly.net/i/u/300x300/fe323e8a58439d8a501284eb848da13a.jpg"
          },
          "aliases": [],
          "tags": ["female vocalists", "american", "rnb", "pop", "Ariana Grande"],
          "bio": {
            "summary": "Ariana Grande-Butera, better known professionally as simply Ariana Grande, is an American singer, songwriter and actress. She is a multi-platinum, Grammy Award-winning recording artist.",
            "content": "Ariana Grande-Butera, better known professionally as simply Ariana Grande, is an American singer, songwriter and actress. She is a multi-platinum, Grammy Award-winning recording artist. Born in Boca Raton, Florida, Grande began her career in 2008 in the Broadway musical \\"13\\". She rose to prominence for her role as Cat Valentine in the Nickelodeon television series, Victorious.",
            "license": "CC BY-SA"
          },
          "similarArtists": [
            {
              "id": "5B0A4414-F829-45D4-8020-CAE8DC5B4D66",
              "name": "Madison Beer",
              "cover": { "template": "https://lastfm.freetls.fastly.net/i/u/{w}x{h}/31c2e5d8d3322dbacaa9cd2a8e54b2ff.jpg", "defaultURL": "https://lastfm.freetls.fastly.net/i/u/300x300/31c2e5d8d3322dbacaa9cd2a8e54b2ff.jpg" }
            },
            {
              "id": "C8A13103-DC2D-4CBB-A449-030035FA98B9",
              "name": "Sabrina Carpenter",
              "cover": { "template": "https://lastfm.freetls.fastly.net/i/u/{w}x{h}/21f87266d1753bff9082accbc06d7271.jpg", "defaultURL": "https://lastfm.freetls.fastly.net/i/u/300x300/21f87266d1753bff9082accbc06d7271.jpg" }
            },
            {
              "id": "449C7CEA-DC42-4150-AB69-1760A6C427FA",
              "name": "Doja Cat",
              "cover": { "template": "https://lastfm.freetls.fastly.net/i/u/{w}x{h}/dcdfe7eabba5e975d13d19304354e051.jpg", "defaultURL": "https://lastfm.freetls.fastly.net/i/u/300x300/dcdfe7eabba5e975d13d19304354e051.jpg" }
            }
          ]
        }
        """
        return try! JSONDecoder().decode(EpistolaresArtistInfo.self, from: Data(json.utf8))
    }()
}

extension EpistolaresAlbumInfo {
    static let sample: EpistolaresAlbumInfo = {
        let json = """
        {
          "id": "E01327DB-7D48-4D8B-ABD9-4733625E4E2A",
          "name": "U",
          "artist": "underscores",
          "mbid": "fa198feb-af0b-4d07-a65f-3f53fb8bff46",
          "listeners": 264200,
          "scrobbles": 11512811,
          "userScrobbles": { "playCount": 18 },
          "url": "https://www.last.fm/music/underscores/U",
          "cover": {
            "template": "https://lastfm.freetls.fastly.net/i/u/{w}x{h}/82573426631c6de14959f4753eafe666.jpg",
            "defaultURL": "https://lastfm.freetls.fastly.net/i/u/300x300/82573426631c6de14959f4753eafe666.jpg"
          },
          "tags": ["dance-pop", "2026", "hyperpop", "electro house", "electropop"],
          "bio": {
            "summary": "U is the third studio album by American musician underscores. It was released on March 20, 2026, under Mom + Pop Music and Corporate Rockmusic.",
            "content": "U is the third studio album by American musician underscores. It was released on March 20, 2026. At only 9 tracks, U features a shift back to EDM influenced sounds compared to the pop rock and folk of her previous record Wallsocket. With no features, the entire album was written, produced, mixed and mastered by underscores herself.",
            "license": "CC BY-SA"
          },
          "tracks": [
            { "id": "C129F1D7-66BD-453D-8C6C-ECBC4EF55CF8", "name": "Innuendo (I Get U)", "rank": 0 },
            { "id": "95035C68-6A44-49F4-A791-1CEA2A4B8434", "name": "Tell Me (U Want It)", "rank": 1 },
            { "id": "9AE121CC-737B-4C2B-A81D-CFE4015DDFC1", "name": "Music", "rank": 2 },
            { "id": "EE3CF749-784A-4003-B5E3-9CD17BDD19C2", "name": "Hollywood Forever", "rank": 3 },
            { "id": "5BC78C18-06AA-48D9-9945-48AB1B025208", "name": "The Peace", "rank": 4 },
            { "id": "D49A9B29-1605-4A94-81EA-D7BC540B4CDE", "name": "Innuendo (I Get It)", "rank": 5 },
            { "id": "7DB59F88-EBF0-4CD9-9998-2F81AA55E0BF", "name": "Lovefield", "rank": 6 },
            { "id": "F3C952EC-9671-40AA-AE3C-CD56771D8EBC", "name": "Do It", "rank": 7 },
            { "id": "BFCD744D-018D-4A82-A276-A9C51815C434", "name": "Bodyfeeling", "rank": 8 },
            { "id": "BB433F46-784B-467F-B37A-17D7DFE36012", "name": "Wish U Well", "rank": 9 }
          ]
        }
        """
        return try! JSONDecoder().decode(EpistolaresAlbumInfo.self, from: Data(json.utf8))
    }()
}

#Preview("Artist") {
    let artist = EpistolaresArtistInfo.sample
    NavigationStack {
        InfoView(
            coverURL: artist.cover?.url(),
            title: artist.name,
            stats: [
                InfoStat(value: artist.listeners, caption: "Listeners"),
                InfoStat(value: artist.scrobbles, caption: "Scrobbles"),
                InfoStat(value: artist.userScrobbles?.playCount ?? 0, caption: "Your Scrobbles"),
            ],
            tags: artist.tags,
            bioSummary: artist.bio?.summary,
            bioContent: artist.bio?.content,
            lastFMURL: artist.url.flatMap(URL.init(string:))
        ) {
            ArtistSimilarSection(artists: artist.similarArtists)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Album") {
    let album = EpistolaresAlbumInfo.sample
    NavigationStack {
        InfoView(
            coverURL: album.cover?.url(),
            title: album.name,
            subtitle: album.artist,
            stats: [
                InfoStat(value: album.listeners, caption: "Listeners"),
                InfoStat(value: album.scrobbles, caption: "Scrobbles"),
                InfoStat(value: album.userScrobbles?.playCount ?? 0, caption: "Your Scrobbles"),
            ],
            tags: album.tags,
            bioSummary: album.bio?.summary,
            bioContent: album.bio?.content,
            lastFMURL: album.url.flatMap(URL.init(string:))
        ) {
            AlbumTrackSection(tracks: album.tracks)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Track") {
    NavigationStack {
        InfoView(
            coverURL: URL(string: "https://lastfm.freetls.fastly.net/i/u/300x300/82573426631c6de14959f4753eafe666.jpg"),
            title: "Music",
            subtitle: "underscores",
            stats: [
                InfoStat(value: 264200, caption: "Listeners"),
                InfoStat(value: 1200000, caption: "Scrobbles"),
                InfoStat(value: 42, caption: "Your Scrobbles"),
            ],
            tags: ["hyperpop", "electropop", "dance-pop", "2026"],
            bioSummary: "\"Music\" is a single from underscores' third studio album, U.",
            bioContent: nil,
            lastFMURL: URL(string: "https://www.last.fm/music/underscores")
        ) {
            EmptyView()
        }
    }
    .preferredColorScheme(.dark)
}
#endif
