// NetlifyStatusBar/Domain/NotificationManager.swift
import UserNotifications
import Foundation

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private var firedIDs: Set<String> = []

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String, identifier: String, actionURL: URL? = nil) {
        guard !firedIDs.contains(identifier) else { return }
        firedIDs.insert(identifier)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let url = actionURL {
            content.userInfo = ["url": url.absoluteString]
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyDeployStarted(siteName: String, deployId: String) {
        notify(
            title: "\(siteName) is deploying",
            body: "A new deploy has started on \(siteName).",
            identifier: "\(deployId)-started"
        )
    }

    func notifyDeploySucceeded(siteName: String, deployId: String) {
        notify(
            title: "\(siteName) deployed successfully",
            body: "Your site is live.",
            identifier: "\(deployId)-ready"
        )
    }

    func notifyDeployFailed(siteName: String, deployId: String, adminURL: URL) {
        notify(
            title: "\(siteName) deploy failed",
            body: "Tap to view details on Netlify.",
            identifier: "\(deployId)-error",
            actionURL: adminURL
        )
    }
}
