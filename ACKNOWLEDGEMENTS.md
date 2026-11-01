# Acknowledgements

Runway Studio exists because of the open-source work it builds on and the product ideas that informed it. These contributions have different roles.

## Source-code lineage

**[OpenUsage](https://github.com/robinebers/openusage), by Robin Ebers and contributors**, is the original MIT project in this lineage. Its existing copyright notice remains in [LICENSE](LICENSE).

**[Runway](https://github.com/mstallone/runway), by Matt Stallone and contributors**, is Studio’s direct fork source. Runway is itself derived from OpenUsage. Studio started from revision [`d017e2f`](https://github.com/mstallone/runway/commit/d017e2fec25e05319e51296bbecce27ee5c8e1ef).

Studio retains and extends the MIT foundation: native Swift/AppKit/SwiftUI infrastructure, provider auth stores and usage clients, account handling, normalized metrics, pricing, and incremental local-log parsers. The upstream Git history and licence are retained. A different interface does not erase that source-code debt.

## Studio’s additions

The `RunwayStudio`, `RunwayStudioKit` and `RunwayStudioTools` targets introduce Studio’s interface and workflow: a mint/violet dashboard, traffic-light menu snapshot, a rich dropdown with weekly curves, floating monitors, detailed local activity analysis, history navigation, image summaries, alerts and morning reports, display controls, refresh diagnostics and read-only CLI/MCP tools.

Studio owns its polling and persisted backoff, calling the bundled MIT provider engine directly. The earlier dependency on the installed Runway app/helper has been removed. Shared parser extensions retain project, worktree, source, session and agent metadata.

## Product inspiration

**[Agent Runway](https://runway.metal-sole.com/), by Matt Maher**, is a different product from Matt Stallone’s Runway. Its visible behaviour, publicly advertised features, bundled command documentation and release notes informed our feature comparison and several interaction choices, including weekly allowance presentation, rich menu-bar information and reporting ideas.

Agent Runway was not a source-code fork or library dependency. We did not obtain Matt Maher’s source code or incorporate his proprietary graphics, icons or licence mechanism. Studio’s icon and interface were implemented separately. This was an independent implementation informed by observed features, not a formally separated clean-room process.

The local history importer reads the user’s own saved allowance data. It does not read entitlement information or alter Agent Runway. Imported source-account identity stays separate from Studio’s identity and is labelled accordingly.

## Dependencies and attribution

The project retains its declared dependencies, including [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) and [Sparkle](https://github.com/sparkle-project/Sparkle), and their respective licences. Studio links the shared framework dependencies but does not initialize the inherited Sparkle updater.

Product names and provider marks identify their respective services. Credit is not a claim of affiliation or endorsement. See [TRADEMARK.md](TRADEMARK.md) and [LICENSE](LICENSE).
