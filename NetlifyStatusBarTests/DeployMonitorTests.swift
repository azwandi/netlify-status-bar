import XCTest
@testable import NetlifyStatusBar

final class DeployMonitorTests: XCTestCase {

    func testDiffDetectsNewActiveDeployAsStarted() {
        let old: [String: Deploy] = [:]
        let new: [String: Deploy] = [
            "site1": Deploy(id: "d1", siteId: "site1", state: .building,
                            branch: "main", createdAt: Date(), deployedAt: nil)
        ]
        let transitions = DeployMonitor.diffDeploys(old: old, new: new)
        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions[0].kind, .started)
    }

    func testDiffDetectsDeploySucceeded() {
        let deploy = Deploy(id: "d1", siteId: "site1", state: .building,
                            branch: "main", createdAt: Date(), deployedAt: nil)
        let old: [String: Deploy] = ["site1": deploy]
        let newDeploy = Deploy(id: "d1", siteId: "site1", state: .ready,
                               branch: "main", createdAt: deploy.createdAt, deployedAt: Date())
        let new: [String: Deploy] = ["site1": newDeploy]
        let transitions = DeployMonitor.diffDeploys(old: old, new: new)
        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions[0].kind, .succeeded)
    }

    func testDiffDetectsDeployFailed() {
        let deploy = Deploy(id: "d1", siteId: "site1", state: .building,
                            branch: "main", createdAt: Date(), deployedAt: nil)
        let old: [String: Deploy] = ["site1": deploy]
        let newDeploy = Deploy(id: "d1", siteId: "site1", state: .error,
                               branch: "main", createdAt: deploy.createdAt, deployedAt: nil)
        let new: [String: Deploy] = ["site1": newDeploy]
        let transitions = DeployMonitor.diffDeploys(old: old, new: new)
        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions[0].kind, .failed)
    }

    func testDiffIgnoresCancelledTransition() {
        let deploy = Deploy(id: "d1", siteId: "site1", state: .building,
                            branch: "main", createdAt: Date(), deployedAt: nil)
        let old: [String: Deploy] = ["site1": deploy]
        let newDeploy = Deploy(id: "d1", siteId: "site1", state: .cancelled,
                               branch: "main", createdAt: deploy.createdAt, deployedAt: nil)
        let new: [String: Deploy] = ["site1": newDeploy]
        let transitions = DeployMonitor.diffDeploys(old: old, new: new)
        XCTAssertTrue(transitions.isEmpty)
    }

    func testAnyActiveDeployMeansActivePollRate() {
        let deploys: [String: Deploy] = [
            "s1": Deploy(id: "d1", siteId: "s1", state: .building,
                         branch: "main", createdAt: Date(), deployedAt: nil),
            "s2": Deploy(id: "d2", siteId: "s2", state: .ready,
                         branch: "main", createdAt: Date(), deployedAt: Date())
        ]
        XCTAssertTrue(DeployMonitor.hasActiveDeploys(in: deploys))
    }

    func testNoActiveDeploysMeansIdlePollRate() {
        let deploys: [String: Deploy] = [
            "s1": Deploy(id: "d1", siteId: "s1", state: .ready,
                         branch: "main", createdAt: Date(), deployedAt: Date())
        ]
        XCTAssertFalse(DeployMonitor.hasActiveDeploys(in: deploys))
    }

    func testHasNewDeploysDetectsBrandNewSiteDeploy() {
        let old: [String: Deploy] = [:]
        let new: [String: Deploy] = [
            "site1": Deploy(id: "d1", siteId: "site1", state: .ready,
                            branch: "main", createdAt: Date(), deployedAt: Date())
        ]

        XCTAssertTrue(DeployMonitor.hasNewDeploys(old: old, new: new))
    }

    func testHasNewDeploysDetectsLatestDeployIdChange() {
        let timestamp = Date()
        let old: [String: Deploy] = [
            "site1": Deploy(id: "d1", siteId: "site1", state: .ready,
                            branch: "main", createdAt: timestamp, deployedAt: timestamp)
        ]
        let new: [String: Deploy] = [
            "site1": Deploy(id: "d2", siteId: "site1", state: .building,
                            branch: "main", createdAt: timestamp.addingTimeInterval(10), deployedAt: nil)
        ]

        XCTAssertTrue(DeployMonitor.hasNewDeploys(old: old, new: new))
    }

    func testHasNewDeploysIgnoresSameDeployId() {
        let timestamp = Date()
        let oldDeploy = Deploy(id: "d1", siteId: "site1", state: .building,
                               branch: "main", createdAt: timestamp, deployedAt: nil)
        let old: [String: Deploy] = ["site1": oldDeploy]
        let new: [String: Deploy] = [
            "site1": Deploy(id: "d1", siteId: "site1", state: .ready,
                            branch: "main", createdAt: timestamp, deployedAt: timestamp.addingTimeInterval(30))
        ]

        XCTAssertFalse(DeployMonitor.hasNewDeploys(old: old, new: new))
    }
}
