# Netlify Status Bar — Design Spec

**Date:** 2026-03-28
**Status:** Approved

---

## Overview

A native macOS menu bar app that monitors all Netlify deployments across a user's account. Shows a live scrolling ticker of active deploys in the menu bar, with a dropdown listing all sites grouped by activity. No paywall, no single-project limit.

**Target:** macOS 13 (Ventura)+
**Framework:** SwiftUI `MenuBarExtra` with `.window` style
**Auth:** Netlify Personal Access Token, stored in Keychain

> **Note on `.window` vs `.menu` style:** The `.menu` style renders a native `NSMenu` and does not support live SwiftUI views — menu items are rendered once on open and cannot update. Since the dropdown requires real-time elapsed build timers and conditional section headers, `.window` style is used instead. This renders the dropdown as a floating SwiftUI panel that updates live while open.

---

## Architecture

Three layers with clear separation:

### Network Layer — `NetlifyClient`

A Swift `actor` wrapping `URLSession`. Responsible only for making API calls and decoding JSON responses into local model types. Stateless.

Endpoints used:
- `GET /api/v1/sites?per_page=100&page={n}` — fetch all sites with pagination (see Pagination section); called only on startup and every 10 minutes, not on every deploy poll
- `GET /api/v1/deploys?site_id={id}&per_page=1` — fetch latest deploy per site; called on every poll tick

### Domain Layer — `DeployMonitor`

An `@Observable` class that owns all polling logic and state. This is the single source of truth for the UI.

`DeployMonitor` is instantiated once as `@State private var monitor = DeployMonitor()` on the `App` struct and injected into the SwiftUI environment via `.environment(monitor)`. All views read it from the environment using `@Environment(DeployMonitor.self)`.

Responsibilities:
- Holds `[Site]` and `[String: Deploy]` (latest deploy keyed by `siteId`)
- Holds `isLoading: Bool` — true from first launch until the first poll completes successfully
- Runs adaptive polling: 60s when all deploys are idle, 10s when any deploy is active (`state.isActive == true`)
- Compares old vs new deploy snapshots to detect state transitions and fire notifications
- Exposes `lastError: Error?` for UI error display
- Monitors network connectivity via `NWPathMonitor` — pauses polling when offline, resumes on reconnect
- Refreshes the site list on launch and every 10 minutes independent of deploy polling

### UI Layer — SwiftUI views

All views are driven purely by `DeployMonitor`. No business logic in views.

- `MenuBarLabel` — the always-visible ticker/icon in the menu bar
- `SiteListView` — the dropdown panel content (live SwiftUI view)
- `PreferencesView` — token entry, opened as a separate `Window` scene via `openWindow`

---

## Data Model

```swift
struct Site: Identifiable {
    let id: String
    let name: String        // slug, e.g. "my-portfolio"
    let adminURL: URL       // https://app.netlify.com/sites/<name>
}

struct Deploy: Identifiable {
    let id: String
    let siteId: String
    let state: DeployState
    let branch: String
    let createdAt: Date
    let deployedAt: Date?   // nil if not yet complete
}

enum DeployState {
    case enqueued, building, processing, ready, error, cancelled, unknown

    var isActive: Bool {
        self == .building || self == .enqueued || self == .processing
    }
}
```

`adminURL` is constructed using the site **name** (slug), not the ID: `https://app.netlify.com/sites/<name>`. The Netlify dashboard URL uses the slug, not the UUID.

`DeployState.cancelled` covers deploys cancelled by the user or by Netlify. No notification is fired for cancellations. `DeployState.unknown` is a safe fallback for any API state string not explicitly handled.

---

## Pagination

`GET /api/v1/sites` is paginated. `NetlifyClient` fetches pages sequentially until a page returns fewer items than `per_page` (default 100), indicating the last page. All pages are accumulated before returning to `DeployMonitor`. This happens on each full poll cycle.

---

## Menu Bar Item (Ticker)

The `MenuBarLabel` view has three display states:

| State | Display |
|---|---|
| Idle — no active deploys | Small icon only (SF Symbol, system color) |
| Active — 1+ deploys building | Icon + scrolling text ticker |
| Failed — any site has `error` state, no active builds | Icon tinted red + "sitename → failed" |

**Failed state reset:** The red/failed state clears when the failed site's next deploy succeeds (transitions to `ready`), or when the user triggers "Refresh Now" and the latest deploy for that site is no longer `error`. It does not auto-clear on a timer.

**Ticker behavior:** Cycles through active deploys every ~3 seconds. Each frame shows `sitename → building…` or `sitename → deploying…`. Transitions use SwiftUI `.transition(.opacity)` + `withAnimation` for a smooth crossfade. No third-party animation libraries.

---

## Dropdown Panel

`MenuBarExtra` with `.window` style renders a floating SwiftUI panel — not a native `NSMenu`. This enables live updates while the panel is open (real-time elapsed timers, dynamic section headers).

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
- Active deploys show elapsed build time counting up in real time (driven by a 1s `Timer` publisher while the panel is open)
- Relative timestamps (`3h ago`, `just now`) update on each poll
- "Refresh Now" triggers an immediate poll outside the timer schedule

**First launch (no token):** The panel shows a single "Set up token…" button that opens `PreferencesView` instead of the site list.

**Initial load (token exists, first poll in progress):** The panel shows a loading indicator ("Loading sites…") until `DeployMonitor.isLoading` becomes false. This prevents a blank or empty flash on startup.

---

## Preferences

A separate `Window` scene (`openWindow(id: "preferences")`). `Window` (not `WindowGroup`) is single-instance by design in SwiftUI — calling `openWindow` when it is already open brings the existing window to front rather than opening a second one.

Contents:
- `SecureField` for Netlify personal access token
- "Save" button — writes token to Keychain and triggers an immediate poll
- "Test connection" button — hits `GET /api/v1/user`, shows inline success ("Connected as user@example.com") or failure message without saving
- Token is read/written via `KeychainHelper`, a thin wrapper over `Security.framework`
- Token is never stored in `UserDefaults` or any plist
- Dismissing the window without saving discards any unsaved changes

---

## Notifications

Uses `UserNotifications` framework. Permission is requested **after** the user taps "Save" in Preferences and the subsequent `GET /api/v1/user` call returns a 200 OK — i.e., after the token is confirmed working, not merely non-empty. This ensures the permission prompt appears in context and only when notifications can actually fire.

Notification triggers (fired on deploy state transition):

| Transition | Message |
|---|---|
| New deploy detected (→ building/enqueued) | "sitename is deploying" |
| Deploy succeeded (→ ready) | "sitename deployed successfully" |
| Deploy failed (→ error) | "sitename deploy failed" + action opens Netlify dashboard |
| Deploy cancelled | No notification fired |

Deduplication: each notification is identified by `deploy.id + "-" + transitionName`. The same deploy will never fire the same notification twice.

---

## Error Handling

| Error | Behavior |
|---|---|
| Network error / API failure | Show "⚠ Last refresh failed · 2m ago" row in panel; keep displaying stale data |
| 401 Unauthorized | Show "Token invalid or expired" row with link to Preferences |
| 429 Rate limited | Back off to 5-minute polling for 5 minutes, then resume normal adaptive schedule on next successful response. If a 429 occurs during a `withTaskGroup` parallel deploy fetch, the entire group is cancelled and the backoff applies to all subsequent requests — individual site errors do not get partial updates. |
| No internet | `NWPathMonitor` pauses polling; resumes automatically on reconnect |

---

## Polling Logic

```
On deploy poll tick (10s or 60s):
  1. Fetch latest deploy per site in parallel (withTaskGroup)
  2. Diff against previous snapshot → fire notifications for transitions
  3. Update published state → UI re-renders

On site list refresh (startup + every 10 minutes):
  1. Fetch all site pages (GET /api/v1/sites, paginated)
  2. Update sites list → triggers UI re-render

Timer schedule:
  - Any deploy isActive → use 10s deploy poll timer
  - All deploys settled  → use 60s deploy poll timer
  - Offline             → pause all timers
  - After 429           → use 5-minute timer for 5 minutes, then revert
```

---

## Out of Scope

- Deploy log viewing (opens Netlify dashboard instead)
- OAuth authentication (token only)
- Branch-level filtering
- Multiple Netlify account support
- Windows / Linux support
