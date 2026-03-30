// NetlifyStatusBar/UI/SiteListView.swift
import SwiftUI

struct SiteListView: View {
    @Environment(DeployMonitor.self) private var monitor
    @Environment(\.openWindow) private var openWindow
    @State private var hasToken: Bool = (try? KeychainHelper.read()) != nil

    private var activeSites: [Site] {
        monitor.sites.filter { monitor.deploys[$0.id]?.state.isActive == true }
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
        .frame(width: 280)
        .onAppear { monitor.start() }
    }

    // MARK: - States

    private var noTokenView: some View {
        Button("Set up token…") {
            openWindow(id: "preferences")
        }
        .padding()
    }

    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.7)
            Text("Loading sites…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var siteListContent: some View {
        // Error banners
        if monitor.isUnauthorized {
            errorRow("Token invalid or expired") { openWindow(id: "preferences") }
        } else if monitor.lastError != nil {
            Text("⚠ Last refresh failed")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }

        // Active deploys section
        if !activeSites.isEmpty {
            sectionHeader("Active Deploys")
            ForEach(activeSites) { site in
                SiteRowView(site: site, deploy: monitor.deploys[site.id])
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
            }
            Divider().padding(.vertical, 4)
        }

        // All sites section
        sectionHeader("All Sites")
        ScrollView {
            VStack(spacing: 0) {
                ForEach(monitor.sites) { site in
                    SiteRowView(site: site, deploy: monitor.deploys[site.id])
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                }
            }
        }
        .frame(maxHeight: 300)

        Divider().padding(.vertical, 4)

        // Footer actions
        Group {
            Button("Refresh Now") {
                Task { await monitor.pollDeploys() }
            }
            Button("Preferences…") {
                openWindow(id: "preferences")
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .buttonStyle(.plain)
        .font(.system(size: 13))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func errorRow(_ message: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
