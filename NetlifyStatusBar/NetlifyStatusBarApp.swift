// NetlifyStatusBar/NetlifyStatusBarApp.swift
import SwiftUI

@main
struct NetlifyStatusBarApp: App {
    @State private var monitor = DeployMonitor()
    @State private var updater = AppUpdater()

    var body: some Scene {
        MenuBarExtra {
            SiteListView(updater: updater)
                .environment(monitor)
        } label: {
            MenuBarLabel()
                .environment(monitor)
        }
        .menuBarExtraStyle(.menu)

        Window("Preferences", id: "preferences") {
            PreferencesView()
                .environment(monitor)
        }
        .windowResizability(.contentSize)
    }
}
