import SwiftUI

// MARK: - Sections

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Now Playing"
    case week     = "Your Week"
    case collage  = "Collage"
    case settings = "Settings"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .overview: "Now Playing"
        case .week:     "Your Week"
        case .collage:  "Collage"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "music.note"
        case .week:     "chart.bar.fill"
        case .collage:  "square.grid.3x3.fill"
        case .settings: "gear"
        }
    }

    #if os(macOS)
    @MainActor @ViewBuilder
    func destination(manager: ScrobblerManager, settings: Settings, updater: SparkleUpdater) -> some View {
        switch self {
        case .overview: OverviewView(manager: manager)
        case .week:     WeekView(manager: manager)
        case .collage:  CollageView(manager: manager)
        case .settings: SettingsView(settings: settings, scrobbler: manager.lastFM, updater: updater, onSignOut: { manager.signOut() })
        }
    }
    #else
    @MainActor @ViewBuilder
    func destination(manager: ScrobblerManager, settings: Settings) -> some View {
        switch self {
        case .overview: OverviewView(manager: manager)
        case .week:     WeekView(manager: manager)
        case .collage:  CollageView(manager: manager)
        case .settings: SettingsView(settings: settings, scrobbler: manager.lastFM, onSignOut: { manager.signOut() })
        }
    }
    #endif
}

// MARK: - Root (adaptive)

struct RootView: View {
    let manager: ScrobblerManager
    let settings: Settings
    #if os(iOS)
    let model: MediaModel
    #else
    let updater: SparkleUpdater
    #endif

    @State private var webAuth = WebAuthCoordinator()
    @Environment(\.openURL) private var openURL

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
        Group {
            if !manager.lastFM.isAuthenticated {
                ConnectLastFMView(onSignIn: signIn)
            } else {
                SidebarNavigation(manager: manager, settings: settings, updater: updater)
            }
        }
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
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
                    openURL(url)
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
    let updater: SparkleUpdater

    @State private var selection: AppSection? = .overview
    @State private var backdrop = BackdropState()

    private let sections: [AppSection] = [.overview, .week, .collage]

    var body: some View {
        NavigationSplitView {
            List(sections, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .navigationTitle("Scrobblrr")
            .scrollContentBackground(.hidden)
        } detail: {
            NavigationStack {
                (selection ?? .overview).destination(manager: manager, settings: settings, updater: updater)
                    .infoRouteDestination(manager: manager)
                    .toolbarBackground(.hidden, for: .windowToolbar)
            }
        }
        .background { AnimatedBackdrop(url: backdrop.override ?? manager.displayCoverURL) }
        .environment(backdrop)
    }
}
#endif

// MARK: TabBar

#if !os(macOS)
struct TabNavigation: View {
    let manager: ScrobblerManager
    let settings: Settings

    @State private var backdrop = BackdropState()

    var body: some View {
        TabView {
            ForEach(AppSection.allCases) { section in
                Tab(section.title, systemImage: section.symbol) {
                    NavigationStack {
                        section.destination(manager: manager, settings: settings)
                            .sharedBackdrop(manager)
                            .infoRouteDestination(manager: manager)
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(backdrop)
    }
}
#endif
