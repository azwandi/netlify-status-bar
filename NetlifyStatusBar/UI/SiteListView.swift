// NetlifyStatusBar/UI/SiteListView.swift
import SwiftUI

struct SiteListView: View {
    @Environment(DeployMonitor.self) private var monitor
    @Environment(\.openWindow) private var openWindow
    @State private var hasToken: Bool = (try? KeychainHelper.read()) != nil
    let updater: AppUpdater

    private var sortedSites: [Site] {
        monitor.sites.sorted {
            let a = monitor.deploys[$0.id]?.createdAt ?? .distantPast
            let b = monitor.deploys[$1.id]?.createdAt ?? .distantPast
            return a > b
        }
    }

    private var activeSites: [Site] {
        sortedSites.filter { monitor.deploys[$0.id]?.state.isActive == true }
    }

    private var versionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildNumber) {
        case let (shortVersion?, buildNumber?) where shortVersion != buildNumber:
            return "Version \(shortVersion) (\(buildNumber))"
        case let (shortVersion?, _):
            return "Version \(shortVersion)"
        case let (_, buildNumber?):
            return "Build \(buildNumber)"
        default:
            return "Version unavailable"
        }
    }

    var body: some View {
        Group {
            if !hasToken {
                noTokenView
            } else if monitor.isLoading {
                loadingView
            } else {
                siteListContent
            }
        }
        .onAppear {
            monitor.start()
            monitor.wakeIfDisabled()
        }
    }

    // MARK: - States

    private var noTokenView: some View {
        Button("Set up token…") {
            openPreferences()
        }
    }

    private var loadingView: some View {
        Button("Loading sites…") {}
            .disabled(true)
    }

    @ViewBuilder
    private var siteListContent: some View {
        if let accountDisplayName = monitor.accountDisplayName {
            Text(accountDisplayName)
            Divider()
        }

        // Error banners
        if monitor.isUnauthorized {
            Button("⚠ Token invalid or expired") { openPreferences() }
        } else if monitor.lastError != nil {
            Text("⚠ Last refresh failed")
        }

        // Active deploys section
        if !activeSites.isEmpty {
            Text("Active Deploys")
            ForEach(activeSites) { site in
                SiteRowView(site: site, deploy: monitor.deploys[site.id])
            }
            Divider()
        }

        // All sites section
        Text("All Sites")
        ForEach(Array(sortedSites.prefix(15))) { site in
            SiteRowView(site: site, deploy: monitor.deploys[site.id])
        }

        Divider()

        // Footer actions
        Button("Check for Updates…") {
            Task { await updater.checkForUpdates() }
        }
        .disabled(updater.isCheckingForUpdates)
        
        Button("Refresh Now") {
            Task { await monitor.refreshNow() }
        }
        
        Button("Disable") {
            monitor.disable()
        }
        
        Button("Preferences…") {
            openPreferences()
        }
        
        Divider()
        
        Text(versionText)
        if let statusMessage = updater.statusMessage {
            Text(statusMessage)
        }
        
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Helpers

    private func openPreferences() {
        openWindow(id: "preferences")
        NSApp.activate(ignoringOtherApps: true)
    }
}
