# Netlify Status Bar

A macOS menu bar app that monitors all Netlify deployments across your account — no paywall, no single-project limit.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange)

## Features

- **Colour-coded status dot** — green (deployed), amber (building), red (failed) in the menu bar
- **Live status bar** — shows the most recent deploy with project name and elapsed/relative time; hides text after 30 minutes of inactivity
- **Pulsing indicator** — dot animates while a build is in progress
- **All projects** — monitors every site in your Netlify account simultaneously, sorted by latest activity
- **Adaptive polling** — checks every 10s during active builds, 60s when idle; starts immediately on launch
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

## Building

```bash
# Generate the Xcode project (requires xcodegen)
xcodegen generate

# Open in Xcode
open NetlifyStatusBar.xcodeproj
```

Or open `NetlifyStatusBar.xcodeproj` directly if you already have the project file.

## Architecture

- **SwiftUI** `MenuBarExtra` with `.window` style (macOS 14+)
- **`@Observable`** `DeployMonitor` injected via SwiftUI environment
- **`actor`** `NetlifyClient` for concurrency-safe networking
- **Keychain** for secure token storage
- **`NWPathMonitor`** for offline detection
- **`UserNotifications`** for deploy event alerts
