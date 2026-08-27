#!/usr/bin/env bash
# Install PRBar as a menu extra in ~/Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/sburl/prBar/main/install.sh | bash
#
# Builds from source on your Mac (needs Swift / Xcode CLT and gh).
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "PRBar is macOS 14+ only." >&2
  exit 1
fi

if ! command -v swift >/dev/null; then
  echo "Swift is not on PATH. Install Xcode or the Command Line Tools, then retry." >&2
  exit 1
fi

if ! command -v git >/dev/null; then
  echo "git is required." >&2
  exit 1
fi

if ! command -v gh >/dev/null; then
  echo "GitHub CLI (gh) is required. brew install gh && gh auth login" >&2
  exit 1
fi

REPO="${PRBAR_REPO:-https://github.com/sburl/prBar.git}"
SRC="${PRBAR_SRC:-${XDG_CACHE_HOME:-$HOME/.cache}/prbar/src}"

mkdir -p "$(dirname "$SRC")"
if [[ -d "$SRC/.git" ]]; then
  git -C "$SRC" fetch --depth 1 origin
  git -C "$SRC" checkout --force -B main origin/main
else
  rm -rf "$SRC"
  git clone --depth 1 "$REPO" "$SRC"
fi

exec "$SRC/scripts/run.sh"
