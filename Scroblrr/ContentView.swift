import SwiftUI
import MediaRemoteAdapter

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

@Observable
final class MediaModel {
    var trackInfo: TrackInfo.Payload?
    private let mediaController = MediaController()

    init() {
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            self?.trackInfo = trackInfo?.payload
        }

        // Handle listener termination
        mediaController.onListenerTerminated = { [weak self] in
            self?.trackInfo = nil
        }
        
        mediaController.startListening()
    }
    
    deinit() {
        mediaController.stopListening()
    }
}

struct ContentView: View {
    @State private var model = MediaModel()

    var body: some View {
        if model.trackInfo != nil {
            Text("\(model.trackInfo?.title), by \(model.trackInfo?.artist)")
                .padding()
        } else {
            Text("Nothing playing")
                .padding()
        }
    }
}

#Preview {
    ContentView()
}
