#!/usr/bin/env bash
set -euo pipefail

STUDIO_TOOL="/Applications/Runway Studio.app/Contents/MacOS/runway-studio"
STUDIO_BIN="${HOME}/.local/bin"
STUDIO_LINK="${STUDIO_BIN}/runway-studio"
if [[ ! -x "$STUDIO_TOOL" ]]; then
  echo "Install Runway Studio.app in Applications first." >&2
  exit 1
fi
mkdir -p "$STUDIO_BIN"
if [[ -e "$STUDIO_LINK" || -L "$STUDIO_LINK" ]]; then
  if [[ ! -L "$STUDIO_LINK" || "$(readlink "$STUDIO_LINK")" != "$STUDIO_TOOL" ]]; then
    echo "Preserving existing ${STUDIO_LINK}; choose another location manually." >&2
    exit 1
  fi
else
  ln -s "$STUDIO_TOOL" "$STUDIO_LINK"
fi
echo "Installed ${STUDIO_LINK}"
