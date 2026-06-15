#!/usr/bin/env bash
#
# Nimble Scholar — build a Release app and install it into /Applications.
#
# Usage:  bash scripts/install_app.sh
#
# Produces a locally-built (not downloaded) app, so macOS does NOT quarantine it —
# it launches without the right-click → Open step. Auto-update still works: when you
# publish a newer build with scripts/release.sh, this installed copy updates itself.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname)" == "Darwin" ]] || { echo "!! macOS only (needs Xcode)."; exit 1; }

DEST="/Applications/Nimble Scholar.app"

# 1. generate the project + build Release
bash scripts/mac_bootstrap.sh full generate
xcodebuild -project NimbleScholar.xcodeproj -scheme NimbleScholar \
  -configuration Release -derivedDataPath .build-release build
APP="$(/usr/bin/find .build-release/Build/Products/Release -maxdepth 1 -name 'NimbleScholar.app' | head -1)"
[[ -n "$APP" ]] || { echo "!! build produced no .app — see errors above."; exit 1; }

# 2. replace any existing install
pkill -9 -f 'MacOS/NimbleScholar' 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "==> Installed: $DEST"

# 3. launch it
open "$DEST"
echo "==> Launched. It's now in your Applications and Launchpad."
