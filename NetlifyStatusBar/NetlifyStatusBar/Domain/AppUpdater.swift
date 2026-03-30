import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppUpdater {
    var isCheckingForUpdates = false
    var statusMessage: String?

    private static let owner = "azwandi"
    private static let repository = "netlify-status-bar"
    private static let appName = "NetlifyStatusBar"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkForUpdates() async {
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true
        statusMessage = "Checking for updates…"
        defer { isCheckingForUpdates = false }

        do {
            let release = try await fetchLatestRelease()
            let currentVersion = Self.currentVersionString()

            guard Self.isNewerVersion(release.tagName, than: currentVersion) else {
                statusMessage = "You're up to date"
                return
            }

            guard let asset = Self.preferredAsset(from: release.assets) else {
                statusMessage = "No installable update found in the latest release"
                return
            }

            statusMessage = "Downloading \(release.tagName)…"
            let archiveURL = try await downloadAsset(asset)

            statusMessage = "Preparing update…"
            let extractedAppURL = try extractApp(from: archiveURL)

            statusMessage = "Installing \(release.tagName)…"
            try installUpdate(from: extractedAppURL)
            statusMessage = "Installing update and relaunching…"
        } catch {
            statusMessage = "Update failed: \(error.localizedDescription)"
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NetlifyStatusBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdaterError.invalidResponse
        }

        guard 200...299 ~= http.statusCode else {
            throw UpdaterError.httpError(http.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    private func downloadAsset(_ asset: GitHubReleaseAsset) async throws -> URL {
        let (temporaryURL, response) = try await session.download(from: asset.browserDownloadURL)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdaterError.httpError(statusCode)
        }

        let downloadDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetlifyStatusBarUpdate", isDirectory: true)
        try? FileManager.default.removeItem(at: downloadDirectory)
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)

        let destinationURL = downloadDirectory.appendingPathComponent(asset.name)
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func extractApp(from archiveURL: URL) throws -> URL {
        let extractDirectory = archiveURL.deletingLastPathComponent().appendingPathComponent("Extracted", isDirectory: true)
        try? FileManager.default.removeItem(at: extractDirectory)
        try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)

        try Self.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archiveURL.path, extractDirectory.path]
        )

        guard let extractedAppURL = Self.findApp(in: extractDirectory) else {
            throw UpdaterError.appBundleNotFound
        }
        return extractedAppURL
    }

    private func installUpdate(from extractedAppURL: URL) throws {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        guard bundleURL.pathExtension == "app" else {
            throw UpdaterError.unsupportedInstallLocation
        }

        let scriptDirectory = extractedAppURL.deletingLastPathComponent()
        let scriptURL = scriptDirectory.appendingPathComponent("install_update.sh")
        let sourcePath = extractedAppURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let targetPath = bundleURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let newTargetPath = "\(bundleURL.path).new".replacingOccurrences(of: "\"", with: "\\\"")
        let pid = ProcessInfo.processInfo.processIdentifier

        let script = """
        #!/bin/zsh
        set -euo pipefail
        SOURCE_APP="\(sourcePath)"
        TARGET_APP="\(targetPath)"
        NEW_TARGET_APP="\(newTargetPath)"
        APP_PID="\(pid)"

        while kill -0 "$APP_PID" 2>/dev/null; do
          sleep 1
        done

        install_update() {
          rm -rf "$NEW_TARGET_APP"
          /usr/bin/ditto "$SOURCE_APP" "$NEW_TARGET_APP"
          rm -rf "$TARGET_APP"
          mv "$NEW_TARGET_APP" "$TARGET_APP"
          open "$TARGET_APP"
        }

        if install_update; then
          exit 0
        fi

        ADMIN_COMMAND=$(printf 'rm -rf %q && /usr/bin/ditto %q %q && rm -rf %q && mv %q %q && open %q' "$NEW_TARGET_APP" "$SOURCE_APP" "$NEW_TARGET_APP" "$TARGET_APP" "$NEW_TARGET_APP" "$TARGET_APP" "$TARGET_APP")
        /usr/bin/osascript -e "do shell script \\"$ADMIN_COMMAND\\" with administrator privileges"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        try process.run()

        NSApplication.shared.terminate(nil)
    }

    private static func preferredAsset(from assets: [GitHubReleaseAsset]) -> GitHubReleaseAsset? {
        assets.first {
            $0.name.lowercased().hasSuffix(".zip") && $0.name.contains(appName)
        } ?? assets.first {
            $0.name.lowercased().hasSuffix(".zip")
        }
    }

    private static func findApp(in directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "app" {
                return url
            }
        }
        return nil
    }

    private static func currentVersionString(bundle: Bundle = .main) -> String {
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return shortVersion ?? "0"
    }

    private static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let candidateComponents = normalizedVersionComponents(from: candidate)
        let currentComponents = normalizedVersionComponents(from: current)
        let count = max(candidateComponents.count, currentComponents.count)

        for index in 0..<count {
            let candidateValue = index < candidateComponents.count ? candidateComponents[index] : 0
            let currentValue = index < currentComponents.count ? currentComponents[index] : 0
            if candidateValue != currentValue {
                return candidateValue > currentValue
            }
        }
        return false
    }

    private static func normalizedVersionComponents(from rawVersion: String) -> [Int] {
        rawVersion
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .compactMap { Int($0) }
    }

    private static func runProcess(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdaterError.processFailed(message?.isEmpty == false ? message! : "Process failed")
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private enum UpdaterError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case appBundleNotFound
    case unsupportedInstallLocation
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from GitHub"
        case let .httpError(statusCode):
            return "GitHub returned HTTP \(statusCode)"
        case .appBundleNotFound:
            return "Downloaded update did not contain an app bundle"
        case .unsupportedInstallLocation:
            return "Current app location can't be updated automatically"
        case let .processFailed(message):
            return message
        }
    }
}
