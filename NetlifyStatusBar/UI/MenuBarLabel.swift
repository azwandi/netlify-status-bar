// NetlifyStatusBar/UI/MenuBarLabel.swift
import SwiftUI

struct MenuBarLabel: View {
    @Environment(DeployMonitor.self) private var monitor
    @State private var now: Date = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var mostRecent: (site: Site, deploy: Deploy)? {
        monitor.sites.compactMap { site -> (Site, Deploy)? in
            guard let deploy = monitor.deploys[site.id] else { return nil }
            return (site, deploy)
        }
        .max(by: { $0.1.createdAt < $1.1.createdAt })
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "network")
                .foregroundStyle(iconColor)

            if let entry = mostRecent {
                Text(labelText(site: entry.site, deploy: entry.deploy))
                    .font(.system(size: 11))
            }
        }
        .onAppear { monitor.start() }
        .onReceive(timer) { now = $0 }
    }

    private var iconColor: Color {
        guard let deploy = mostRecent?.deploy else { return .primary }
        switch deploy.state {
        case .building, .enqueued, .processing: return .orange
        case .error: return .red
        default: return .primary
        }
    }

    private func labelText(site: Site, deploy: Deploy) -> String {
        let name = shortName(site.name)
        switch deploy.state {
        case .building:   return "\(name) · building \(elapsed(from: deploy.createdAt))"
        case .enqueued:   return "\(name) · queued \(elapsed(from: deploy.createdAt))"
        case .processing: return "\(name) · processing \(elapsed(from: deploy.createdAt))"
        case .ready:      return "\(name) · deployed \(relative(from: deploy.deployedAt ?? deploy.createdAt))"
        case .error:      return "\(name) · failed \(relative(from: deploy.createdAt))"
        case .cancelled:  return "\(name) · cancelled \(relative(from: deploy.createdAt))"
        default:          return name
        }
    }

    private func shortName(_ name: String) -> String {
        guard name.count > 16 else { return name }
        let parts = name.split(separator: "-")
        if parts.count > 1, let first = parts.first {
            let short = String(first)
            return short.count > 16 ? String(short.prefix(14)) + "…" : short
        }
        return String(name.prefix(14)) + "…"
    }

    private func elapsed(from date: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    private func relative(from date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}
