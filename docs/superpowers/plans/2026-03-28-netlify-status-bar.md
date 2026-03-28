# Netlify Status Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS 14+ menu bar app that monitors all Netlify deployments across a user's account, showing a live scrolling ticker and a grouped dropdown panel.

**Architecture:** Three-layer SwiftUI app — `NetlifyClient` actor handles API calls, `DeployMonitor` (@Observable) owns polling/state/notifications, SwiftUI views render purely from monitor state. `MenuBarExtra` with `.window` style enables live-updating dropdown.

**Tech Stack:** Swift 5.10+, SwiftUI, MenuBarExtra (.window), @Observable, URLSession, Security.framework (Keychain), UserNotifications, Network.framework (NWPathMonitor), XCTest

---

## File Structure

```
NetlifyStatusBar/                          ← Xcode project root
├── NetlifyStatusBar.xcodeproj
├── NetlifyStatusBar/
│   ├── NetlifyStatusBarApp.swift          ← @main App, MenuBarExtra, Window scene
│   ├── Models/
│   │   ├── Site.swift                     ← Site struct
│   │   └── Deploy.swift                   ← Deploy struct + DeployState enum
│   ├── Network/
│   │   └── NetlifyClient.swift            ← actor, all API calls, error types
│   ├── Domain/
│   │   ├── KeychainHelper.swift           ← Security.framework wrapper
│   │   ├── DeployMonitor.swift            ← @Observable, polling, diffing
│   │   └── NotificationManager.swift      ← UserNotifications wrapper
│   └── UI/
│       ├── MenuBarLabel.swift             ← Menu bar ticker view
│       ├── SiteListView.swift             ← Dropdown panel (grouped sections)
│       ├── SiteRowView.swift              ← Single site row with status + time
│       └── PreferencesView.swift          ← Token entry window
└── NetlifyStatusBarTests/
    ├── ModelTests.swift
    ├── KeychainHelperTests.swift
    ├── MockURLProtocol.swift              ← URLProtocol mock for network tests
    ├── NetlifyClientTests.swift
    └── DeployMonitorTests.swift
```

---

## Task 1: Create Xcode Project

**Files:**
- Create: `NetlifyStatusBar/NetlifyStatusBar.xcodeproj` (via Xcode GUI)
- Create: `NetlifyStatusBar/NetlifyStatusBar/NetlifyStatusBar.entitlements`
- Modify: `NetlifyStatusBar/NetlifyStatusBar/Info.plist`

- [ ] **Step 1: Create the Xcode project**

Open Xcode → File → New → Project → macOS → App.
- Product Name: `NetlifyStatusBar`
- Bundle Identifier: `com.yourname.NetlifyStatusBar`
- Interface: SwiftUI
- Language: Swift
- Uncheck "Include Tests" (we'll add the test target manually for control)
- Save to: `~/Development/netlify-status-bar/`

- [ ] **Step 2: Set deployment target**

In Xcode → select project → General tab → Minimum Deployments → macOS 14.0

- [ ] **Step 3: Add test target**

File → New → Target → macOS → Unit Testing Bundle → name it `NetlifyStatusBarTests`. Confirm it's added to the scheme.

- [ ] **Step 4: Configure Info.plist — hide dock icon**

Open `NetlifyStatusBar/Info.plist`. Add key:
```xml
<key>LSUIElement</key>
<true/>
```
This makes the app a menu bar agent with no Dock icon.

- [ ] **Step 5: Configure entitlements — outgoing network access**

Open (or create) `NetlifyStatusBar.entitlements`. Ensure:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```
In Xcode → Project → Signing & Capabilities → ensure "Outgoing Connections (Client)" is checked under App Sandbox, or disable App Sandbox entirely for a development-only personal tool.

- [ ] **Step 6: Delete boilerplate**

Delete `ContentView.swift` and `Assets.xcassets` default content (keep the xcassets, just clear the AppIcon placeholder). Leave `NetlifyStatusBarApp.swift` — we'll rewrite it in Task 10.

- [ ] **Step 7: Create folder groups in Xcode**

In Xcode's project navigator, create groups: `Models`, `Network`, `Domain`, `UI`. These are just Xcode groups (folders on disk too — use "New Group with Folder").

- [ ] **Step 8: Commit**

```bash
cd ~/Development/netlify-status-bar
git add NetlifyStatusBar/
git commit -m "feat: scaffold Xcode project with macOS 14 target"
```

---

## Task 2: Data Models

**Files:**
- Create: `NetlifyStatusBar/NetlifyStatusBar/Models/Site.swift`
- Create: `NetlifyStatusBar/NetlifyStatusBar/Models/Deploy.swift`
- Create: `NetlifyStatusBar/NetlifyStatusBarTests/ModelTests.swift`

- [ ] **Step 1: Write failing test for DeployState.isActive**

Create `NetlifyStatusBarTests/ModelTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test — verify it fails**

In Xcode: Cmd+U. Expected: compile error "cannot find type 'DeployState' in scope".

- [ ] **Step 3: Create Site.swift**

```swift
// NetlifyStatusBar/Models/Site.swift
import Foundation

struct Site: Identifiable, Equatable {
    let id: String
    let name: String        // slug, e.g. "my-portfolio"
    let adminURL: URL       // https://app.netlify.com/sites/<name>
}
```

- [ ] **Step 4: Create Deploy.swift**

```swift
// NetlifyStatusBar/Models/Deploy.swift
import Foundation

struct Deploy: Identifiable, Equatable {
    let id: String
    let siteId: String
    let state: DeployState
    let branch: String
    let createdAt: Date
    let deployedAt: Date?
}

enum DeployState: String, Equatable {
    case enqueued, building, processing, ready, error, cancelled, unknown

    var isActive: Bool {
        self == .building || self == .enqueued || self == .processing
    }

    /// Safe init from raw API string — falls back to .unknown
    init(apiString: String) {
        self = DeployState(rawValue: apiString) ?? .unknown
    }
}
```

- [ ] **Step 5: Run tests — verify they pass**

Cmd+U. Expected: all ModelTests pass.

- [ ] **Step 6: Commit**

```bash
git add NetlifyStatusBar/NetlifyStatusBar/Models/ NetlifyStatusBar/NetlifyStatusBarTests/ModelTests.swift
git commit -m "feat: add Site and Deploy data models with tests"
```

---

## Task 3: KeychainHelper

**Files:**
- Create: `NetlifyStatusBar/NetlifyStatusBar/Domain/KeychainHelper.swift`
- Create: `NetlifyStatusBar/NetlifyStatusBarTests/KeychainHelperTests.swift`

- [ ] **Step 1: Write failing tests**

Create `NetlifyStatusBarTests/KeychainHelperTests.swift`:

```swift
import XCTest
@testable import NetlifyStatusBar

final class KeychainHelperTests: XCTestCase {
    let testService = "com.test.NetlifyStatusBar.keychain-tests"

    override func tearDown() {
        // Clean up after each test
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
```

- [ ] **Step 2: Run test — verify it fails**

Cmd+U. Expected: compile error "cannot find 'KeychainHelper'".

- [ ] **Step 3: Create KeychainHelper.swift**

```swift
// NetlifyStatusBar/Domain/KeychainHelper.swift
import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
}

enum KeychainHelper {
    private static let defaultService = "com.yourname.NetlifyStatusBar"

    static func save(_ token: String, service: String = defaultService) throws {
        let data = Data(token.utf8)

        // Try update first
        let updateQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]
        let updateAttributes: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist — add it
            let addQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecValueData: data
            ]
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    static func read(service: String = defaultService) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    @discardableResult
    static func delete(service: String = defaultService) throws -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        return true
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

Cmd+U. Expected: all KeychainHelperTests pass.

> **Note:** If tests fail with `errSecMissingEntitlement`, ensure the test target has keychain access. In Xcode → test target → Signing & Capabilities → add Keychain Sharing capability with an access group, or disable App Sandbox on the test target.

- [ ] **Step 5: Commit**

```bash
git add NetlifyStatusBar/NetlifyStatusBar/Domain/KeychainHelper.swift NetlifyStatusBar/NetlifyStatusBarTests/KeychainHelperTests.swift
git commit -m "feat: add KeychainHelper with save/read/delete and tests"
```

---

## Task 4: NetlifyClient — Core Infrastructure

**Files:**
- Create: `NetlifyStatusBar/NetlifyStatusBar/Network/NetlifyClient.swift`
- Create: `NetlifyStatusBar/NetlifyStatusBarTests/MockURLProtocol.swift`
- Create: `NetlifyStatusBar/NetlifyStatusBarTests/NetlifyClientTests.swift`

- [ ] **Step 1: Create MockURLProtocol**

Create `NetlifyStatusBarTests/MockURLProtocol.swift`:

```swift
import Foundation

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// Returns a URLSession configured to use MockURLProtocol
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Helper to build a JSON response
    static func jsonResponse(statusCode: Int, json: Any, url: URL = URL(string: "https://api.netlify.com")!) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        let data = try! JSONSerialization.data(withJSONObject: json)
        return (response, data)
    }
}
```

- [ ] **Step 2: Write failing test for NetlifyError**

Create `NetlifyStatusBarTests/NetlifyClientTests.swift`:

```swift
import XCTest
@testable import NetlifyStatusBar

final class NetlifyClientTests: XCTestCase {
    var client: NetlifyClient!

    override func setUp() {
        client = NetlifyClient(token: "test-token", session: MockURLProtocol.makeSession())
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
}
```

- [ ] **Step 3: Run test — verify it fails**

Cmd+U. Expected: compile error "cannot find 'NetlifyClient'".

- [ ] **Step 4: Create NetlifyClient.swift with core infrastructure**

```swift
// NetlifyStatusBar/Network/NetlifyClient.swift
import Foundation

enum NetlifyError: Error, Equatable {
    case unauthorized
    case rateLimited
    case networkError(String)
    case decodingError(String)
}

actor NetlifyClient {
    private let token: String
    private let session: URLSession
    private let baseURL = URL(string: "https://api.netlify.com")!

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    // MARK: - Core request

    private func request<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw NetlifyError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw NetlifyError.networkError("Non-HTTP response")
        }

        switch http.statusCode {
        case 200...299: break
        case 401: throw NetlifyError.unauthorized
        case 429: throw NetlifyError.rateLimited
        default: throw NetlifyError.networkError("HTTP \(http.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetlifyError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - User endpoint

    func fetchCurrentUser() async throws -> NetlifyUser {
        try await request("api/v1/user")
    }
}

// MARK: - API response types

struct NetlifyUser: Decodable {
    let id: String
    let email: String
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case fullName = "full_name"
    }
}
```

- [ ] **Step 5: Run tests — verify they pass**

Cmd+U. Expected: all NetlifyClientTests pass.

- [ ] **Step 6: Commit**

```bash
git add NetlifyStatusBar/NetlifyStatusBar/Network/ NetlifyStatusBar/NetlifyStatusBarTests/MockURLProtocol.swift NetlifyStatusBar/NetlifyStatusBarTests/NetlifyClientTests.swift
git commit -m "feat: add NetlifyClient core with error handling and mock URLProtocol"
```

---

## Task 5: NetlifyClient — Sites Fetching

**Files:**
- Modify: `NetlifyStatusBar/NetlifyStatusBar/Network/NetlifyClient.swift`
- Modify: `NetlifyStatusBar/NetlifyStatusBarTests/NetlifyClientTests.swift`

- [ ] **Step 1: Write failing tests for fetchAllSites**

Add to `NetlifyClientTests.swift`:

```swift
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
    MockURLProtocol.requestHandler = { request in
        callCount += 1
        // Page 1: full page of 2 (simulating per_page=2 for test)
        // Page 2: partial page (1 item) → stop
        let json: [[String: String]] = callCount == 1
            ? [["id": "a", "name": "site-a"], ["id": "b", "name": "site-b"]]
            : [["id": "c", "name": "site-c"]]
        return MockURLProtocol.jsonResponse(statusCode: 200, json: json)
    }
    // Use perPage:2 to trigger pagination with small data
    let sites = try await client.fetchAllSites(perPage: 2)
    XCTAssertEqual(sites.count, 3)
    XCTAssertEqual(callCount, 2)
}
```

- [ ] **Step 2: Run tests — verify they fail**

Cmd+U. Expected: compile errors for `fetchAllSites`.

- [ ] **Step 3: Add fetchAllSites to NetlifyClient.swift**

Add after `fetchCurrentUser`:

```swift
// MARK: - Sites

func fetchAllSites(perPage: Int = 100) async throws -> [Site] {
    var all: [Site] = []
    var page = 1
    while true {
        let batch: [APISite] = try await request(
            "api/v1/sites",
            queryItems: [
                URLQueryItem(name: "per_page", value: "\(perPage)"),
                URLQueryItem(name: "page", value: "\(page)")
            ]
        )
        all += batch.map { $0.toSite() }
        if batch.count < perPage { break }
        page += 1
    }
    return all
}
```

Add API response type and mapping after `NetlifyUser`:

```swift
private struct APISite: Decodable {
    let id: String
    let name: String

    func toSite() -> Site {
        Site(
            id: id,
            name: name,
            adminURL: URL(string: "https://app.netlify.com/sites/\(name)")!
        )
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

Cmd+U. Expected: all tests pass including pagination test.

- [ ] **Step 5: Commit**

```bash
git add NetlifyStatusBar/NetlifyStatusBar/Network/NetlifyClient.swift NetlifyStatusBar/NetlifyStatusBarTests/NetlifyClientTests.swift
git commit -m "feat: add fetchAllSites with pagination to NetlifyClient"
```

---

## Task 6: NetlifyClient — Deploys Fetching

**Files:**
- Modify: `NetlifyStatusBar/NetlifyStatusBar/Network/NetlifyClient.swift`
- Modify: `NetlifyStatusBar/NetlifyStatusBarTests/NetlifyClientTests.swift`

- [ ] **Step 1: Write failing test**

Add to `NetlifyClientTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests — verify they fail**

Cmd+U. Expected: compile errors for `fetchLatestDeploy`.

- [ ] **Step 3: Add fetchLatestDeploy to NetlifyClient.swift**

Add after `fetchAllSites`:

```swift
// MARK: - Deploys

func fetchLatestDeploy(siteId: String) async throws -> Deploy? {
    let deploys: [APIDeploy] = try await request(
        "api/v1/deploys",
        queryItems: [
            URLQueryItem(name: "site_id", value: siteId),
            URLQueryItem(name: "per_page", value: "1")
        ]
    )
    return deploys.first?.toDeploy()
}
```

Add API response type after `APISite`:

```swift
private struct APIDeploy: Decodable {
    let id: String
    let siteId: String
    let state: String
    let branch: String
    let createdAt: Date
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, state, branch
        case siteId = "site_id"
        case createdAt = "created_at"
        case publishedAt = "published_at"
    }

    func toDeploy() -> Deploy {
        Deploy(
            id: id,
            siteId: siteId,
            state: DeployState(apiString: state),
            branch: branch,
            createdAt: createdAt,
            deployedAt: publishedAt
        )
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

Cmd+U. Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add NetlifyStatusBar/NetlifyStatusBar/Network/NetlifyClient.swift NetlifyStatusBar/NetlifyStatusBarTests/NetlifyClientTests.swift
git commit -m "feat: add fetchLatestDeploy with unknown-state fallback"
```

---

## Task 7: NotificationManager

**Files:**
- Create: `NetlifyStatusBar/NetlifyStatusBar/Domain/NotificationManager.swift`

No unit tests here — `UNUserNotificationCenter` is not unit-testable in isolation; behavior is verified via integration in Task 9.

- [ ] **Step 1: Create NotificationManager.swift**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add NetlifyStatusBar/NetlifyStatusBar/Domain/NotificationManager.swift
git commit -m "feat: add NotificationManager with deduplication"
```

---

## Task 8: DeployMonitor

**Files:**
- Create: `NetlifyStatusBar/NetlifyStatusBar/Domain/DeployMonitor.swift`
- Create: `NetlifyStatusBar/NetlifyStatusBarTests/DeployMonitorTests.swift`

- [ ] **Step 1: Write failing tests**

Create `NetlifyStatusBarTests/DeployMonitorTests.swift`:

```swift
import XCTest
@testable import NetlifyStatusBar

final class DeployMonitorTests: XCTestCase {
    // Tests for diffing logic (pure function, no timers)

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
}
```

- [ ] **Step 2: Run tests — verify they fail**

Cmd+U. Expected: compile errors for `DeployMonitor`.

- [ ] **Step 3: Create DeployMonitor.swift**

```swift
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
        guard let token = try? KeychainHelper.read(), token != nil else { return }
        client = NetlifyClient(token: token!)
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
        Task { await refreshSites() }
        startDeployPolling()
        startSiteRefreshTimer()
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
                try? await Task.sleep(for: .seconds(600)) // 10 minutes
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
                    interval = 300 // 5 minutes during backoff
                } else {
                    rateLimitBackoffUntil = nil
                    interval = Self.hasActiveDeploys(in: deploys) ? 10 : 60
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func pollDeploys() async {
        guard let client, isOnline, !sites.isEmpty else {
            if sites.isEmpty && client != nil { isLoading = false }
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
        pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
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

    // MARK: - Pure helpers (testable static functions)

    static func diffDeploys(old: [String: Deploy], new: [String: Deploy]) -> [DeployTransition] {
        var transitions: [DeployTransition] = []
        for (siteId, newDeploy) in new {
            let oldDeploy = old[siteId]
            // New deploy ID appeared and it's active → started
            if oldDeploy == nil && newDeploy.state.isActive {
                transitions.append(DeployTransition(siteId: siteId, deployId: newDeploy.id, kind: .started))
            }
            // Same deploy, state changed
            if let old = oldDeploy, old.id == newDeploy.id, old.state != newDeploy.state {
                switch newDeploy.state {
                case .ready:
                    transitions.append(DeployTransition(siteId: siteId, deployId: newDeploy.id, kind: .succeeded))
                case .error:
                    transitions.append(DeployTransition(siteId: siteId, deployId: newDeploy.id, kind: .failed))
                default:
                    break
                }
            }
            // Different deploy ID (new deploy started)
            if let old = oldDeploy, old.id != newDeploy.id && newDeploy.state.isActive {
                transitions.append(DeployTransition(siteId: siteId, deployId: newDeploy.id, kind: .started))
            }
        }
        return transitions
    }

    static func hasActiveDeploys(in deploys: [String: Deploy]) -> Bool {
        deploys.values.contains { $0.state.isActive }
    }
}

// MARK: - Supporting types

struct DeployTransition {
    let siteId: String
    let deployId: String
    let kind: Kind

    enum Kind { case started, succeeded, failed }
}
```

- [ ] **Step 4: Run tests — verify they pass**

Cmd+U. Expected: all DeployMonitorTests pass.

- [ ] **Step 5: Commit**

```bash
git add NetlifyStatusBar/NetlifyStatusBar/Domain/DeployMonitor.swift NetlifyStatusBar/NetlifyStatusBarTests/DeployMonitorTests.swift
git commit -m "feat: add DeployMonitor with polling, diffing, and notification dispatch"
```

---

## Task 9: App Entry Point

**Files:**
- Modify: `NetlifyStatusBar/NetlifyStatusBar/NetlifyStatusBarApp.swift`

- [ ] **Step 1: Rewrite NetlifyStatusBarApp.swift**

```swift
// NetlifyStatusBar/NetlifyStatusBarApp.swift
import SwiftUI

@main
struct NetlifyStatusBarApp: App {
    @State private var monitor = DeployMonitor()

    var body: some Scene {
        MenuBarExtra {
            SiteListView()
                .environment(monitor)
        } label: {
            MenuBarLabel()
                .environment(monitor)
        }
        .menuBarExtraStyle(.window)

        Window("Preferences", id: "preferences") {
            PreferencesView()
                .environment(monitor)
        }
        .windowResizability(.contentSize)
    }

    init() {
        // Start monitoring after init so @State is ready
    }
}
```

> **Note:** Call `monitor.start()` from `.onAppear` in `SiteListView` rather than in `init()` to ensure the `@State` is initialized before side effects run.

- [ ] **Step 2: Verify the project builds**

Cmd+B. Expected: build succeeds (some views may be missing — that's fine, they're next).

- [ ] **Step 3: Commit**

```bash
git add NetlifyStatusBar/NetlifyStatusBar/NetlifyStatusBarApp.swift
git commit -m "feat: wire up App entry point with MenuBarExtra and Preferences window"
```

---

## Task 10: MenuBarLabel

**Files:**
- Create: `NetlifyStatusBar/NetlifyStatusBar/UI/MenuBarLabel.swift`

- [ ] **Step 1: Create MenuBarLabel.swift**

```swift
// NetlifyStatusBar/UI/MenuBarLabel.swift
import SwiftUI

struct MenuBarLabel: View {
    @Environment(DeployMonitor.self) private var monitor
    @State private var tickerIndex: Int = 0
    @State private var showTicker: Bool = true
    @State private var tickerTimer: Timer? = nil

    private var activeDeploys: [(site: Site, deploy: Deploy)] {
        monitor.sites.compactMap { site in
            guard let deploy = monitor.deploys[site.id], deploy.state.isActive else { return nil }
            return (site, deploy)
        }
    }

    private var hasFailures: Bool {
        monitor.deploys.values.contains { $0.state == .error } && activeDeploys.isEmpty
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "network")
                .foregroundStyle(iconColor)

            if !activeDeploys.isEmpty {
                tickerText
            } else if hasFailures {
                failedText
            }
        }
        .onAppear { restartTicker() }
        .onChange(of: activeDeploys.count) { restartTicker() }
        .onDisappear { stopTicker() }
    }

    @ViewBuilder
    private var tickerText: some View {
        if showTicker && !activeDeploys.isEmpty {
            let item = activeDeploys[tickerIndex % activeDeploys.count]
            Text("\(item.site.name) → \(tickerLabel(item.deploy.state))…")
                .font(.system(size: 11))
                .transition(.opacity)
                .id(tickerIndex)
        }
    }

    private var failedText: some View {
        let failedSite = monitor.sites.first { monitor.deploys[$0.id]?.state == .error }
        return Text("\(failedSite?.name ?? "site") → failed")
            .font(.system(size: 11))
            .foregroundStyle(.red)
    }

    private var iconColor: Color {
        if hasFailures { return .red }
        if !activeDeploys.isEmpty { return .orange }
        return .primary
    }

    private func tickerLabel(_ state: DeployState) -> String {
        switch state {
        case .building: return "building"
        case .enqueued: return "queued"
        case .processing: return "processing"
        default: return "deploying"
        }
    }

    private func stopTicker() {
        tickerTimer?.invalidate()
        tickerTimer = nil
    }

    private func restartTicker() {
        stopTicker()
        guard !activeDeploys.isEmpty else { return }
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [self] timer in
            guard !activeDeploys.isEmpty else { timer.invalidate(); return }
            withAnimation(.easeInOut(duration: 0.3)) { showTicker = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                tickerIndex += 1
                withAnimation(.easeInOut(duration: 0.3)) { showTicker = true }
            }
        }
    }
}
```

- [ ] **Step 2: Build and verify no compile errors**

Cmd+B. Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add NetlifyStatusBar/NetlifyStatusBar/UI/MenuBarLabel.swift
git commit -m "feat: add MenuBarLabel with idle/active/failed states and ticker animation"
```

---

## Task 11: SiteRowView

**Files:**
- Create: `NetlifyStatusBar/NetlifyStatusBar/UI/SiteRowView.swift`

- [ ] **Step 1: Create SiteRowView.swift**

```swift
// NetlifyStatusBar/UI/SiteRowView.swift
import SwiftUI

struct SiteRowView: View {
    let site: Site
    let deploy: Deploy?
    @State private var now: Date = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Button {
            NSWorkspace.shared.open(site.adminURL)
        } label: {
            HStack {
                statusIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text(site.name)
                        .font(.system(size: 13))
                    if let deploy {
                        Text(subtitleText(for: deploy))
                            .font(.system(size: 10))
                            .foregroundStyle(subtitleColor(for: deploy.state))
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onReceive(timer) { now = $0 }
    }

    private var statusIcon: some View {
        Group {
            switch deploy?.state {
            case .building, .enqueued, .processing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            default:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
    }

    private func subtitleText(for deploy: Deploy) -> String {
        switch deploy.state {
        case .building, .enqueued, .processing:
            return "⟳ \(elapsedString(from: deploy.createdAt))"
        case .ready:
            return "✓ \(relativeString(from: deploy.deployedAt ?? deploy.createdAt))"
        case .error:
            return "✗ failed · \(relativeString(from: deploy.createdAt))"
        case .cancelled:
            return "cancelled · \(relativeString(from: deploy.createdAt))"
        default:
            return relativeString(from: deploy.createdAt)
        }
    }

    private func subtitleColor(for state: DeployState) -> Color {
        switch state {
        case .building, .enqueued, .processing: return .orange
        case .ready: return .green
        case .error: return .red
        default: return .secondary
        }
    }

    private func elapsedString(from date: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    private func relativeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
```

- [ ] **Step 2: Build — verify no errors**

Cmd+B. Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add NetlifyStatusBar/NetlifyStatusBar/UI/SiteRowView.swift
git commit -m "feat: add SiteRowView with live elapsed timer and relative timestamps"
```

---

## Task 12: SiteListView

**Files:**
- Create: `NetlifyStatusBar/NetlifyStatusBar/UI/SiteListView.swift`

- [ ] **Step 1: Create SiteListView.swift**

```swift
// NetlifyStatusBar/UI/SiteListView.swift
import SwiftUI

struct SiteListView: View {
    @Environment(DeployMonitor.self) private var monitor
    @Environment(\.openWindow) private var openWindow

    private var activeSites: [Site] {
        monitor.sites.filter { monitor.deploys[$0.id]?.state.isActive == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !hasToken {
                noTokenView
            } else if monitor.isLoading {
                loadingView
            } else {
                siteListContent
            }
        }
        .frame(width: 280)
        .onAppear { monitor.start() }
    }

    // MARK: - States

    private var noTokenView: some View {
        Button("Set up token…") {
            openWindow(id: "preferences")
        }
        .padding()
    }

    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.7)
            Text("Loading sites…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var siteListContent: some View {
        // Error banners
        if monitor.isUnauthorized {
            errorRow("Token invalid or expired") { openWindow(id: "preferences") }
        } else if let error = monitor.lastError {
            Text("⚠ Last refresh failed — \(error.localizedDescription)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }

        // Active deploys section
        if !activeSites.isEmpty {
            sectionHeader("Active Deploys")
            ForEach(activeSites) { site in
                SiteRowView(site: site, deploy: monitor.deploys[site.id])
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
            }
            Divider().padding(.vertical, 4)
        }

        // All sites section
        sectionHeader("All Sites")
        ScrollView {
            VStack(spacing: 0) {
                ForEach(monitor.sites) { site in
                    SiteRowView(site: site, deploy: monitor.deploys[site.id])
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                }
            }
        }
        .frame(maxHeight: 300)

        Divider().padding(.vertical, 4)

        // Footer actions
        Group {
            Button("Refresh Now") {
                Task { await monitor.pollDeploys() }
            }
            Button("Preferences…") {
                openWindow(id: "preferences")
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .buttonStyle(.plain)
        .font(.system(size: 13))
    }

    // MARK: - Helpers

    private var hasToken: Bool {
        (try? KeychainHelper.read()) != nil
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func errorRow(_ message: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Build — verify no errors**

Cmd+B. Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add NetlifyStatusBar/NetlifyStatusBar/UI/SiteListView.swift
git commit -m "feat: add SiteListView with grouped sections, error states, and footer actions"
```

---

## Task 13: PreferencesView

**Files:**
- Create: `NetlifyStatusBar/NetlifyStatusBar/UI/PreferencesView.swift`

- [ ] **Step 1: Create PreferencesView.swift**

```swift
// NetlifyStatusBar/UI/PreferencesView.swift
import SwiftUI

struct PreferencesView: View {
    @Environment(DeployMonitor.self) private var monitor
    @State private var token: String = ""
    @State private var connectionStatus: ConnectionStatus = .idle

    enum ConnectionStatus {
        case idle, testing, success(String), failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Netlify Status Bar")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Personal Access Token")
                    .font(.system(size: 12, weight: .medium))
                SecureField("paste token here…", text: $token)
                    .textFieldStyle(.roundedBorder)
                Text("Generate one at: app.netlify.com/user/applications")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Connection status feedback
            if case .testing = connectionStatus {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Testing connection…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else if case .success(let user) = connectionStatus {
                Label("Connected as \(user)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            } else if case .failure(let message) = connectionStatus {
                Label(message, systemImage: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Test Connection") {
                    Task { await testConnection() }
                }
                .disabled(token.isEmpty)

                Spacer()

                Button("Save") {
                    Task { await save() }
                }
                .disabled(token.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            token = (try? KeychainHelper.read()) ?? ""
        }
    }

    private func testConnection() async {
        connectionStatus = .testing
        let client = NetlifyClient(token: token)
        do {
            let user = try await client.fetchCurrentUser()
            connectionStatus = .success(user.email)
        } catch NetlifyError.unauthorized {
            connectionStatus = .failure("Invalid token")
        } catch {
            connectionStatus = .failure(error.localizedDescription)
        }
    }

    private func save() async {
        do {
            // Validate token first
            connectionStatus = .testing
            let client = NetlifyClient(token: token)
            let user = try await client.fetchCurrentUser()
            connectionStatus = .success(user.email)

            // Save to keychain
            try KeychainHelper.save(token)

            // Request notification permission now that we have a confirmed token
            await MainActor.run {
                NotificationManager.shared.requestPermission()
            }

            // Restart monitoring with new token
            monitor.restart(withToken: token)
        } catch NetlifyError.unauthorized {
            connectionStatus = .failure("Invalid token — not saved")
        } catch {
            connectionStatus = .failure("Save failed: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 2: Build — verify no errors**

Cmd+B. Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add NetlifyStatusBar/NetlifyStatusBar/UI/PreferencesView.swift
git commit -m "feat: add PreferencesView with token save, test connection, and notification permission"
```

---

## Task 14: Integration Smoke Test

**Files:** No new files — manual verification checklist.

- [ ] **Step 1: Run the app**

Cmd+R. The app should launch with no Dock icon. A network icon should appear in the menu bar.

- [ ] **Step 2: Test no-token state**

Click the menu bar icon. Panel should show "Set up token…" button.

- [ ] **Step 3: Test preferences flow**

Click "Set up token…". Preferences window opens. Paste a real Netlify personal access token. Click "Test Connection" — should show "Connected as you@email.com". Click "Save" — panel should close and sites should start loading.

- [ ] **Step 4: Test loading state**

On first launch with token, panel should briefly show "Loading sites…" before populating.

- [ ] **Step 5: Test site list**

Menu bar panel should show all your Netlify sites grouped under "All Sites". Each site should show its last deploy status and relative time.

- [ ] **Step 6: Test Refresh Now**

Click "Refresh Now" — deploys should re-fetch immediately.

- [ ] **Step 7: Add .gitignore**

Create `NetlifyStatusBar/.gitignore`:

```
# Xcode
*.xcuserstate
*.xccheckout
xcuserdata/
DerivedData/
.build/
*.pbxuser
!default.pbxuser
*.mode1v3
!default.mode1v3
*.mode2v3
!default.mode2v3
*.perspectivev3
!default.perspectivev3

# macOS
.DS_Store
```

- [ ] **Step 8: Final commit**

```bash
git add NetlifyStatusBar/.gitignore
git commit -m "chore: add .gitignore for Xcode project"
```
