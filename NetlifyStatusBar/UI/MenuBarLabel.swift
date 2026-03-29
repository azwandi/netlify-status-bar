// NetlifyStatusBar/UI/MenuBarLabel.swift
import SwiftUI

struct MenuBarLabel: View {
    @Environment(DeployMonitor.self) private var monitor
    @State private var tickerIndex: Int = 0
    @State private var showTicker: Bool = true
    @State private var tickerTimer: Timer? = nil

    private var activeDeploys: [(site: Site, deploy: Deploy)] {
        monitor.sites.compactMap { site in
            guard let deploy = monitor.deploys[site.id], deploy.state.isActive else { return nil }
            return (site, deploy)
        }
    }

    private var hasFailures: Bool {
        monitor.deploys.values.contains { $0.state == .error } && activeDeploys.isEmpty
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "network")
                .foregroundStyle(iconColor)

            if !activeDeploys.isEmpty {
                tickerText
            } else if hasFailures {
                failedText
            }
        }
        .onAppear { restartTicker() }
        .onChange(of: activeDeploys.count) { restartTicker() }
        .onDisappear { stopTicker() }
    }

    @ViewBuilder
    private var tickerText: some View {
        if showTicker && !activeDeploys.isEmpty {
            let item = activeDeploys[tickerIndex % activeDeploys.count]
            Text("\(item.site.name) → \(tickerLabel(item.deploy.state))…")
                .font(.system(size: 11))
                .transition(.opacity)
                .id(tickerIndex)
        }
    }

    private var failedText: some View {
        let failedSite = monitor.sites.first { monitor.deploys[$0.id]?.state == .error }
        return Text("\(failedSite?.name ?? "site") → failed")
            .font(.system(size: 11))
            .foregroundStyle(.red)
    }

    private var iconColor: Color {
        if hasFailures { return .red }
        if !activeDeploys.isEmpty { return .orange }
        return .primary
    }

    private func tickerLabel(_ state: DeployState) -> String {
        switch state {
        case .building: return "building"
        case .enqueued: return "queued"
        case .processing: return "processing"
        default: return "deploying"
        }
    }

    private func stopTicker() {
        tickerTimer?.invalidate()
        tickerTimer = nil
    }

    private func restartTicker() {
        stopTicker()
        guard !activeDeploys.isEmpty else { return }
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [self] _ in
            guard !activeDeploys.isEmpty else {
                stopTicker()
                return
            }
            withAnimation(.easeInOut(duration: 0.3)) { showTicker = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                tickerIndex += 1
                withAnimation(.easeInOut(duration: 0.3)) { showTicker = true }
            }
        }
    }
}
