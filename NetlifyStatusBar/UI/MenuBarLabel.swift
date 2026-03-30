// NetlifyStatusBar/UI/MenuBarLabel.swift
import SwiftUI

struct MenuBarLabel: View {
    @Environment(DeployMonitor.self) private var monitor
    @State private var now: Date = Date()
    @State private var pulse: Bool = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var mostRecent: (site: Site, deploy: Deploy)? {
        monitor.sites.compactMap { site -> (Site, Deploy)? in
            guard let deploy = monitor.deploys[site.id] else { return nil }
            return (site, deploy)
        }
        .max(by: { $0.1.createdAt < $1.1.createdAt })
    }

    private var isActive: Bool {
        mostRecent?.deploy.state.isActive == true
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: dotImage(color: dotNSColor))
                .opacity(isActive ? (pulse ? 0.3 : 1.0) : 1.0)
                .animation(
                    isActive ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default,
                    value: pulse
                )
                .onAppear { if isActive { pulse = true } }
                .onChange(of: isActive) { pulse = $0 }

            if let entry = mostRecent, now.timeIntervalSince(entry.deploy.createdAt) < 1800 {
                Text(labelText(site: entry.site, deploy: entry.deploy))
                    .font(.system(size: 11))
            }
        }
        .onAppear { monitor.start() }
        .onReceive(timer) { now = $0 }
    }

    private var dotNSColor: NSColor {
        guard let deploy = mostRecent?.deploy else { return .systemGray }
        switch deploy.state {
        case .building, .enqueued, .processing: return .systemOrange
        case .ready: return .systemGreen
        case .error: return .systemRed
        default: return .systemGray
        }
    }

    private func dotImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func labelText(site: Site, deploy: Deploy) -> String {
        let name = shortName(site.name)
        switch deploy.state {
        case .building:   return "\(name) · building \(elapsed(from: deploy.createdAt))"
        case .enqueued:   return "\(name) · queued \(elapsed(from: deploy.createdAt))"
        case .processing: return "\(name) · processing \(elapsed(from: deploy.createdAt))"
        case .ready:      return "\(name) · \(relative(from: deploy.deployedAt ?? deploy.createdAt))"
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
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
