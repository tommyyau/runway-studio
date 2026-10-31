# Runway Studio

Runway Studio is the local fork's native menu bar companion and dark dashboard for Claude and Codex. Studio is the only running tracker. It invokes the installed signed Runway command-line helper for short usage checks; the Runway GUI and Agent Runway stay closed. It does not require a licence key or trial.

## Start and build

Open `/Applications/Runway Studio.app` only. Keep Agent Runway and the original Runway GUI closed. The installed Runway bundle supplies its signed helper; it does not need to run as an app.

```sh
bash script/build_studio.sh
open "dist/Runway Studio.app"
```

The product builds with `swift build -c release --product RunwayStudio`; the packaging script creates and ad-hoc signs a standalone app. It links the existing Runway module to reuse its log parsers and embeds the existing Sparkle framework required by that module. Studio does not initialize an updater. It does not need a developer signing certificate to request Keychain access: Studio never requests Keychain access.

Future builds of the tracker source include **Open Studio Dashboard** in the gear menu. The already-installed signed upstream tracker has its original menu, so open Studio from Applications there.

## Menu bar snapshot

Studio launches into the menu bar without opening the dashboard. Its Claude and Codex marks show five allowance cells and percentages remaining. When both windows are available, the upper percentage is session allowance and the lower percentage is weekly allowance. Cells show weekly allowance, falling back to session allowance when weekly is absent or awaiting reset. A nonzero balance keeps at least one cell; all five cells mean 100%. Each provider uses its default account, or its first available account, without adding account quotas together. Menu bar cells use allowance status colours for both providers: green above 30% remaining, orange above 10% through 30%, and red at 10% or less. At zero, the empty cells retain a faint red tint. The popover keeps Studio’s mint/violet provider identity colours.

Click the snapshot to open the compact panel in Studio colours: mint for Claude and violet for Codex. The summary ring switches between estimated API value and tokens, with Today, Yesterday and 30 Days tabs. It reads existing tracker history once per provider, so accounts with shared local-log history are not added twice. Missing estimates stay unavailable and incomplete pricing is labelled. API value is an estimate, not subscription billing.

Provider cards show session, weekly and model allowance bars with reset countdowns. Their chevrons reveal pacing, reset credits, expiry and copyable summaries. Stale and error notices stay visible while collapsed. Hourly local activity remains below the cards. **Open Dashboard** opens the full Studio dashboard, with projects, agents, models, chart ranges and monitors. The footer **Customize…** opens the dashboard with display controls. The footer also opens **Alerts & Report** or quits Studio. The panel scrolls on smaller screens; clicking outside dismisses it. Cached readings retain their last known menu bar percentages and cells, with a small amber dot beside the provider mark and a cached label in the accessible summary. The panel keeps its cached notice; forecasts and alerts still require fresh readings. An elapsed reset waits for a fresh provider confirmation.

Closing any Studio window keeps menu bar tracking running even when alerts are disabled. **Quit** stops monitoring. `--show-menu` opens the compact panel at launch for review; normal launches leave only the snapshot visible.

## Reading the dashboard

The large gauge shows account-wide weekly allowance remaining. Session and model-specific limits are separate. Forecasts assume the average pace so far continues; they pause when the tracker is unreachable, a provider reports an error, or a reading is older than six minutes. A reset time passing reads **Awaiting Reset** until the provider confirms a new window.

The glide path starts with actual observed readings. Its dashed diagonal is an even-pace reference, not a measured curve. A gap over 20 minutes breaks the observed line. Earlier windows show last-observed use; readings well before renewal only establish a lower bound. No past history is invented.

Token activity defaults to the last **24H**, a rolling 24-hour window with hourly bars. **7D**, **14D** and **30D** cover local calendar days, including today. Each provider card can switch between **5 Minutes**, **Hourly** and **Daily**. Drag across the chart to select whole hours or days: totals, category counts and every breakdown use that same interval. **Clear Selection** returns to the full range. Daylight-saving transitions retain distinct absolute hours, including repeated local clock hours.

**By Project** groups working directories by their Git root. Git worktrees resolve through their `.git` pointer and `commondir` file to the main repository. When no Git root exists, folders under `~/repos/<project>/` are grouped by that workspace project; other directories keep their recorded path. Deleted worktrees whose metadata is gone cannot be folded reliably and retain their path. Missing working directories are **Unknown Project**. No repository commands are executed.

**By Agent** separates recorded main sessions, subagents and unknown roles. Expand a role for individual agents/sessions, with their project names. Forked main sessions remain main sessions. **By Model** shows the recorded models for the same interval. Token charts include unpriced models; they do not require a pricing entry to count usage.

Stacked bars separate cached reads, new input, output and any unclassified remainder. Claude cache writes belong to new input. Codex cached input is subtracted from its inclusive input count, and reasoning is not added again to output. **New Only** includes new input and output, excluding cached reads and unclassified tokens. Unknown data is never guessed into a category.

These views read native Claude Code/Cowork and Codex logs on this Mac, without iCloud aggregation. They group activity by provider across accounts: historical logs cannot reliably name a subscription account. Blank hours mean no matching log records, not proof of no use elsewhere. Pi and OpenCode imports remain in the tracker's daily totals but are outside this native-event view.

**API Value** remains the tracker's daily cache view, scoped by account, with Today/7/14/30-day ranges and model breakdowns. It is an estimated API-rate comparison, not subscription spend; missing prices are excluded and flagged when the cache supplies unknown-model metadata. Because its source coverage and pricing filters differ, its token coverage can differ from the native-event view.

The **Monitor** menu opens a compact provider window with account allowance and native local activity. It defaults to 24H with hourly bars; 7D and 30D use daily bars. Activity is grouped across accounts even when the allowance card names a particular account. Its pin toggles whether the window stays above other apps. Each account has its own monitor, and its placement is remembered.

**Copy Allowance Summary** copies only the provider name, weekly percentage, reset date and reading time. It does not include model/activity breakdowns.

## Local data and dependencies

Studio reads enabled account IDs and normalized snapshots directly from the saved preferences; polling errors come from its own coordinator. It reads `~/Library/Preferences/com.mattstallone.runway.plist`, key `runway.providerSnapshots.v9`, for the normalized daily history. That cache format is internal and versioned. Studio reports a visible error if it cannot decode it.

`LocalActivityReader` reuses the existing incremental Claude/Codex parsers without constructing any credential store or provider client. The parsers retain usage timestamps, token categories, model, working directory, session and agent metadata. Claude message deduplication and Codex fork replay/stale-counter suppression are shared with the original tracker. Only the first Codex session header assigns identity; replayed parent headers cannot overwrite it. Metadata survives append-only tail resumes.

The `studio-claude` and `studio-codex` namespaces under `~/Library/Application Support/Runway/log-scan-cache/` hold private versioned parser caches. They contain normalized counts and local project/session identifiers, not prompt or response text. They are separate from the signed tracker's older cache schema. The first scan parses existing recent files; later scans read appended bytes. The activity view filters events to the most recent 30 calendar days. File caches can retain older events from a still-active log; original log files are not modified.

The cache's account identity stamp separates histories when accounts switch. Snapshots without an identity stamp can display current data but cannot create a historical curve. Failed, stale or login-required readings do not become new history. Re-reading a cached timestamp does not add another point.

`~/Library/Application Support/RunwayStudio/allowance-history.json` retains up to 63 days of observed weekly readings. It contains account stamps, percentages and window timestamps; no login tokens. The directory is private and the file is written atomically with owner-only permissions. A corrupt history file is preserved and an error is shown rather than overwriting it.

Studio updates local activity and its status heartbeat every 30 seconds while running. Its single provider scheduler invokes the signed helper only when a family is due. Activity indexing runs outside the main actor, so allowance cards remain usable during a cold scan. Native activity can continue updating if the menu bar tracker is offline; account allowances remain labelled cached. Background Studio polling makes no model-usage, update-server or analytics requests. Explicit manual refresh delegates Claude/Codex usage requests to the installed signed Runway helper; Studio itself does not read credentials. It checks the public Claude and OpenAI status summary endpoints every five minutes without credentials or cookies; these summaries describe provider-wide service health, not an individual account or Codex-specific availability. It does not refresh credentials, consume reset credits, change the tracker's settings or modify Agent Runway.

## Alerts and morning report

Open **Alerts & Report** in the dashboard header or the compact menu bar panel. Alerts and the daily morning report are enabled initially for this requested feature. macOS notification permission is requested on first launch. Each alert has its own switch. Rapid-drop rules and spare-allowance notices start off; the other allowance alerts start on. The existing Runway app's notification preferences are unchanged.

The morning report defaults to **07:00 Europe/London**, following GMT/BST automatically. Change its time in the alert window and use **Preview Morning Report** to inspect the current content without sending a notification. It includes each account's weekly allowance, renewal, relevant forecast and next reset-credit expiry. Unavailable readings are labelled unavailable instead of repeating their old percentage as current.

The scheduler checks every 30 seconds and on wake. A missed morning report can arrive during the four hours after its configured time; later reports are skipped. One daily delivery key survives restarts and time changes. Studio must be running and the Mac awake, or wake within the catch-up period. Closing the dashboard keeps Studio running with its usage snapshot in the menu bar. **Quit Studio** stops monitoring. **Open Studio At Login** is optional and starts off; macOS may require approval in Login Items. Studio owns allowance polling; keep the other tracker apps closed.

Allowance rules:

- **Low allowance:** 10% or less in a live weekly or session window, once per reported window.
- **Early runout:** the average pace projects exhaustion at least 12 hours before renewal, once per weekly window. Tiny/coarse readings below 5% used do not produce a forecast.
- **Recovery:** a fresh reading confirms a previously exhausted limit is available again. A missing metric is not proof of recovery. Restored usage readings after at least two minutes of observed unavailability are labelled as readings restored, not service health.
- **Reset changes:** an observed early weekly reset or an increase in the number of reset credits. An unknown previous credit count is not treated as zero.
- **Credit expiry:** a known available credit's expiry, at the 24-hour and 2-hour stages. Credits with the same expiry share a reminder. Studio never uses a credit.
- **Spare allowance:** at least 30% projected unused, renewal within 48 hours, and London time between 08:00 and 20:00; once per weekly window.
- **Rapid drop:** independent Claude and Codex rules, configurable from 1–100 percentage points over 5–120 minutes. One alert covers a continuous drop; a full configured interval without a further decrease rearms it. These use account-wide allowance readings, not token-to-quota guesses.

A first reading establishes a baseline instead of inventing a change. Account stamps separate different accounts. Stale or failed readings never create allowance alerts. One event is chosen per account/read, prioritizing recovery, reset changes and low allowance over forecasts. A ten-minute quiet period limits other alerts; recovery and low allowance bypass it. Forecasts are suppressed when low-allowance warnings already apply.

**Recent Alerts** retains the latest 100 events locally, with the latest 20 displayed. Without macOS permission, events still reach this in-app history and are not replayed as old system banners after permission is granted. If macOS accepts delivery, the event is acknowledged; delivery errors remain visible and retry for up to 30 minutes while the event still applies. Focus and macOS notification style can suppress banners even when submission succeeds. **Send Test Notification** submits a clearly labelled test without changing real allowance history.

`~/Library/Application Support/RunwayStudio/alert-state.json` stores preferences, per-account baselines, delivery keys, pending retries and recent alerts. It contains usage readings and timestamps, no credentials. It is written atomically with owner-only permissions. Corrupt state is preserved and alerts are paused rather than silently resetting deduplication. A process lock prevents two live Studio instances from sending duplicate alerts. Rendering previews suppress notifications entirely.

## Validation

```sh
swift test -c release --filter RunwayStudioTests
"dist/Runway Studio.app/Contents/MacOS/RunwayStudio" --snapshot /tmp/runway-studio.png
```

The export captures the native dashboard for layout review. Tests cover account isolation, early-reset separation, missing history, stale-read rejection, coarse-percent forecast safeguards, worktree resolution, session metadata, copied-event deduplication, tail resumes, token category totals, range aggregation and repeated DST hours. Scanner regression coverage runs with:

```sh
swift test -c release --filter 'ActivityMetadataTests|RunwayStudioTests|ClaudeLogUsageScannerTests|CodexLogUsageScannerTests'
```

On 31 October 2026, all 107 focused tests passed. The installed app was also checked with live local logs: agent-role expansion, individual subagent rows, New Only totals, persistent hour selection, clearing the selection, and the monitor's 24H hourly chart. Selecting an interval updates the visible totals and project list together. Native rendering was reviewed for both provider charts.

Alert validation adds clock-driven tests for baselines, account changes, stale data, recovery, early resets, credit-expiry stages, continuous-drop rearming, retry acknowledgement, morning timing/catch-up, BST, restart deduplication and the single-instance lock. No test changes the Mac's clock or generates a fake real-usage warning.

The Studio suite now passes 45 tests. Native acceptance on 31 October 2026 confirmed the saved 07:00 Europe/London schedule, live report preview, enabled macOS permission retained across an update, and a labelled test present in Notification Centre. Studio remained running after window closure, and a duplicate executable launch exited while the original process remained. The next real 07:00 report has not yet occurred; its timing is covered by simulated-clock tests.

### Menu bar restoration validation

The release app was built, ad-hoc signature verified and installed at `/Applications/Runway Studio.app`. All 50 Studio tests passed, including five menu snapshot regressions covering separate accounts, provider ordering, stale/failed readings, elapsed reset windows, session-only fallback and cell boundaries. Native UI review confirmed the populated compact panel and its Dashboard action; closing the dashboard left the process alive, and reopening Studio showed the compact panel. The menu bar item itself could not be clicked through this automation surface, which exposes app windows but not Studio's status button; its rendering and target/action wiring were reviewed in source.

### Compact layout and dashboard shortcut validation

The Studio-coloured summary ring, date tabs and allowance-bar layout were built, signature verified and installed. Native UI review confirmed the populated ring, Today range recalculation, provider detail expansion and Customize opening the full Studio dashboard. All 54 Studio tests passed, including four summary tests covering calendar dates across DST, shared account histories, missing estimates and unknown-model partial pricing.

### Menu bar cached-value and status-colour fix

Cached readings previously replaced all menu bar percentages with dashes. They now retain unexpired last-known allowance cells and percentages with an amber cache indicator. Elapsed reset windows still wait for confirmation. Traffic-light thresholds are covered by regression tests, including unavailable values and the 10%/30% boundaries. All 55 Studio tests passed. The signed tracker was restarted after its local API was found offline; the installed Studio panel then confirmed connected, fresh provider readings. The release build and installed signature were verified.

## Expanded history, zoom and sharing

The weekly glide path has previous/next controls for observed windows belonging to the same account. Current allowance stays labelled current; the chart and exported summary carry the selected historical dates. Missing weeks remain absent. Completed-window summaries coalesce provider reset-time rounding.

Local activity supports five-minute, hourly and daily bins. Dragging selects exact timestamps for totals and breakdowns while the surrounding whole bins remain visible. **Zoom To Selection** changes the viewport; **Reset Zoom** returns to the chosen range. **Choose Interval…** accepts date/time boundaries within the last 30 days of indexed logs. The image share menu copies or saves PNG summaries for the selected interval; the image includes dates, measurement scope and the matching bars. Daily API value and allowance charts also support PNG summaries. Missing daily records remain unavailable rather than zero.

**By Source** groups Claude Code and Cowork records using known native log paths. Records from custom or conflicting paths remain unknown. Claude Chat and Desktop Chat are not observed by this local index; no zero-use claim is made for them. The Studio-only Claude parse cache uses schema 3 to rebuild path attribution; the signed tracker's cache remains separate.

Dashboard service-status cards show vendor-wide public Claude and OpenAI summaries. Failed requests retain a labelled stale result; absence of a successful result reads unavailable. Public status does not prove the state of the user's account. Status data is separate from allowance alerts.

## Developer tools

The app bundles `runway-studio`. Run `bash script/install_studio_tools.sh` after installing the app to create a safe link in `~/.local/bin`; an unrelated existing file is preserved. It supplies statusline, bounded wait and read-only stdio MCP tools. See [tools and MCP setup](studio-tools.md). Installing the executable does not register it with a client or change Claude/Codex settings.

### Parallel Terra implementation validation

Three explicitly selected GPT-6.1 Terra workers implemented the history/zoom/sharing, sources/status and developer-tools areas. Cross-review caught completed-window rounding duplicates, missing daily records shown as zero, local-history account scope and cached/live tool provenance; these were corrected before acceptance. This is evidence of a successful scoped implementation trial, not a controlled Terra-versus-Sol benchmark or measured subscription-cost comparison.

The focused regression run passed 157 tests: 88 scanner/metadata tests, 66 Studio tests and 3 tool tests. Native acceptance confirmed public service-status rendering, five-minute bins, By Source grouping, applying a custom viewport, selecting an exact interval, and zooming with the same 158.4M-token total. A PNG was saved through the native save panel and visually reviewed. Installed-tool smoke tests verified JSON statusline, MCP initialize/list/call/ping (clean stdout), timeout exit 1 and invalid-input exit 2. Historical navigation is covered with account-isolated synthetic recorded windows; this new installation has no earlier observed weeks to demonstrate locally. Claude Chat/Desktop Chat remains unavailable. MCP is shipped but not automatically registered with clients. A final release rebuild, signature verification and installation include the export scope/tick-label polish.

## Manual refresh

The popover and dashboard refresh buttons now invoke the signed `/Applications/Runway.app/Contents/Helpers/runway` helper, instead of merely reloading stored data. The header shows progress and reports whether a newer provider reading actually arrived. The helper runs asynchronously, is cancelled when Studio quits, times out after 45 seconds, and writes bounded output to private temporary files. Its reported provider timestamp is preserved; a reload timestamp is never substituted for it.

The signed CLI treats a default `claude` or `codex` ID as a family selector. Studio deduplicates those calls and never requests other provider families. A cached `warningAction: wait` seeds a finite cooldown. Automatic and manual requests use the same persisted family schedule, and manual refresh never bypasses it. After the cooldown, Studio can retry even while the old warning remains cached. Other families keep their own schedules. Backoff notices no longer show a frozen `Retrying in ~now` countdown; Studio shows its saved next-attempt time. Studio never clears a provider warning or changes a cached reading to fresh merely because the button was clicked. Missing helper, errors, partial results and no-new-reading cases remain visible.

## Activity chart presentation

Observed bars are inset with visible gaps and rounded corners. Cache reads use a muted provider tint, new input a vivid provider accent and output warm amber; totals and stacked proportions remain unchanged. Hovering shows the observed bin and its category breakdown. Selection and zoom continue using exact timestamps. Empty intervals remain unobserved gaps, not fabricated zero records. PNG activity summaries use matching rounded accent bars.

### App Management permission

Studio's usage tracking and manual refresh do not require App Management access. It has no runtime app-update or uninstall command and does not initialize Sparkle's updater. The refresh helper is executed in place; it is not copied, replaced or deleted. Its only cleanup removes the UUID-named private temporary output directory it created. Build/install scripts replace the Studio app during development; these are separate from Studio's running tracking features.

On 31 October, a targeted macOS log review showed System Settings enabling `local.runway.studio` App Management access at 19:11:38. The available evidence does not establish what caused any earlier prompt; no causal claim is made about the helper or installer. The grant is unnecessary and should be off. The permission database was not accessed after macOS denied the read.

### Refresh, chart and permission acceptance

All 78 focused tests passed (75 Studio, 3 tools), including helper response/timeout fixtures, family wait policy, timestamp handoff, and bar clipping/spacing. The signed release was installed and verified. Native review confirmed separate rounded, provider-tinted stacked bars. A manual provider refresh completed with App Management disabled after quitting/reopening Studio: Codex received a newer reading and the header reported `Updated 1 provider reading. Provider retry pending for Claude.` The Claude rate-limit warning remained labelled cached, without the frozen countdown. System Settings was checked again afterward and Studio App Management remained off. The original cause of the earlier grant remains unestablished.

### Respecting tracker closure

Studio never opens Runway automatically, including during manual refresh. Only the explicit **Runway Setup…** button opens that application. Studio checks providers through the signed command-line helper while the Runway GUI stays closed; cached readings remain visible during scheduled backoff.

## Studio-only polling and recovery

Agent Runway and the Runway GUI must stay closed. Studio is the sole polling owner and uses the existing signed helper in place. A kernel polling lock prevents a second Studio coordinator, and a serialized coordinator prevents manual/automatic overlap. If another tracker GUI is detected before a check, Studio pauses its own checks and displays a conflict notice. This is a local coordination safeguard, not control over other devices or independently launched third-party software.

Successful checks schedule the next one in five minutes. Failures back off for 15, 30, 60 and then up to 120 minutes. A provider retry duration conveyed by the helper's rounded warning is retained as a minimum, even if longer. A previously cached wait starts one finite 15-minute cooldown rather than blocking recovery forever. Schedule state is saved before launching a helper, so a crash/restart reserves 15 minutes for an interrupted attempt. A successful fresh reading clears the failure count. Manual refresh shares these limits and displays the next eligible check instead of forcing requests.

`polling-state.json` contains the private persisted schedule. Corrupt or unreadable state pauses polling and preserves the file. `latest-state.json` is a private normalized status heartbeat for CLI/MCP readers; it is refreshed every 30 seconds independently of provider requests. Tools use it without making provider calls or requiring the original GUI's local HTTP server. Existing malformed or expired state fails closed. Closing Studio cancels running tasks and synchronously terminates its registered helper process. No administrator privileges or App Management access are required.

The **Runway Setup…** button is an explicit account-setup action. It may open the original app temporarily; Studio detects that competing tracker and pauses until it is closed again. There is no automatic reopening of either old tracker.

Local verification on 31 October 2026: 88 Studio tests and six tools tests passed. The installed Studio app launched with both other tracker GUIs closed, a fresh Codex reading, and Claude awaiting its persisted retry deadline. The CLI reported `studio_state` as its source. Late cache publication is reconciled without another provider request or changing the original reading timestamp. Live Claude recovery remains dependent on the provider accepting the scheduled check.

## Display customization and refresh health

**Customize…** opens saved display controls in the dashboard. Choose bars with percentages, bars alone or percentages alone in the menu bar. Where several cards exist for a family, select the account shown in the menu bar; a removed account falls back to the default or first available card. Allowances are never summed across accounts. Current bars and percentages remain the default.

The summary ring, local-activity sparklines and model allowance bars in the compact panel can be hidden independently. Dashboard controls can hide public status and refresh-health cards, and retain the chosen activity range and Tokens/API Value measure across restarts. These choices do not change provider enablement, polling, alert rules or source tracker preferences. Settings live in owner-only `display-preferences.json`; unreadable data is preserved with a visible error.

Refresh-health cards show each account’s actual provider timestamp and freshness, the latest recorded check, next eligible check with a live countdown, failure count and provider retry deadline when available. A seeded check timestamp is labelled accordingly. These cards only observe the existing coordinator and never trigger requests. A permitted deadline is not a guarantee that a check has completed: Studio still needs its scheduler, readable account data and no competing tracker.

Customization acceptance on 31 October 2026: 91 Studio tests and six tools tests passed. The installed signature was verified. Native review confirmed the real Customize sheet, a Bars Only change persisted to disk, restoration to Bars & Percentages, and both refresh-health cards displaying fresh provider timestamps and live countdowns. The existing Claude/Codex polling deadlines remained active. Multi-account menu selection is covered by fixtures; this Mac currently has one visible card per family.

## Source backup and restore

The private GitHub repository `tommyyau/runway-studio` stores Studio’s source, tests, documentation, build scripts and the MIT Runway source history. The `upstream` remote identifies `mstallone/runway`; `origin` identifies the private Studio repository. The source does not include Agent Runway’s app bundle or proprietary code.

To restore, clone the private repository, install Xcode with Swift 6.2 or newer, install the signed Runway app used for account setup and the helper, then follow the build instructions above. Accounts must be connected locally. Build products, signing keys, credentials, native session logs and `~/Library/Application Support/RunwayStudio/` runtime files are excluded. Restoring source alone does not restore recorded history or account authentication.

GitHub Actions are disabled for this source-backup repository. Upstream publishing/release workflows remain in the source as reference and are not configured as Studio deployment. No release, tag, public website or automatic update feed is published by the backup.

Source-backup verification: the combined Studio/tools/native-scanner regression run passed 185 tests (91 Studio, six tools and 88 scanner/metadata tests). Staged source was checked for common credential patterns and generated runtime files before the initial private push.
