# Architecture

## Local Studio extension

`RunwayStudioKit` and the `RunwayStudio` executable provide a separate read-only native dashboard. Studio depends on the Runway module for `LocalActivityReader`, which reuses the incremental Claude/Codex log parsers without constructing credential readers or provider clients. `ActivityContext` retains project/session/agent metadata through parser caches and Codex tail resumes. Separate `studio-claude` and `studio-codex` cache namespaces isolate the richer records from older installed builds. Studio's activity index resolves Git worktrees and builds five-minute/hourly/daily category totals and project/agent/model/source breakdowns for one selected interval. The signed helper’s v9 cache supplies allowance/API-value history. Studio’s single polling coordinator owns availability, retries and provider errors; the original GUI stays closed. Studio's account-stamped allowance archive supplies observed glide paths. See [Studio](studio.md).

Studio's app-owned monitoring task runs independently of window visibility. `StudioAlertEngine` is a pure, Codable evaluator; `StudioAlertCoordinator` persists its state and presents events through an in-app feed and UserNotifications. Delivery is acknowledged separately from generation so errors can retry. Daily scheduling uses a configured IANA time zone and persisted local-day keys. A kernel process lock enforces a single alert evaluator. No provider credential or reset-credit action is used by this path.

A map of Runway's structure for people who work on the code. For what the app does, start with the [behavior docs](README.md).

## Layout

Runway is a SwiftPM package with one shared module and two thin executables. There is no Xcode project. The main executable is a menu-bar app: a SwiftUI interface hosted inside an AppKit status item and panel. The code is grouped by role:

- `App/`: startup and the AppKit bridge (status item, panel, app entry point)
- `Models/`: the value types the rest of the app uses (`MetricLine`, `WidgetData`, descriptors)
- `Providers/`: one folder per provider
- `Stores/`: the mutable state the UI observes
- `Services/`: shared infrastructure (HTTP, the local API, process running)
- `Support/`: small shared helpers (formatting, parsing, animations)
- `Views/`: the SwiftUI screens (dashboard, customize, settings, menu-bar strip)

## Composition root

`AppContainer` wires everything together. At launch it builds the provider list, turns it into a `WidgetRegistry`, creates the stores, starts the refresh loop, and starts the local HTTP API. Everything else receives what it needs from here instead of reaching for globals, which keeps the pieces testable.

The `runway` executable imports the same module. A normal invocation reads `ProviderSnapshotCache` and exits. `--force` builds the `ProviderCatalog` and runs the forced refresh path in `WidgetDataStore` before reading. Providers mark the scalar resources they export through the limits contract. The CLI and `/v1/limits` share one serializer over the same normalized snapshots. The CLI never launches the GUI and never duplicates provider, auth, pricing, or mapping logic.

## The provider pipeline

Each provider is a small module that conforms to `ProviderRuntime`. A refresh flows through three parts:

1. **Auth store**: reads credentials that already exist on the machine (config files, keychain, browser sessions). Runway never asks the user to paste tokens.
2. **Usage client**: calls the provider's API.
3. **Mapper**: turns the response into a `ProviderSnapshot` with typed widget values (`.progress`, `.values`, `.badge`, `.chart`) plus `.text` notices, which reach the local API but do not render as widgets.

Every provider produces the same `MetricLine` shapes, so the UI renders them all the same way. See [Adding a provider](adding-a-provider.md).

### Credential ownership

The app that owns a credential is the only app that changes it. Provider credentials belong to the provider's own tool (Claude Code, the `codex` CLI, the Cursor app, GitHub CLI, and so on). Every credential store reads through the read-only `KeychainReading`. The one Keychain write path is `ClaudeCredentialWriteBack`, used only by the guarded Claude Code renewal described below. Runway's own iCloud-sync device ID lives in Application Support through `RunwayOwnedFileStore`.

Runway never calls the OAuth token endpoints for Codex, Cursor, Copilot, or Muse. Two apps rotating the same login can trip the server's token-reuse protection and sign the user out. When one of those tokens lapses, the card shows a renewal notice naming the owning app. Claude Code is the guarded exception: when a stored token has already been expired for a while, so no live Claude Code session can be mid-rotation, Runway renews it and writes the result back to the same store (Keychain item or `.credentials.json`) so there is one token chain. See [Claude](providers/claude.md). Claude Desktop's login stays read-only. Antigravity refreshes its access token through Google OAuth, which is safe because Google refresh tokens do not rotate, and caches the result in Runway's own file. Grok and Kimi refresh their own file-based logins and write them back to the CLI's credential file.

Automatic refreshes never request secret data from another app's Keychain item. They inspect only non-secret metadata and reuse, for the rest of the process while the item is unchanged, a value loaded by a manual refresh. After launch or a credential change, the user connects the login again through a manual refresh. That waiting state shows a neutral Connect control, not a warning. Only a denied manual read, an expired token, or an unreadable keychain shows a warning. Manual Refresh All queues protected providers and prompts for them one at a time, so approval dialogs never overlap. If a refresh is cancelled while its read is still queued, the read leaves the queue without touching Keychain. Clicking Use on a Codex reset credit may also prompt after every cached credential was rejected. Both paths are user-initiated.

Claude, Codex, Grok, Muse, and pi share `IncrementalJSONLScanner` for local JSONL history. The scanner caches parsed events per file by path, size, and modification time in a versioned Application Support store, partitioned by provider and home. Provider instances that read the same home share one scanner actor, so cards do not parse the same files twice. A session log that only grew since its last parse re-reads just the appended bytes. Records leave the cache as their file modification dates fall out of the history window. The scanner also memoizes aggregation and pricing: when a refresh finds no log changes and the pricing snapshot, history window, and calendar are unchanged, it reuses the previous aggregation.

Muse subscription meters use the Meta developer dashboard’s teams/subscription-quota JSON APIs and the browser cookie reader shared with Sakana Fugu. Muse additionally discovers Firefox profiles and reads their unencrypted cookie databases without Keychain access. Its provider coalesces concurrent reads and enforces a 15-minute floor for both automatic and manual refreshes. Muse CLI credentials and key-minting endpoints are not involved. Local token history uses the existing independent session-log scanner.

## Stores

- `WidgetDataStore`: the latest snapshot per provider, plus refresh and caching. Machine-local cached snapshots are kept separate from rendered snapshots so peer history is never written back out and counted twice.
- `LayoutStore`: which metrics are shown, the provider and metric order, and which metrics are starred for the menu bar.
- `ProviderEnablementStore`: which providers are on or off.
- `ICloudUsageSyncStore`: one CloudKit record per device in the app's private database (history plus a live snapshot for companion apps), a five-minute peer poll, and the visible device and error state. Cloud access is injected for tests.

Refresh runs on a timer in `AppContainer`. Each pass respects the cache, so the app only hits the network once a snapshot has expired.

Reset-credit reminders use one cancellable timer for the next milestone or expiry. Observable data/settings changes, Mac wake, and clock changes trigger re-evaluation and rescheduling; there is no recurring poll. Failed deliveries get a retry after five minutes or at an earlier milestone. `ResetExpiryNotificationMonitor` reads enabled providers' local expiry data through `WidgetDataStore`; it never fetches usage. It rechecks eligibility after asynchronous permission and delivery calls. `ResetExpiryNotificationEvaluator` persists each delivered milestone per provider card and expiry in local UserDefaults. `AppNotifications` checks live authorization for each delivery and lets macOS replace the previous reminder using a stable identifier, preserving the old alert if adding its replacement fails. `NotificationDeliveryClient` makes this system boundary injectable for tests. The loop runs with the popover closed and is cancelled when the container is released. macOS controls persistent alert style; see [Notifications](settings.md#notifications).

To preview a reset notification, build with `CONFIG=debug ./script/build_and_run.sh build`, then launch with `open -n dist/Runway.app --args --preview-reset-notification`. This debug-only action sends a labeled sample through the normal notification path without changing preferences or real-credit history.

Reminder identities use whole-second expiry timestamps to match the snapshot cache's precision across restarts. Credits sharing that timestamp form one group. A changed count withdraws the old alert while retaining its milestone history. New alerts wait for a successful provider refresh each launch (a wait-notice snapshot, such as Claude's rate limit, does not count); cached credits only retain existing reminders until revalidation. Keys use the metric's card ID and the existing launch-resolved account identity, when known. Moving or resolving an account can start new reminder history; the reminder loop does not discover or migrate accounts.

Providers with spend tiles carry a history scope beside their export descriptors. Machine-local sources can be summed across device records. Account-wide sources such as Cursor cannot. `WidgetDataStore` re-renders only the spend rows from the union and leaves quota and error state local.

## The AppKit bridge

Runway shows its content in a custom key-capable `NSPanel` instead of an `NSPopover`. A popover's window is only key while the whole app is active, and activating a menu-bar app is asynchronous and unreliable on recent macOS, so a popover cannot receive keystrokes until a second click. A non-activating `NSPanel` with `canBecomeKey` set to true takes key focus the instant it opens. `App/` owns that AppKit layer and hosts the SwiftUI views inside it.

Settings is an ordinary preferences-style window (`App/SettingsWindowController.swift`), not a popover screen. The controller creates it on first open, mounts only the active tab's SwiftUI pane, and tears it down on close.

## Platform support

Runway runs on macOS 15 (Sequoia) and later. It is built against the latest SDK and back-deploys: on macOS 26 (Tahoe) it uses the system's Liquid Glass controls, and on macOS 15 it uses the standard controls with the same behavior. All of those version checks live in `Support/LiquidGlassFallbacks.swift`, so the views have no `#available` checks.

The release build (`script/release.sh`) is a universal binary (arm64 and x86_64). The dev build (`script/build_and_run.sh`) is host-arch only to keep compile time down.

## Local HTTP API

A small loopback server exposes the current usage as JSON on `127.0.0.1:6736`. See [Local HTTP API](local-http-api.md).

### Studio extensions

Studio keeps observed weekly histories separated by account stamp and reset window, including historical navigation. Local event analysis supports exact selected intervals, five-minute bins, viewport zoom and PNG summaries. Known native Claude log paths identify Code or Cowork before flattening; custom/conflicting provenance remains unknown. A separate schema-3 Studio cache preserves this metadata without replacing the signed tracker's cache.

`StudioServiceStatusMonitor` polls official public Claude/OpenAI summaries every five minutes through an ephemeral session without stored credentials or cookies. These vendor-wide statuses are separate from account allowances and alert recovery events. The app bundles the independent `runway-studio` executable: it reads Studio’s normalized heartbeat and native local history for statusline, bounded wait and read-only newline-delimited stdio MCP tools. Existing Studio state is authoritative; only installations without a Studio state file use the legacy cache/loopback fallback. Cached metrics and incomplete prices remain labelled. No MCP client registration occurs during installation.

### Explicit Studio refresh

Studio background cache reads remain passive. Automatic and explicit provider checks delegate to the installed signed Runway CLI helper, with family deduplication, persisted wait-policy checks, bounded output, timeout/cancellation and timestamp-based confirmation. It does not construct a second provider/auth engine. Confirmation is tied to the exact persisted reading timestamp, including delayed cache publication, and never overrides a provider wait or login-required state.

### Single polling owner

`StudioPollingCoordinator` serializes automatic and manual helper requests behind `polling.lock`, persists `StudioPollState` before every attempt and observes one schedule per provider family. Success schedules five minutes; failures use 15/30/60/120 minutes with any known provider minimum retained. Cached waits seed only once and expire, allowing automatic recovery. Competing tracker GUIs pause Studio before new requests. Snapshot publication and local activity run on a separate 30-second heartbeat; CLI/MCP consume `latest-state.json` without provider requests. Background and manual flows never open the old GUI. Studio’s helper registry terminates child requests synchronously on normal app shutdown.

### Studio display preferences

`StudioDisplayStore` persists local UI choices separately from alerts and polling. Dashboard, compact panel and status-item rendering observe these preferences. Menu account selection resolves one available card per family, with the existing default-account fallback. Display controls never change provider enablement or reset scheduler state. Refresh-health cards observe coordinator records and real cached timestamps without invoking checks.
