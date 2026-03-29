// NetlifyStatusBar/Domain/DeployMonitor.swift
import Foundation
import Observation
import Network

@Observable
@MainActor
final class DeployMonitor {
    // MARK: - Published state
    var sites: [Site] = []
    var deploys: [String: Deploy] = [:]  // keyed by siteId
    var isLoading: Bool = true
    var lastError: Error? = nil
    var isUnauthorized: Bool = false

    // MARK: - Private
    private var client: NetlifyClient?
    private var deployPollTask: Task<Void, Never>?
    private var siteRefreshTask: Task<Void, Never>?
    private var pathMonitor = NWPathMonitor()
    private var isOnline: Bool = true
    private var rateLimitBackoffUntil: Date? = nil

    // MARK: - Lifecycle

    func start() {
        guard let token = try? KeychainHelper.read() else { return }
        client = NetlifyClient(token: token)
        startPathMonitor()
        Task { await refreshSites() }
        startDeployPolling()
        startSiteRefreshTimer()
    }

    func restart(withToken token: String) {
        stopAll()
        client = NetlifyClient(token: token)
        isUnauthorized = false
        lastError = nil
        isLoading = true
        pathMonitor = NWPathMonitor()
        Task { await refreshSites() }
        startDeployPolling()
        startSiteRefreshTimer()
        startPathMonitor()
    }

    private func stopAll() {
        deployPollTask?.cancel()
        siteRefreshTask?.cancel()
        pathMonitor.cancel()
    }

    // MARK: - Site refresh (startup + every 10 min)

    func refreshSites() async {
        guard let client, isOnline else { return }
        do {
            let newSites = try await client.fetchAllSites()
            sites = newSites
            lastError = nil
            isUnauthorized = false
        } catch NetlifyError.unauthorized {
            isUnauthorized = true
        } catch {
            lastError = error
        }
    }

    private func startSiteRefreshTimer() {
        siteRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                await refreshSites()
            }
        }
    }

    // MARK: - Deploy polling

    private func startDeployPolling() {
        deployPollTask = Task {
            while !Task.isCancelled {
                await pollDeploys()
                let interval: Double
                if let backoffUntil = rateLimitBackoffUntil, Date() < backoffUntil {
                    interval = 300
                } else {
                    rateLimitBackoffUntil = nil
                    interval = Self.hasActiveDeploys(in: deploys) ? 10 : 60
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func pollDeploys() async {
        guard let client, isOnline else {
            if client != nil { isLoading = false }
            return
        }
        guard !sites.isEmpty else {
            if client != nil { isLoading = false }
            return
        }
        do {
            var newDeploys: [String: Deploy] = [:]
            try await withThrowingTaskGroup(of: (String, Deploy?).self) { group in
                for site in sites {
                    group.addTask {
                        let deploy = try await client.fetchLatestDeploy(siteId: site.id)
                        return (site.id, deploy)
                    }
                }
                for try await (siteId, deploy) in group {
                    newDeploys[siteId] = deploy
                }
            }
            let transitions = Self.diffDeploys(old: deploys, new: newDeploys)
            fireNotifications(for: transitions)
            deploys = newDeploys
            lastError = nil
            isUnauthorized = false
            isLoading = false
        } catch NetlifyError.unauthorized {
            isUnauthorized = true
            isLoading = false
        } catch NetlifyError.rateLimited {
            rateLimitBackoffUntil = Date().addingTimeInterval(300)
            isLoading = false
        } catch {
            lastError = error
            isLoading = false
        }
    }

    // MARK: - Network monitoring

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isOnline = path.status == .satisfied
            }
        }
        pathMonitor.start(queue: .global(qos: .background))
    }

    // MARK: - Notification firing

    private func fireNotifications(for transitions: [DeployTransition]) {
        for t in transitions {
            guard let site = sites.first(where: { $0.id == t.siteId }) else { continue }
            switch t.kind {
            case .started:
                NotificationManager.shared.notifyDeployStarted(siteName: site.name, deployId: t.deployId)
            case .succeeded:
                NotificationManager.shared.notifyDeploySucceeded(siteName: site.name, deployId: t.deployId)
            case .failed:
                NotificationManager.shared.notifyDeployFailed(siteName: site.name, deployId: t.deployId, adminURL: site.adminURL)
            }
        }
    }

    // MARK: - Pure helpers (static — testable without instantiation)

    nonisolated static func diffDeploys(old: [String: Deploy], new: [String: Deploy]) -> [DeployTransition] {
        var transitions: [DeployTransition] = []
        for (siteId, newDeploy) in new {
            let oldDeploy = old[siteId]
            // New deploy ID appeared and it's active → started
            if oldDeploy == nil && newDeploy.state.isActive {
                transitions.append(DeployTransition(siteId: siteId, deployId: newDeploy.id, kind: .started))
                continue
            }
            guard let old = oldDeploy else { continue }
            // Different deploy ID (new deploy started)
            if old.id != newDeploy.id && newDeploy.state.isActive {
                transitions.append(DeployTransition(siteId: siteId, deployId: newDeploy.id, kind: .started))
                continue
            }
            // Same deploy, state changed
            if old.id == newDeploy.id && old.state != newDeploy.state {
                switch newDeploy.state {
                case .ready:
                    transitions.append(DeployTransition(siteId: siteId, deployId: newDeploy.id, kind: .succeeded))
                case .error:
                    transitions.append(DeployTransition(siteId: siteId, deployId: newDeploy.id, kind: .failed))
                default:
                    break
                }
            }
        }
        return transitions
    }

    nonisolated static func hasActiveDeploys(in deploys: [String: Deploy]) -> Bool {
        deploys.values.contains { $0.state.isActive }
    }
}

// MARK: - Supporting types

struct DeployTransition {
    let siteId: String
    let deployId: String
    let kind: Kind

    enum Kind: Equatable { case started, succeeded, failed }
}
