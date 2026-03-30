# Netlify Status Bar

A lightweight macOS menu bar app for monitoring Netlify deployments across your account.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange)

## Features

- Color-coded status dot in the menu bar
- Live status text for the most recent deploy
- Pulsing indicator while builds are active
- All Netlify sites in one dropdown
- Account header showing the current user and account/team names
- Stateful polling with active, idle, and disabled modes
- Manual `Refresh Now`, `Disable`, and `Check for Updates…` actions
- Built-in updater that pulls newer builds from GitHub Releases
- Local notifications for deploy start, success, and failure
- Click any site row to open it in the Netlify dashboard

## Requirements

- macOS 14 or later
- A [Netlify Personal Access Token](https://app.netlify.com/user/applications#personal-access-tokens)

## Setup

1. Build and launch the app from Xcode.
2. Open the menu bar app and choose **Preferences…**
3. Paste your Netlify Personal Access Token and save it.

The app starts monitoring immediately after the token is saved.

## Polling Behavior

- `ACTIVE`: polls every 10 seconds for 2 minutes after launch or after a newly detected deploy
- `IDLE`: polls every 60 seconds for up to 30 minutes once activity cools down
- `DISABLED`: stops polling and shows `Netlify` in the menu bar until you open the menu or choose **Refresh Now**

## Building

```bash
xcodegen generate
open NetlifyStatusBar.xcodeproj
```

If the project already exists, you can open `NetlifyStatusBar.xcodeproj` directly.

## App Updates

The app checks GitHub Releases only when you choose **Check for Updates…** from the menu.

If a newer release is found and it includes a `.zip` asset containing the app, Netlify Status Bar downloads it, replaces the current app bundle, and relaunches.

### Release Requirements

- Releases should include a macOS zip asset such as `NetlifyStatusBar-v1.2.0.zip`
- The helper workflow at [publish-release-zip.yml](/Users/azwandi/Development/netlify-status-bar/.github/workflows/publish-release-zip.yml) can attach that asset automatically when a GitHub release is published
- If the app is installed in a protected location, macOS may prompt for administrator access during the update

## Architecture

- SwiftUI `MenuBarExtra` with `.window` style
- `@Observable` `DeployMonitor` for polling and UI state
- `actor` `NetlifyClient` for Netlify API requests
- Keychain storage for the Netlify token
- `NWPathMonitor` for online/offline detection
- `UserNotifications` for deploy alerts
