// NetlifyStatusBar/UI/SiteRowView.swift
import SwiftUI

struct SiteRowView: View {
    let site: Site
    let deploy: Deploy?
    @State private var now: Date = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        Button {
            NSWorkspace.shared.open(site.adminURL)
        } label: {
            HStack {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.name)
                        .font(.system(size: 13))
                    if let deploy {
                        Text(subtitleText(for: deploy))
                            .font(.system(size: 10))
                            .foregroundStyle(subtitleColor(for: deploy.state))
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
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
        .font(.system(size: 12))
    }

    private func subtitleText(for deploy: Deploy) -> String {
        switch deploy.state {
        case .building, .enqueued, .processing:
            return "⟳ \(elapsedString(from: deploy.createdAt))"
        case .ready:
            return "✓ \(relativeString(from: deploy.deployedAt ?? deploy.createdAt))"
        case .error:
            return "✗ failed · \(relativeString(from: deploy.createdAt))"
        case .cancelled:
            return "cancelled · \(relativeString(from: deploy.createdAt))"
        default:
            return relativeString(from: deploy.createdAt)
        }
    }

    private func subtitleColor(for state: DeployState) -> Color {
        switch state {
        case .building, .enqueued, .processing: return .orange
        case .ready: return .green
        case .error: return .red
        default: return .secondary
        }
    }

    private func elapsedString(from date: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    private func relativeString(from date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}
