// NetlifyStatusBar/UI/SiteRowView.swift
import SwiftUI

struct SiteRowView: View {
    let site: Site
    let deploy: Deploy?
    @State private var now: Date = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Button {
            NSWorkspace.shared.open(site.adminURL)
        } label: {
            HStack(spacing: 6) {
                statusIcon
                Text(site.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                if let deploy {
                    Text(statusLabel(for: deploy.state))
                        .font(.system(size: 11))
                        .foregroundStyle(stateColor(for: deploy.state))
                }
                Spacer(minLength: 8)
                if let deploy {
                    Text(timeString(for: deploy))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .onReceive(timer) { now = $0 }
    }

    private var statusIcon: some View {
        Group {
            switch deploy?.state {
            case .building, .enqueued, .processing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            default:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
    }

    private func statusLabel(for state: DeployState) -> String {
        switch state {
        case .building:   return "· building"
        case .enqueued:   return "· queued"
        case .processing: return "· processing"
        case .ready:      return "· deployed"
        case .error:      return "· failed"
        case .cancelled:  return "· cancelled"
        default:          return ""
        }
    }

    private func stateColor(for state: DeployState) -> Color {
        switch state {
        case .building, .enqueued, .processing: return .orange
        case .ready: return .green
        case .error: return .red
        default: return .secondary
        }
    }

    private func timeString(for deploy: Deploy) -> String {
        switch deploy.state {
        case .building, .enqueued, .processing:
            return elapsed(from: deploy.createdAt)
        case .ready:
            return relative(from: deploy.deployedAt ?? deploy.createdAt)
        default:
            return relative(from: deploy.createdAt)
        }
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
