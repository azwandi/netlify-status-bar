# Netlify Status Bar

A macOS menu bar app that monitors all Netlify deployments across your account — no paywall, no single-project limit.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange)

## Features

- **Colour-coded status dot** — green (deployed), amber (building), red (failed) in the menu bar
- **Live status bar** — shows the most recent deploy with project name and elapsed/relative time; hides text after 30 minutes of inactivity
- **Pulsing indicator** — dot animates while a build is in progress
- **All projects** — monitors every site in your Netlify account simultaneously, sorted by latest activity
- **Account header** — shows the current Netlify user plus account/team names at the top of the dropdown
- **Stateful polling** — starts in an active 10s mode, cools to 60s idle checks, then disables itself after 30 minutes of no new deploys until you click the menu bar app again
- **Manual controls** — use **Refresh Now** to wake the app into active polling, or **Disable** to silence polling immediately
- **Built-in updater UI** — check GitHub Releases from the menu, auto-install newer app builds, and see the current version in the dropdown
- **Notifications** — get notified when a deploy starts, succeeds, or fails
- **Grouped dropdown** — active deploys pinned at the top, up to 15 recent sites listed below
- **Click to open** — clicking any site row opens it in the Netlify dashboard

## Requirements

- macOS 14 (Sonoma) or later
- A [Netlify Personal Access Token](https://app.netlify.com/user/applications#personal-access-tokens)

## Setup

1. Build and run the app in Xcode
2. Click the menu bar icon and choose **Preferences…**
3. Paste your Netlify Personal Access Token and click **Save**

The app will immediately begin polling your account and updating the status bar.

### Polling States

- **ACTIVE** — polls every 10 seconds for 2 minutes after launch or whenever a new deploy is detected
- **IDLE** — polls every 60 seconds for up to 30 minutes when deploy activity has cooled down
- **DISABLED** — stops polling and shows `Netlify` in the menu bar until you open the menu or choose **Refresh Now**

## Building

```bash
# Generate the Xcode project (requires xcodegen)
xcodegen generate

# Open in Xcode
open NetlifyStatusBar.xcodeproj
```

Or open `NetlifyStatusBar.xcodeproj` directly if you already have the project file.

## App Updates

The app can manually check the latest GitHub release from the dropdown menu.
If a newer release is available and it includes a `.zip` app asset, the app downloads it, replaces the current bundle, and relaunches.

### Requirements

- The latest GitHub release must include a zipped macOS app bundle asset such as `NetlifyStatusBar-v1.2.0.zip`
- The app must be running from a location that can be replaced, or macOS may prompt for admin access during install
- The workflow at [publish-release-zip.yml](/Users/azwandi/Development/netlify-status-bar/.github/workflows/publish-release-zip.yml) can attach that zip asset automatically whenever you publish a GitHub release

### Notes

- Updates are only checked when you choose **Check for Updates…**
- The current implementation looks at the latest public GitHub release for `azwandi/netlify-status-bar`
- If the newest release does not contain a compatible `.zip` asset, the menu will report that no installable update was found

## Architecture

- **SwiftUI** `MenuBarExtra` with `.window` style (macOS 14+)
- **`@Observable`** `DeployMonitor` injected via SwiftUI environment
- **`actor`** `NetlifyClient` for concurrency-safe networking
- **Keychain** for secure token storage
- **`NWPathMonitor`** for offline detection
- **`UserNotifications`** for deploy event alerts
