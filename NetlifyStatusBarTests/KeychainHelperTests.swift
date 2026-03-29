import XCTest
@testable import NetlifyStatusBar

final class KeychainHelperTests: XCTestCase {
    let testService = "com.test.NetlifyStatusBar.keychain-tests"

    override func tearDown() {
        try? KeychainHelper.delete(service: testService)
    }

    func testSaveAndReadToken() throws {
        try KeychainHelper.save("test-token-123", service: testService)
        let retrieved = try KeychainHelper.read(service: testService)
        XCTAssertEqual(retrieved, "test-token-123")
    }

    func testOverwriteToken() throws {
        try KeychainHelper.save("first-token", service: testService)
        try KeychainHelper.save("second-token", service: testService)
        let retrieved = try KeychainHelper.read(service: testService)
        XCTAssertEqual(retrieved, "second-token")
    }

    func testReadMissingTokenReturnsNil() throws {
        let result = try KeychainHelper.read(service: testService)
        XCTAssertNil(result)
    }

    func testDeleteRemovesToken() throws {
        try KeychainHelper.save("token", service: testService)
        try KeychainHelper.delete(service: testService)
        let result = try KeychainHelper.read(service: testService)
        XCTAssertNil(result)
    }
}
