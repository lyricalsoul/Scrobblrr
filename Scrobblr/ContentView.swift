import SwiftUI
import SwiftData

@main struct MyApp: App {
    @State private var manager: ScrobblerManager
    @State private var model: MediaModel
    @State private var webAuth = WebAuthCoordinator()
    private let modelContainer: ModelContainer
    private let settings: Settings

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: AutoCorrect.self, Settings.self, QueuedScrobble.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        let settings = Settings.shared(in: container.mainContext)
        let manager = ScrobblerManager(modelContainer: container)
        modelContainer = container
        self.settings = settings
        _manager = State(initialValue: manager)
        _model = State(initialValue: MediaModel(manager: manager, settings: settings))
    }

    var body: some Scene {
        WindowGroup(id: "SquarePlayerWindow") {
            #if os(macOS)
            MainView(model: model, manager: manager)
                .onOpenURL { url in
                    print(url)
                }
            #else
            MainView(model: model, manager: manager, settings: settings)
                .task { await model.start() }
            #endif
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        //.defaultSize(width: CGFloat(Constants.imageDimensionOnMacOS), height: CGFloat(Constants.imageDimensionOnMacOS))
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        #endif

        #if os(macOS)
        MenuBarExtra(
            "Scroblrr",
            systemImage: (model.trackInfo != nil) ? "music.note" : "music.note.slash"
        ) {
            let scrobbler = manager.lastFM
            if scrobbler.isAuthenticated {
                Text("Signed in as \(scrobbler.username ?? "—")")
            } else {
                Button("Sign In to Last.fm…") {
                    Task { await webAuth.signIn(scrobbler) }
                }
            }
            Divider()
            
            if settings.showNowPlayingInMenu {
                Text(model.trackInfo?.displayName ?? "No playback detected")
                Divider()
            }
            

            SettingsLink {
                Text("Settings…")
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }

        SwiftUI.Settings {
            SettingsView(settings: settings, scrobbler: manager.lastFM)
                .modelContainer(modelContainer)
        }
        #endif
    }
}
