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
        VStack(alignment: .leading, spacing: 0) {
            if !hasToken {
                noTokenView
            } else if monitor.isLoading {
                loadingView
            } else {
                siteListContent
            }
        }
        .frame(width: 300)
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
        .padding()
    }

    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.7)
            Text("Loading sites…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var siteListContent: some View {
        if let accountDisplayName = monitor.accountDisplayName {
            VStack(alignment: .leading, spacing: 2) {
                Text("NETLIFY ACCOUNT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(accountDisplayName)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().padding(.bottom, 4)
        }

        // Error banners
        if monitor.isUnauthorized {
            errorRow("Token invalid or expired") { openPreferences() }
        } else if monitor.lastError != nil {
            Text("⚠ Last refresh failed")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }

        // Active deploys section
        if !activeSites.isEmpty {
            sectionHeader("Active Deploys")
            ForEach(activeSites) { site in
                SiteRowView(site: site, deploy: monitor.deploys[site.id])
                    .padding(.horizontal, 14)
                    .padding(.vertical, 3)
            }
            Divider().padding(.vertical, 4)
        }

        // All sites section
        sectionHeader("All Sites")
        ForEach(Array(sortedSites.prefix(15))) { site in
            SiteRowView(site: site, deploy: monitor.deploys[site.id])
                .padding(.horizontal, 14)
                .padding(.vertical, 3)
        }

        Divider().padding(.vertical, 4)

        // Footer actions
        footerButton("Check for Updates…") {
            Task { await updater.checkForUpdates() }
        }
        .disabled(updater.isCheckingForUpdates)
        footerButton("Refresh Now") {
            Task { await monitor.refreshNow() }
        }
        footerButton("Disable") {
            monitor.disable()
        }
        footerButton("Preferences…") {
            openPreferences()
        }
        Divider().padding(.vertical, 2)
        Text(versionText)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, updater.statusMessage == nil ? 2 : 0)
        if let statusMessage = updater.statusMessage {
            Text(statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 2)
        }
        footerButton("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    private func openPreferences() {
        openWindow(id: "preferences")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }

    private func errorRow(_ message: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 13))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func footerButton(_ label: String, action: @escaping () -> Void) -> some View {
        FooterButton(label: label, action: action)
    }
}

private struct FooterButton: View {
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
                )
                .foregroundStyle(isHovered ? Color(nsColor: .selectedMenuItemTextColor) : .primary)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .padding(.horizontal, 6)
        .onHover { isHovered = $0 }
    }
}
