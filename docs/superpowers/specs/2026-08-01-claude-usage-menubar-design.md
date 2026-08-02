# Claude Usage Menu-Bar App — Design

**Date:** 2026-08-01
**Status:** Approved

## Purpose

A macOS menu-bar app that shows, near-real-time, how much of the user's Claude
subscription quota is left — the 5-hour session window, the weekly all-models
window, and the model-scoped (Fable) weekly window — so the user doesn't have to
keep running `/usage` in Claude Code. Clicking the bar item opens a detail panel
with limit gauges, reset countdowns, a 7-day token-consumption chart, and an
estimated API-price cost equivalent.

v1 is Claude-only. A provider abstraction leaves room to add OpenAI/Codex later.

## Data sources (both verified working on this machine)

### Live quota
- Endpoint: `GET https://api.anthropic.com/api/oauth/usage`
  - Headers: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`
- Token: **supplied by the user**, not harvested. On first run the app asks the
  user to run `claude setup-token` (Claude Code's official long-lived-token
  command) and paste the result. The token is validated against the endpoint
  before being stored in the app's *own* Keychain item (service `UsageBar`).
- **The app never reads credentials belonging to other applications.** This was
  a deliberate change from an earlier design that read Claude Code's Keychain
  entry: the project is intended for public release, and reading another app's
  stored secrets is not something to ship to strangers. A browser OAuth flow was
  also considered and rejected — no public OAuth client registration exists for
  Anthropic subscriptions, so it would require reusing Claude Code's client ID,
  which would show users a consent screen naming an app that isn't this one.
- **Read-only**: the app never refreshes or rotates the token. If it expires or
  is revoked, the panel prompts the user to reconnect.
- Parse the `limits` array — the authoritative window list — not the fixed
  top-level fields. Each entry: `kind` (`session` / `weekly_all` /
  `weekly_scoped`), `percent` (0–100), `resets_at` (ISO 8601),
  `severity`, and optional `scope.model.display_name` (e.g. "Fable").
  Parsing is generic over the array so new/renamed windows appear without code
  changes.

### 7-day history + cost
- Scan `~/.claude/projects/**/*.jsonl`. Each assistant message line carries
  `message.usage` (input_tokens, output_tokens, cache_creation_input_tokens,
  cache_read_input_tokens) plus `message.model` and a `timestamp`.
- Aggregate tokens per calendar day (local time) per model for the trailing
  7 days.
- Cost equivalent = tokens × a small built-in API pricing table (per-model
  input / output / cache-write / cache-read rates). This is an estimate of what
  the usage would cost at API prices, not a bill.
- Dedupe by (`message.id`, `requestId`) pairs where present, since JSONL lines
  can repeat usage for streamed chunks.

## App shape

- Swift Package (SwiftPM only, no Xcode project; builds with `swift build`),
  Swift 5.9+, macOS 14+.
- SwiftUI for the panel; AppKit `NSStatusItem` for the bar item.
- Menu-bar only: `LSUIElement` (no Dock icon).
- `make app` bundles the built binary into `UsageBar.app` (Info.plist with
  LSUIElement, unsigned/ad-hoc) suitable for /Applications.
- "Launch at login" toggle in the panel via `SMAppService.mainApp`.

## Components

| Component | Responsibility |
|---|---|
| `TokenStore` | Save/load/delete the user-supplied token in UsageBar's own Keychain item. |
| `SetupView` | First-run screen: instructions, paste field, live validation. |
| `ClaudeUsageClient` | Fetch + decode the usage endpoint into `[LimitWindow]`. |
| `UsageHistoryScanner` | Scan/aggregate JSONL logs into per-day, per-model token totals + cost. Incremental: caches per-file byte offsets and only reads appended data. |
| `RefreshScheduler` | Adaptive polling + FSEvents watcher (below). |
| `StatusItemController` | Renders bar text `✳ 5h 88% · wk 75% · F 81%`; text color shifts orange at ≥75%, red at ≥90% (worst window governs). |
| `UsagePanelView` (SwiftUI) | Three gauge bars with "resets in 2h 14m" countdowns, 7-day stacked-by-model bar chart (Swift Charts), weekly cost line, launch-at-login toggle, quit button. |
| `UsageProvider` protocol | Boundary so a Codex provider can be added later without restructuring. |

## Refresh behavior (near-real-time)

- **FSEvents watcher** on `~/.claude/projects`: any write (Claude Code logging a
  message) triggers a quota refresh within ~1–2s, debounced.
- **Active mode**: if activity was seen in the last 5 minutes or any window is
  ≥70%, poll every 10s.
- **Idle mode**: otherwise poll every 60s.
- Opening the popover triggers an immediate refresh; reset countdowns tick every
  second locally regardless of polling.
- History rescan happens lazily: on popover open and at most every 5 minutes,
  incremental via cached file offsets.

## Error handling

- No token stored → bar shows `✳ Connect`; panel shows the setup screen.
- HTTP 401 → keep last data, and prompt the user to reconnect with a fresh
  `claude setup-token` (the app cannot refresh the token itself).
- Network failure → keep last data, show last-updated timestamp as stale.
- Malformed/unknown `limits` entries are skipped, never fatal.

## Testing

- Unit tests (pure logic, no network/UI): usage JSON decoding (including null
  scoped windows and unknown kinds), JSONL day-bucketing and dedupe, pricing
  math, bar-text formatting and threshold colors.
- UI and end-to-end verified by running the app locally.

## Out of scope (v1)

- OpenAI/Codex provider (protocol slot exists; not implemented).
- Notifications/alerts on threshold crossing.
- Per-project breakdown.
- Token refresh / any credential mutation.
- Code signing, notarization, auto-update, distribution beyond this Mac.
