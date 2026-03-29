import XCTest
@testable import NetlifyStatusBar

final class NetlifyClientTests: XCTestCase {
    var client: NetlifyClient!

    override func setUp() {
        client = NetlifyClient(token: "test-token", session: MockURLProtocol.makeSession())
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
    }

    func testFetchCurrentUserSucceeds() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.jsonResponse(statusCode: 200, json: [
                "id": "user1",
                "email": "test@example.com",
                "full_name": "Test User"
            ])
        }
        let user = try await client.fetchCurrentUser()
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertEqual(user.fullName, "Test User")
    }

    func testUnauthorizedThrowsUnauthorizedError() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.jsonResponse(statusCode: 401, json: ["error": "Unauthorized"])
        }
        do {
            _ = try await client.fetchCurrentUser()
            XCTFail("Expected error")
        } catch NetlifyError.unauthorized {
            // expected
        }
    }

    func testRateLimitedThrowsRateLimitedError() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.jsonResponse(statusCode: 429, json: [:])
        }
        do {
            _ = try await client.fetchCurrentUser()
            XCTFail("Expected error")
        } catch NetlifyError.rateLimited {
            // expected
        }
    }

    func testUnknownStatusThrowsNetworkError() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.jsonResponse(statusCode: 500, json: [:])
        }
        do {
            _ = try await client.fetchCurrentUser()
            XCTFail("Expected error")
        } catch NetlifyError.networkError {
            // expected
        }
    }

    func testFetchAllSitesReturnsMappedSites() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.jsonResponse(statusCode: 200, json: [
                ["id": "site1", "name": "my-portfolio"],
                ["id": "site2", "name": "shop-frontend"]
            ])
        }
        let sites = try await client.fetchAllSites()
        XCTAssertEqual(sites.count, 2)
        XCTAssertEqual(sites[0].name, "my-portfolio")
        XCTAssertEqual(sites[0].adminURL, URL(string: "https://app.netlify.com/sites/my-portfolio")!)
    }

    func testFetchAllSitesPaginatesUntilPartialPage() async throws {
        var callCount = 0
        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            let json: [[String: String]] = callCount == 1
                ? [["id": "a", "name": "site-a"], ["id": "b", "name": "site-b"]]
                : [["id": "c", "name": "site-c"]]
            return MockURLProtocol.jsonResponse(statusCode: 200, json: json)
        }
        let sites = try await client.fetchAllSites(perPage: 2)
        XCTAssertEqual(sites.count, 3)
        XCTAssertEqual(callCount, 2)
    }

    func testFetchLatestDeployMapsStateCorrectly() async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.jsonResponse(statusCode: 200, json: [[
                "id": "deploy1",
                "site_id": "site1",
                "state": "building",
                "branch": "main",
                "created_at": now
            ]])
        }
        let deploy = try await client.fetchLatestDeploy(siteId: "site1")
        XCTAssertNotNil(deploy)
        XCTAssertEqual(deploy?.state, .building)
        XCTAssertEqual(deploy?.siteId, "site1")
        XCTAssertTrue(deploy!.state.isActive)
    }

    func testFetchLatestDeployReturnsNilForEmptyArray() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.jsonResponse(statusCode: 200, json: [] as [Any])
        }
        let deploy = try await client.fetchLatestDeploy(siteId: "site1")
        XCTAssertNil(deploy)
    }

    func testFetchLatestDeployUnknownStateIsHandled() async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.jsonResponse(statusCode: 200, json: [[
                "id": "d1", "site_id": "s1", "state": "some_future_state",
                "branch": "main", "created_at": now
            ]])
        }
        let deploy = try await client.fetchLatestDeploy(siteId: "s1")
        XCTAssertEqual(deploy?.state, .unknown)
    }
}
