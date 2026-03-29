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
}
