# Agent Runway feature comparison

Agent Runway by Matt Maher and Runway by mstallone are different products. This local fork extends the MIT-licensed Runway source with Runway Studio, an original dark dashboard. Agent Runway's licence mechanism and proprietary assets remain untouched. See [acknowledgements](../ACKNOWLEDGEMENTS.md) for the OpenUsage → Runway → Studio source lineage and the separate role of Matt Maher’s product inspiration.

## Evidence and versions

Reviewed on 31 October 2026:

- [Agent Runway website](https://runway.metal-sole.com/), advertising version 2.14.1. The feature list below describes that advertised version; it is not a claim that every feature was exercised locally.
- Installed `Agent Runway.app`: version 2.9.0, bundle `net.maherfamily.AgentRunway`. Its bundled command manual and release notes provide additional feature evidence. The trial banner belongs to this product. Its free tier continues after the Pro trial.
- MIT source: [mstallone/runway](https://github.com/mstallone/runway), revision `d017e2fec25e05319e51296bbecce27ee5c8e1ef`, signed release v0.8.17. Existing features were checked in source and documentation.

## Feature comparison

| Capability | MIT Runway before this change | Local extension or remaining gap |
| --- | --- | --- |
| Weekly and session allowances | Present | Larger gauges and session bars in Studio |
| Model-specific limits | Present | Visible alongside weekly allowance |
| Remaining time and reset dates | Present | Both shown together |
| Allowance pacing and forecast | Present | Explicit forecast labels and stale suppression |
| Weekly glide path | Missing | Shaded observed curve, daily guides and labelled latest point; optional imported local history overlay |
| Earlier windows | Missing | Last observations retained; chart appears as history accumulates |
| Historical week navigation | Missing | Previous/next observed native or imported windows with their recorded curves; no fabricated earlier weeks |
| Menu bar snapshot and rich panel | Present in tracker | Studio now shows provider marks, traffic-light allowance cells and percentages (cached values retain an amber indicator); click opens a Studio-coloured summary ring and compact allowance bars, shaded weekly curves and week navigation with expandable details; Customize opens the full dashboard |
| Display customization | Tracker layout controls | Studio saves menu snapshot style/account, compact sections, dashboard status/health visibility and activity measure/range |
| Refresh diagnostics | Generic errors | Studio shows actual reading freshness, recorded attempts, countdowns, failures and retry deadlines |
| Persistent dashboard | Menu bar panel | Native resizable Studio window available as a secondary action |
| Compact floating monitor | Missing | Per-account monitor with pin and activity ranges added |
| Activity ranges | Today, yesterday, 30 days | Studio adds rolling 24H and 7/14/30-day native activity |
| Hourly activity and fine zoom | Missing | Five-minute/hour/day bins, exact interval selection, zoom to selection, custom dates and reset zoom |
| Model breakdown | Present in hover detail | Expanded ranked list matching the chosen range |
| Project and worktree grouping | Missing | Native-log working directories grouped by Git root and worktree metadata |
| Main-agent and subagent grouping | Missing | Recorded roles with expandable individual-agent/session lists added |
| Cache, input and output split | Totals only in normalized history | Stacked categories and New Only added |
| Claude surface breakdown | Some local sources aggregated | Code/Cowork from known native log paths, unknown-source bucket; Chat and Desktop Chat remain unavailable |
| API-equivalent cost | Present | Larger chart; incomplete pricing labelled |
| Reset-credit expiries | Present, including reminders | Expiry date shown directly |
| Allowance-drop alerts | Limited quota thresholds | Independent Claude/Codex drop rules, one per continuous episode |
| Recovery and early-reset alerts | Missing dedicated events | Fresh-reading transitions, deduplication and local alert history added |
| Morning report | Missing | Configurable daily report, default 07:00 Europe/London, with wake catch-up |
| Provider outage monitoring | Error states only | Official Claude/OpenAI public summaries, five-minute polling, cached/error states and status-page links; provider-wide scope |
| Card image sharing | Present | Studio adds dated text and PNG allowance/activity summaries |
| Chart interval selection | Missing | Hour/day selection with matching totals and project/agent/model lists added |
| Arbitrary-range share image | Missing | Copy/save PNG for exact selected local activity intervals, dates, scope and token categories |
| CLI and local JSON | Present | Existing functionality retained |
| Statusline, wait and MCP | Missing | Read-only `runway-studio` command with statusline, bounded wait and stdio MCP tools |
| Offline and stale states | Present | Studio preserves cache and pauses forecasts |
| Multiple accounts | Present | Studio keeps histories separated by identity |
| Multiple providers and iCloud | Present | Existing tracker retains these; Studio focuses on Claude and Codex |

## Implementation order

The dashboard now supplies a larger visual workspace, observed allowance history and normalized native-log events. Hourly charts and project/agent/model breakdowns share the existing parsers' replay suppression and deduplication. Native events group local activity across accounts; they do not assign token counts to subscription allowance.

Previously missing finer activity zoom, historical allowance navigation, dedicated service-status monitoring and CLI/MCP conveniences are implemented in this local build. Claude Chat/Desktop Chat attribution remains unavailable from the supported local data; it is labelled unknown rather than inferred from subscription allowance. Allowance alerts now have independent controls, persisted deduplication, per-provider rapid-drop rules and a morning report. Preserve account-wide allowance separately from machine-local activity throughout. Missing periods remain gaps. Inferred forecasts must never look like observed history.

## Build arrangement

Runway Studio is a new executable in this repository. It calls the bundled MIT provider engine directly and stores normalized readings in a private Studio cache. Its original helper dependency has been removed; existing Claude Code/Codex auth stores supply credentials. It does not replace Agent Runway or alter its trial.

Studio owns all automatic/manual usage polling through its in-process provider engine. Agent Runway and the original Runway GUI stay closed. A persisted per-family cooldown provides recovery without restarting the competing trackers. Studio records history while running, including with its window closed. Upstream automatic updates do not replace the separate Studio executable, but a future cache-schema change may require updating its adapter. See [Studio](studio.md) for data handling and build instructions.

## Implementation provenance

The implementation uses the MIT Runway source and our additions. Agent Runway's website, visible behaviour, bundled command manual/release notes and identifying binary strings were reference material. We did not access Matt Maher's source code or incorporate his proprietary graphics, icons or licence mechanism. The interface uses our dark dashboard design and independently drawn icon.

This is an independent implementation informed by observed features. It was not a formal separated clean-room process: the same implementer examined those references and wrote the extension. The MIT base retains its licence and attribution.

## Remaining coverage limits

Studio has no original Runway app/helper dependency. Sign-ins are supplied by Claude Code and Codex; Keychain permission restrictions can still require connection attention. Chat/Desktop usage is not attributable from the supported logs. Cross-device/iCloud aggregation is outside the chosen laptop-only scope. Additional provider families and Pi/OpenCode native-event imports are not implemented in Studio. CLI/MCP tools are shipped but client registration is manual. These are distinct from the implemented local Claude/Codex feature set; the comparison does not claim complete product parity or an exhaustive audit of Agent Runway’s latest release.
