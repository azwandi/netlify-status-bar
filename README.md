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
- **Auto updates** — Sparkle-powered update checks can pull signed releases from a hosted appcast feed
- **Built-in updater UI** — check for updates from the menu and see the current app version in the dropdown
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

## Auto Updates

The app uses [Sparkle](https://sparkle-project.org/) for update checks and in-app installs.

### One-time setup

1. Generate a Sparkle key pair on your Mac:

   ```bash
   ~/Library/Developer/Xcode/DerivedData/NetlifyStatusBar-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

2. Copy the printed public key into the `SPARKLE_PUBLIC_ED_KEY` build setting.
3. Export the private key and save it as a GitHub Actions secret named `SPARKLE_PRIVATE_KEY`.
4. Enable GitHub Pages for this repo, serving from the `main` branch `/docs` folder.

The appcast feed URL is configured to:

```text
https://azwandi.github.io/netlify-status-bar/appcast.xml
```

### Publishing an update

- Create or publish a GitHub release.
- The workflow at [publish-sparkle-update.yml](/Users/azwandi/Development/netlify-status-bar/.github/workflows/publish-sparkle-update.yml) builds the app, uploads a zip to the release, regenerates `docs/appcast.xml`, and pushes the updated feed back to `main`.
- For local publishing, you can also run [publish_sparkle_update.sh](/Users/azwandi/Development/netlify-status-bar/scripts/publish_sparkle_update.sh) with `SPARKLE_PRIVATE_KEY` set.

### Notes

- The current workflow builds unsigned release archives. For public distribution outside your own machine, you should add Developer ID signing and notarization to the release pipeline.
- Auto-update checks only start when both the appcast URL and public key are configured.

## Architecture

- **SwiftUI** `MenuBarExtra` with `.window` style (macOS 14+)
- **`@Observable`** `DeployMonitor` injected via SwiftUI environment
- **`actor`** `NetlifyClient` for concurrency-safe networking
- **Keychain** for secure token storage
- **`NWPathMonitor`** for offline detection
- **`UserNotifications`** for deploy event alerts
