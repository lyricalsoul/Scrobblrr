import SwiftUI
import SwiftData
import CachedAsyncImage

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
        WindowGroup {
            #if os(macOS)
            RootView(manager: manager, settings: settings)
            #else
            RootView(manager: manager, settings: settings, model: model)
                .task { await model.start() }
            #endif
        }
        .modelContainer(modelContainer)

        #if os(macOS)
        MenuBarExtra(
            "Scroblrr",
            systemImage: (manager.current != nil) ? "music.note" : "music.note.slash"
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
                Text(manager.current?.displayName ?? "No playback detected")
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

// MARK: - Sections

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case week     = "Your Week"
    case collage  = "Collage"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: "music.note"
        case .week:     "chart.bar.fill"
        case .collage:  "square.grid.3x3.fill"
        case .settings: "gear"
        }
    }

    @MainActor @ViewBuilder
    func destination(manager: ScrobblerManager, settings: Settings) -> some View {
        switch self {
        case .overview: OverviewView(manager: manager)
        case .week:     WeekView(manager: manager)
        case .collage:  CollageView(manager: manager)
        case .settings: SettingsView(settings: settings, scrobbler: manager.lastFM)
        }
    }
}

// MARK: - Root (adaptive)

struct RootView: View {
    let manager: ScrobblerManager
    let settings: Settings
    #if os(iOS)
    let model: MediaModel
    #endif

    @State private var webAuth = WebAuthCoordinator()

    var body: some View {
        #if os(iOS)
        if model.accessDenied {
            appleMusicAccessNeeded
        } else if !manager.lastFM.isAuthenticated {
            ConnectLastFMView(onSignIn: signIn)
        } else {
            TabNavigation(manager: manager, settings: settings)
        }
        #else
        if !manager.lastFM.isAuthenticated {
            ConnectLastFMView(onSignIn: signIn)
        } else {
            SidebarNavigation(manager: manager, settings: settings)
        }
        #endif
    }

    private func signIn() {
        Task { await webAuth.signIn(manager.lastFM) }
    }

    #if os(iOS)
    private var appleMusicAccessNeeded: some View {
        ContentUnavailableView {
            Label("Apple Music Access Needed", systemImage: "music.note")
        } description: {
            Text("Scroblrr needs access to Apple Music to see what you're playing and scrobble it.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    #endif
}

// MARK: Sidebar (https://www.youtube.com/watch?v=2_axj9D9W5E)

#if os(macOS)
struct SidebarNavigation: View {
    let manager: ScrobblerManager
    let settings: Settings

    @State private var selection: AppSection? = .overview

    private let sections: [AppSection] = [.overview, .week, .collage]

    var body: some View {
        NavigationSplitView {
            List(sections, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .navigationTitle("Scrobblrr")
            .scrollContentBackground(.hidden)
        } detail: {
            (selection ?? .overview).destination(manager: manager, settings: settings)
                .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .background { backdrop }
    }
    
    private var backdrop: some View {
        CachedAsyncImage(url: manager.coverImageUrl) { image in
            image
                .resizable()
                .scaledToFill()
                .blur(radius: 120, opaque: true)
                .opacity(0.4)
        } placeholder: {
            Color.clear
        }
        .clipped()
        .ignoresSafeArea()
    }
}
#endif

// MARK: TabBar

#if !os(macOS)
struct TabNavigation: View {
    let manager: ScrobblerManager
    let settings: Settings

    var body: some View {
        TabView {
            ForEach(AppSection.allCases) { section in
                NavigationStack {
                    section.destination(manager: manager, settings: settings)
                }
                .tabItem { Label(section.rawValue, systemImage: section.symbol) }
                .tag(section)
            }
        }
    }
}
#endif
