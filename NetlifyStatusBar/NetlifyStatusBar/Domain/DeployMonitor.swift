// NetlifyStatusBar/Domain/DeployMonitor.swift
import Foundation
import Observation
import Network

@Observable
@MainActor
final class DeployMonitor {
    enum PollingState: Equatable {
        case active
        case idle
        case disabled
    }

    private static let activeDuration: TimeInterval = 600
    private static let idleDuration: TimeInterval = 1800

    // MARK: - Published state
    var sites: [Site] = []
    var deploys: [String: Deploy] = [:]  // keyed by siteId
    var isLoading: Bool = true
    var lastError: Error? = nil
    var isUnauthorized: Bool = false
    var pollingState: PollingState = .active
    var accountDisplayName: String? = nil

    // MARK: - Private
    private var client: NetlifyClient?
    private var deployPollTask: Task<Void, Never>?
    private var siteRefreshTask: Task<Void, Never>?
    private var pathMonitor = NWPathMonitor()
    private var isOnline: Bool = true
    private var rateLimitBackoffUntil: Date? = nil
    private var hasStarted: Bool = false
    private var activeUntil: Date?
    private var idleUntil: Date?

    // MARK: - Lifecycle

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard let token = try? KeychainHelper.read() else {
            isLoading = false
            return
        }
        client = NetlifyClient(token: token)
        enterActiveState()
        startPathMonitor()
        startDeployPolling()
        startSiteRefreshTimer()
    }

    func restart(withToken token: String) {
        stopAll()
        hasStarted = true
        client = NetlifyClient(token: token)
        isUnauthorized = false
        lastError = nil
        isLoading = true
        enterActiveState()
        pathMonitor = NWPathMonitor()
        startDeployPolling()
        startSiteRefreshTimer()
        startPathMonitor()
    }

    private func stopAll() {
        deployPollTask?.cancel()
        siteRefreshTask?.cancel()
        pathMonitor.cancel()
    }

    func wakeIfDisabled() {
        guard pollingState == .disabled else { return }
        enterActiveState()
        isLoading = true
    }

    func refreshNow() async {
        enterActiveState()
        isLoading = true
        await refreshIdentity()
        await refreshSites()
        let detectedNewDeploy = await pollDeploys()
        updatePollingState(afterDetectingNewDeploy: detectedNewDeploy)
    }

    func disable() {
        enterDisabledState()
        isLoading = false
    }

    // MARK: - Site refresh (startup + every 10 min)

    func refreshIdentity() async {
        guard let client else { return }
        do {
            async let user = client.fetchCurrentUser()
            async let accounts = client.fetchAccounts()

            let (currentUser, availableAccounts) = try await (user, accounts)
            accountDisplayName = Self.accountLabel(user: currentUser, accounts: availableAccounts)
            lastError = nil
            isUnauthorized = false
        } catch NetlifyError.unauthorized {
            isUnauthorized = true
        } catch {
            lastError = error
        }
    }

    func refreshSites() async {
        guard pollingState != .disabled, let client, isOnline else { return }
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
                do {
                    try await Task.sleep(for: .seconds(600))
                } catch {
                    return
                }
                await refreshIdentity()
                await refreshSites()
            }
        }
    }

    // MARK: - Deploy polling

    private func startDeployPolling() {
        deployPollTask = Task {
            await refreshIdentity()
            await refreshSites()
            while !Task.isCancelled {
                if pollingState == .disabled {
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        return
                    }
                    continue
                }

                let detectedNewDeploy = await pollDeploys()
                updatePollingState(afterDetectingNewDeploy: detectedNewDeploy)

                let interval: Double
                if let backoffUntil = rateLimitBackoffUntil, Date() < backoffUntil {
                    interval = 300
                } else {
                    rateLimitBackoffUntil = nil
                    interval = pollingState == .active ? 5 : 60
                }
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return  // Task was cancelled
                }
            }
        }
    }

    @discardableResult
    func pollDeploys() async -> Bool {
        guard let client, isOnline else {
            if client != nil { isLoading = false }
            return false
        }
        guard !sites.isEmpty else {
            isLoading = false
            return false
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
            let detectedNewDeploy = Self.hasNewDeploys(old: deploys, new: newDeploys)
            let transitions = Self.diffDeploys(old: deploys, new: newDeploys)
            fireNotifications(for: transitions)
            deploys = newDeploys
            lastError = nil
            isUnauthorized = false
            isLoading = false
            return detectedNewDeploy
        } catch NetlifyError.unauthorized {
            isUnauthorized = true
            isLoading = false
            return false
        } catch NetlifyError.rateLimited {
            rateLimitBackoffUntil = Date().addingTimeInterval(300)
            isLoading = false
            return false
        } catch {
            lastError = error
            isLoading = false
            return false
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

    private func enterActiveState(now: Date = Date()) {
        pollingState = .active
        activeUntil = now.addingTimeInterval(Self.activeDuration)
        idleUntil = nil
    }

    private func enterIdleState(now: Date = Date()) {
        pollingState = .idle
        activeUntil = nil
        idleUntil = now.addingTimeInterval(Self.idleDuration)
    }

    private func enterDisabledState() {
        pollingState = .disabled
        activeUntil = nil
        idleUntil = nil
    }

    private func updatePollingState(afterDetectingNewDeploy detectedNewDeploy: Bool, now: Date = Date()) {
        switch pollingState {
        case .active:
            if detectedNewDeploy {
                activeUntil = now.addingTimeInterval(Self.activeDuration)
            } else if let activeUntil, now >= activeUntil {
                enterIdleState(now: now)
            }
        case .idle:
            if detectedNewDeploy {
                enterActiveState(now: now)
            } else if let idleUntil, now >= idleUntil {
                enterDisabledState()
            }
        case .disabled:
            break
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

    nonisolated static func hasNewDeploys(old: [String: Deploy], new: [String: Deploy]) -> Bool {
        new.contains { siteId, newDeploy in
            guard let oldDeploy = old[siteId] else { return true }
            return oldDeploy.id != newDeploy.id
        }
    }

    nonisolated static func accountLabel(user: NetlifyUser, accounts: [NetlifyAccount]) -> String {
        let owner = user.fullName ?? user.email
        let accountNames = Array(
            NSOrderedSet(array: accounts.map { $0.name }.filter { !$0.isEmpty })
        ) as? [String] ?? []

        guard !accountNames.isEmpty else { return owner }
        if accountNames.count == 1 {
            return "\(owner) • \(accountNames[0])"
        }

        let visibleAccounts = accountNames.prefix(2).joined(separator: ", ")
        let extraCount = accountNames.count - 2
        if extraCount > 0 {
            return "\(owner) • \(visibleAccounts) +\(extraCount)"
        }
        return "\(owner) • \(visibleAccounts)"
    }
}

// MARK: - Supporting types

struct DeployTransition {
    let siteId: String
    let deployId: String
    let kind: Kind

    enum Kind: Equatable { case started, succeeded, failed }
}
