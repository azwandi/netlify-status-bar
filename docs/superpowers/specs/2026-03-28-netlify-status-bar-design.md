# Netlify Status Bar — Design Spec

**Date:** 2026-03-28
**Status:** Approved

---

## Overview

A native macOS menu bar app that monitors all Netlify deployments across a user's account. Shows a live scrolling ticker of active deploys in the menu bar, with a dropdown listing all sites grouped by activity. No paywall, no single-project limit.

**Target:** macOS 13 (Ventura)+
**Framework:** SwiftUI `MenuBarExtra` with `.menu` style
**Auth:** Netlify Personal Access Token, stored in Keychain

---

## Architecture

Three layers with clear separation:

### Network Layer — `NetlifyClient`

A Swift `actor` wrapping `URLSession`. Responsible only for making API calls and decoding JSON responses into local model types. Stateless.

Endpoints used:
- `GET /api/v1/sites` — fetch all sites for the authenticated account
- `GET /api/v1/deploys?site_id={id}&per_page=1` — fetch latest deploy per site

### Domain Layer — `DeployMonitor`

An `@Observable` class that owns all polling logic and state. This is the single source of truth for the UI.

Responsibilities:
- Holds `[Site]` and `[String: Deploy]` (latest deploy keyed by `siteId`)
- Runs adaptive polling: 60s when all deploys are idle, 10s when any deploy is active (`state.isActive == true`)
- Compares old vs new deploy snapshots to detect state transitions and fire notifications
- Exposes `lastError: Error?` for UI error display
- Monitors network connectivity via `NWPathMonitor` — pauses polling when offline, resumes on reconnect

### UI Layer — SwiftUI views

All views are driven purely by `DeployMonitor`. No business logic in views.

- `MenuBarLabel` — the always-visible ticker/icon in the menu bar
- `SiteMenuContent` — the dropdown menu content
- `PreferencesView` — token entry, opened as a separate `Window` scene via `openWindow`

---

## Data Model

```swift
struct Site: Identifiable {
    let id: String
    let name: String
    let url: URL
    let adminURL: URL        // https://app.netlify.com/sites/<id>
}

struct Deploy: Identifiable {
    let id: String
    let siteId: String
    let state: DeployState
    let branch: String
    let createdAt: Date
    let deployedAt: Date?    // nil if not yet complete
}

enum DeployState {
    case enqueued, building, processing, ready, error

    var isActive: Bool {
        self == .building || self == .enqueued || self == .processing
    }
}
```

---

## Menu Bar Item (Ticker)

The `MenuBarLabel` view has three display states:

| State | Display |
|---|---|
| Idle — no active deploys | Small icon only (SF Symbol, system color) |
| Active — 1+ deploys building | Icon + scrolling text ticker |
| Failed — recent failure, no active builds | Icon tinted red + "sitename → failed" |

**Ticker behavior:** Cycles through active deploys every ~3 seconds. Each frame shows `sitename → building…` or `sitename → deploying…`. Transitions use SwiftUI `.transition(.opacity)` + `withAnimation` for a smooth crossfade. No third-party animation libraries.

---

## Dropdown Menu

Built as SwiftUI content inside `MenuBarExtra`. Rendered as a native macOS menu.

**Structure:**

```
[Active Deploys]           ← Section header (hidden when none)
  my-portfolio  ⟳ 1m 23s  ↗
  other-site    ⟳ 45s     ↗

[All Sites]
  shop-frontend  ✓ 3h ago  ↗
  api-docs       ✗ failed  ↗
  landing-page   ✓ 1d ago  ↗

──────────────────────────
Refresh Now
Preferences…
Quit
```

- Each site row is a `Button` that calls `NSWorkspace.shared.open(site.adminURL)`
- Active deploys show elapsed build time counting up in real time
- Relative timestamps (`3h ago`, `just now`) update on each poll
- "Refresh Now" triggers an immediate poll outside the timer schedule

**First launch (no token):** The dropdown shows a single "Set up token…" button that opens `PreferencesView` instead of the site list.

---

## Preferences

A separate `Window` scene (`openWindow(id: "preferences")`).

Contents:
- `SecureField` for Netlify personal access token
- "Test connection" button — hits `GET /api/v1/user`, shows inline success/failure
- Token is read/written via `KeychainHelper`, a thin wrapper over `Security.framework`
- Token is never stored in `UserDefaults` or any plist

---

## Notifications

Uses `UserNotifications` framework. Permission is requested on first launch.

Notification triggers (fired on deploy state transition):

| Transition | Message |
|---|---|
| New deploy detected (→ building/enqueued) | "sitename is deploying" |
| Deploy succeeded (→ ready) | "sitename deployed successfully" |
| Deploy failed (→ error) | "sitename deploy failed" + action opens Netlify dashboard |

Deduplication: each notification is identified by `deploy.id + transition`. The same deploy will never fire the same notification twice.

---

## Error Handling

| Error | Behavior |
|---|---|
| Network error / API failure | Show "⚠ Last refresh failed · 2m ago" row in dropdown; keep displaying stale data |
| 401 Unauthorized | Show "Token invalid or expired" row with link to Preferences |
| 429 Rate limited | Back off to 5-minute polling for that minute, then resume adaptive schedule |
| No internet | `NWPathMonitor` pauses polling; resumes automatically on reconnect |

---

## Polling Logic

```
On tick:
  1. Fetch all sites (GET /api/v1/sites)
  2. Fetch latest deploy per site in parallel (withTaskGroup)
  3. Diff against previous snapshot → fire notifications for transitions
  4. Update published state → UI re-renders

Timer schedule:
  - Any deploy isActive → use 10s timer
  - All deploys settled  → use 60s timer
  - Offline             → pause both timers
```

---

## Out of Scope

- Deploy log viewing (opens Netlify dashboard instead)
- OAuth authentication (token only)
- Branch-level filtering
- Multiple Netlify account support
- Windows / Linux support
