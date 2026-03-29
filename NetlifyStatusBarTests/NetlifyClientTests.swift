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
}
