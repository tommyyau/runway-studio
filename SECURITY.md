# Security

This private repository contains Runway Studio and its MIT Runway base. For a Studio-specific issue, report it privately to this repository’s owner; do not send Studio bugs or private usage logs to the upstream maintainers by default. There is no promised public-release support window or response-time SLA for this personal build.

Include a description, affected revision, impact and reproduction steps. Remove access tokens, auth files, account identifiers and personal session content before sharing diagnostics.

Studio’s sensitive paths include local credential reads, provider requests, cache/history storage, imported history and build scripts. Background credential access must remain non-interactive, and tracking must not request administrator or App Management permission. The CLI/MCP reader must not expose credentials or initiate provider requests.

If an issue is independently confirmed to affect the unmodified upstream code, follow the relevant project’s private reporting policy: [Runway](https://github.com/mstallone/runway/security/policy) or [OpenUsage](https://github.com/robinebers/openusage/security/policy). Credit and coordinate upstream fixes where appropriate.
