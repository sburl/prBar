#!/usr/bin/env bash
# Build prBar.app and install it to ~/Applications for local use.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="${HOME}/Applications"
APP="${APP_DIR}/prBar.app"

mkdir -p "${APP_DIR}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BIN_DIR}/prBar" "${APP}/Contents/MacOS/prBar"
cp "${BIN_DIR}/prbar-cli" "${APP}/Contents/MacOS/prbar-cli"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
chmod +x "${APP}/Contents/MacOS/prBar" "${APP}/Contents/MacOS/prbar-cli"

BUNDLE_ID="lc.bestprice.prbar"
# Local builds are ad-hoc signed. A Developer ID is optional via CODESIGN_IDENTITY.
IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --sign "${IDENTITY}" --identifier "${BUNDLE_ID}" "${APP}/Contents/MacOS/prBar"
codesign --force --sign "${IDENTITY}" --identifier "${BUNDLE_ID}.cli" "${APP}/Contents/MacOS/prbar-cli"
codesign --force --sign "${IDENTITY}" --identifier "${BUNDLE_ID}" "${APP}"

mkdir -p dist
cp "${BIN_DIR}/prbar-cli" dist/prbar-cli

# Reloading an already-running instance would keep the old binary.
killall prBar PRBar 2>/dev/null || true
sleep 0.4

open "${APP}"
echo "✓ Installed ${APP}"
echo "  CLI: ${APP}/Contents/MacOS/prbar-cli"
echo "  Also copied to $(pwd)/dist/prbar-cli"
