//
//  SparkleUpdater.swift
//  Scroblrr
//
//  Created by Renan Martins on 7/11/26.
//

#if os(macOS)
import Combine
import Sparkle

@MainActor
@Observable
final class SparkleUpdater {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private(set) var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    @ObservationIgnored private var cancellable: AnyCancellable?

    init() {
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
#endif
