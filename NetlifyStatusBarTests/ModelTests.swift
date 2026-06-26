import XCTest
@testable import NetlifyStatusBar

final class ModelTests: XCTestCase {
    func testDeployStateIsActiveForBuildingStates() {
        XCTAssertTrue(DeployState.building.isActive)
        XCTAssertTrue(DeployState.enqueued.isActive)
        XCTAssertTrue(DeployState.processing.isActive)
    }

    func testDeployStateIsNotActiveForTerminalStates() {
        XCTAssertFalse(DeployState.ready.isActive)
        XCTAssertFalse(DeployState.error.isActive)
        XCTAssertFalse(DeployState.cancelled.isActive)
        XCTAssertFalse(DeployState.unknown.isActive)
    }

    func testSiteAdminURLUsesNameNotID() {
        let site = Site(id: "abc123", name: "my-portfolio", adminURL: URL(string: "https://app.netlify.com/sites/my-portfolio")!)
        XCTAssertTrue(site.adminURL.absoluteString.contains("my-portfolio"))
        XCTAssertFalse(site.adminURL.absoluteString.contains("abc123"))
    }

    // MARK: - SiteRowView title composition

    private let fixedNow = Date(timeIntervalSince1970: 1_000_000)

    func testRowTitleIncludesShortCommitInAllSites() {
        let deploy = Deploy(
            id: "d1", siteId: "s1", state: .ready, branch: "main",
            createdAt: fixedNow.addingTimeInterval(-120),
            deployedAt: fixedNow.addingTimeInterval(-120),
            commitRef: "882f5cc68f15a191fb34203db30aed41ac1e848e"
        )
        let title = SiteRowView.composeTitle(name: "my-site", deploy: deploy, showsCommitRef: true, now: fixedNow)
        XCTAssertTrue(title.contains("my-site"), title)
        XCTAssertTrue(title.contains("deployed"), title)
        XCTAssertTrue(title.contains("882f5cc"), title)      // short SHA present
        XCTAssertFalse(title.contains("882f5cc6"), title)    // truncated to 7 chars
        XCTAssertTrue(title.contains("2m ago"), title)
    }

    func testRowTitleOmitsCommitOutsideAllSites() {
        let deploy = Deploy(
            id: "d1", siteId: "s1", state: .building, branch: "main",
            createdAt: fixedNow.addingTimeInterval(-30),
            deployedAt: nil,
            commitRef: "882f5cc68f15a191"
        )
        let title = SiteRowView.composeTitle(name: "my-site", deploy: deploy, showsCommitRef: false, now: fixedNow)
        XCTAssertFalse(title.contains("882f5cc"), title)
        XCTAssertTrue(title.contains("building"), title)
    }

    func testRowTitleHandlesMissingCommit() {
        let deploy = Deploy(
            id: "d1", siteId: "s1", state: .ready, branch: "main",
            createdAt: fixedNow.addingTimeInterval(-3600),
            deployedAt: fixedNow.addingTimeInterval(-3600),
            commitRef: nil
        )
        let title = SiteRowView.composeTitle(name: "my-site", deploy: deploy, showsCommitRef: true, now: fixedNow)
        XCTAssertTrue(title.contains("my-site"), title)
        XCTAssertTrue(title.contains("deployed"), title)
        XCTAssertTrue(title.contains("1h ago"), title)
    }

    func testRowIconReflectsState() {
        XCTAssertEqual(SiteRowView.iconName(for: .ready), "checkmark.circle.fill")
        XCTAssertEqual(SiteRowView.iconName(for: .error), "xmark.circle.fill")
        XCTAssertEqual(SiteRowView.iconName(for: .building), "arrow.triangle.2.circlepath")
        XCTAssertEqual(SiteRowView.iconName(for: nil), "circle")
    }
}
