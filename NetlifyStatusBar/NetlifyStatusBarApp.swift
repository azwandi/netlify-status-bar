// NetlifyStatusBar/NetlifyStatusBarApp.swift
import SwiftUI

@main
struct NetlifyStatusBarApp: App {
    @State private var monitor = DeployMonitor()

    var body: some Scene {
        MenuBarExtra {
            SiteListView()
                .environment(monitor)
        } label: {
            MenuBarLabel()
                .environment(monitor)
        }
        .menuBarExtraStyle(.window)

        Window("Preferences", id: "preferences") {
            PreferencesView()
                .environment(monitor)
        }
        .windowResizability(.contentSize)
    }
}
