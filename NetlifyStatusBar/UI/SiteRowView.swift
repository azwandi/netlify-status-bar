// NetlifyStatusBar/UI/SiteRowView.swift
import SwiftUI

struct SiteRowView: View {
    let site: Site
    let deploy: Deploy?
    var showsCommitRef: Bool = false
    @State private var now: Date = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        // MenuBarExtra(.menu) renders each Button as a native NSMenuItem, which
        // only shows a title + icon — not an arbitrary HStack with Spacers and
        // separately-styled Text. So the whole row is composed into one title.
        Button {
            NSWorkspace.shared.open(site.adminURL)
        } label: {
            Label(
                SiteRowView.composeTitle(
                    name: site.name,
                    deploy: deploy,
                    showsCommitRef: showsCommitRef,
                    now: now
                ),
                systemImage: SiteRowView.iconName(for: deploy?.state)
            )
        }
        .onReceive(timer) { now = $0 }
    }

    // MARK: - Title composition (pure, testable)

    /// Single-line title combining name, status, commit ID, and relative time.
    static func composeTitle(name: String, deploy: Deploy?, showsCommitRef: Bool, now: Date) -> String {
        var parts: [String] = [name]
        if let deploy {
            let status = statusWord(for: deploy.state)
            if !status.isEmpty { parts.append(status) }
            if showsCommitRef, let ref = shortCommitRef(deploy.commitRef) { parts.append(ref) }
            parts.append(timeString(for: deploy, now: now))
        }
        return parts.joined(separator: "  ·  ")
    }

    static func iconName(for state: DeployState?) -> String {
        switch state {
        case .building, .enqueued, .processing: return "arrow.triangle.2.circlepath"
        case .ready:  return "checkmark.circle.fill"
        case .error:  return "xmark.circle.fill"
        default:      return "circle"
        }
    }

    /// Short 7-character form of the deployed commit SHA, or nil if unavailable.
    static func shortCommitRef(_ ref: String?) -> String? {
        guard let ref, !ref.isEmpty else { return nil }
        return String(ref.prefix(7))
    }

    private static func statusWord(for state: DeployState) -> String {
        switch state {
        case .building:   return "building"
        case .enqueued:   return "queued"
        case .processing: return "processing"
        case .ready:      return "deployed"
        case .error:      return "failed"
        case .cancelled:  return "cancelled"
        default:          return ""
        }
    }

    private static func timeString(for deploy: Deploy, now: Date) -> String {
        switch deploy.state {
        case .building, .enqueued, .processing:
            return elapsed(from: deploy.createdAt, now: now)
        case .ready:
            return relative(from: deploy.deployedAt ?? deploy.createdAt, now: now)
        default:
            return relative(from: deploy.createdAt, now: now)
        }
    }

    private static func elapsed(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    private static func relative(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
