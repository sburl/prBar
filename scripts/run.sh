#!/usr/bin/env bash
# Build PRBar.app and install it to ~/Applications for local use.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="${HOME}/Applications"
APP="${APP_DIR}/PRBar.app"

mkdir -p "${APP_DIR}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BIN_DIR}/PRBar" "${APP}/Contents/MacOS/PRBar"
cp "${BIN_DIR}/prbar-cli" "${APP}/Contents/MacOS/prbar-cli"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
chmod +x "${APP}/Contents/MacOS/PRBar" "${APP}/Contents/MacOS/prbar-cli"

BUNDLE_ID="lc.bestprice.prbar"
# Local builds are ad-hoc signed. A Developer ID is optional via CODESIGN_IDENTITY.
IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --sign "${IDENTITY}" --identifier "${BUNDLE_ID}" "${APP}/Contents/MacOS/PRBar"
codesign --force --sign "${IDENTITY}" --identifier "${BUNDLE_ID}.cli" "${APP}/Contents/MacOS/prbar-cli"
codesign --force --sign "${IDENTITY}" --identifier "${BUNDLE_ID}" "${APP}"

mkdir -p dist
cp "${BIN_DIR}/prbar-cli" dist/prbar-cli

# Reloading an already-running instance would keep the old binary.
killall PRBar 2>/dev/null || true
sleep 0.4

open "${APP}"
echo "✓ Installed ${APP}"
echo "  CLI: ${APP}/Contents/MacOS/prbar-cli"
echo "  Also copied to $(pwd)/dist/prbar-cli"
