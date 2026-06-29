//
//  LoginItemController.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//
//  Wraps SMAppService.mainApp to toggle "launch at login".

#if os(macOS)
import Foundation
import ServiceManagement
import os

@Observable
final class LoginItemController {
    private(set) var status: SMAppService.Status

    init() {
        status = SMAppService.mainApp.status
    }

    var isEnabled: Bool { status == .enabled }

    /// The user registered the item but must still approve it in System Settings.
    var requiresApproval: Bool { status == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.playback.error("Login item \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        status = SMAppService.mainApp.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
#endif
