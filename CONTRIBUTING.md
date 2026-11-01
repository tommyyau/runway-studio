# Working on Runway Studio

This is a private, laptop-focused derivative of MIT Runway. Changes should improve the Claude/Codex Studio experience while preserving attribution and existing local data. The upstream multi-provider source remains available, but its presence does not expand Studio’s current product scope.

Read [AGENTS.md](AGENTS.md) for engineering conventions, [the Studio guide](docs/studio.md) for current behaviour and [the architecture](docs/architecture.md) for the shared provider foundation.

- Keep changes focused and describe their user-visible effect.
- Reuse the shared provider/auth/parser logic; avoid parallel credential-reading paths.
- Preserve the single polling owner, persisted backoff, real provider timestamps and separate native/imported account histories.
- Never include credentials, personal session logs, runtime caches or signing material in a commit.
- Run checks appropriate to the change, and verify native UI changes in a rebuilt app.
- Preserve the MIT licence and [acknowledgements](ACKNOWLEDGEMENTS.md).

Build Studio with `bash script/build_studio.sh`. `script/build_and_run.sh` belongs to the original Runway application and is not Studio’s launch path. The inherited release workflows are not configured as Studio deployment; do not tag, publish or enable them as part of routine development.

The README illustrations are rendered from actual Studio views with synthetic data. Regenerate them with `bash script/render_studio_docs.sh`; do not replace them with personal usage screenshots.
