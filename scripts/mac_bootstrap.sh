#!/usr/bin/env bash
#
# Nimble Scholar — macOS project bootstrap (no manual Xcode setup).
#
# Generates NimbleScholar.xcodeproj from a spec using XcodeGen, with the local
# NimbleScholarCore package wired in, the right files included, and NO App Sandbox
# (so the capture server + arXiv fetch work). Optionally builds & launches.
#
# Usage:
#   bash scripts/mac_bootstrap.sh c        # minimal boot app (Step C), generate + open Xcode
#   bash scripts/mac_bootstrap.sh c run    # minimal boot app, build + launch from CLI
#   bash scripts/mac_bootstrap.sh full     # full app (Step A), generate + open Xcode
#   bash scripts/mac_bootstrap.sh full run # full app, build + launch from CLI
#
# Defaults: MODE=full, ACTION=open
set -euo pipefail

MODE="${1:-full}"     # c | full
ACTION="${2:-open}"   # open | run

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Nimble Scholar bootstrap  (mode=$MODE, action=$ACTION)"
echo "    repo: $ROOT"

# --- 0. sanity ---------------------------------------------------------------
if [[ "$(uname)" != "Darwin" ]]; then
  echo "!! This script must run on macOS (it needs Xcode)."; exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "!! Xcode not found. Install Xcode from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"; exit 1
fi

# --- 1. ensure XcodeGen -------------------------------------------------------
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> Installing XcodeGen via Homebrew…"
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "!! Homebrew not found. Install it first:"
    echo '   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
  fi
fi

# --- 2. choose the source set for this mode ----------------------------------
if [[ "$MODE" == "c" ]]; then
  SOURCES='      - NimbleScholar/AppEnvironment.swift
      - NimbleScholar/NimbleScholarApp.swift
      - NimbleScholar/BootCheckView.swift'
else
  SOURCES='      - NimbleScholar/AppEnvironment.swift
      - NimbleScholar/App
      - NimbleScholar/Library
      - NimbleScholar/Reader
      - NimbleScholar/Settings'
fi

# --- 3. write the XcodeGen spec ----------------------------------------------
echo "==> Writing project.yml"
cat > project.yml <<YAML
name: NimbleScholar
options:
  bundleIdPrefix: com.yijie
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
packages:
  NimbleScholarCore:
    path: NimbleScholarCore
targets:
  NimbleScholar:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources:
$SOURCES
    dependencies:
      - package: NimbleScholarCore
        product: NimbleScholarCore
    info:
      path: Generated/Info.plist
      properties:
        CFBundleDisplayName: Nimble Scholar
        LSMinimumSystemVersion: "14.0"
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        LSApplicationCategoryType: public.app-category.productivity
        NSPrincipalClass: NSApplication
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.yijie.nimblescholar
        SWIFT_VERSION: "5.0"
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        # Ad-hoc local signing: no Apple Developer account required.
        CODE_SIGN_STYLE: Manual
        CODE_SIGN_IDENTITY: "-"
        ENABLE_HARDENED_RUNTIME: NO
        # No entitlements file => app is NOT sandboxed => loopback capture server
        # and outbound arXiv requests both work.
schemes:
  NimbleScholar:
    build:
      targets:
        NimbleScholar: all
    run:
      config: Debug
YAML

# --- 4. clean previous project + stale derived data --------------------------
echo "==> Cleaning previous project + DerivedData"
rm -rf NimbleScholar.xcodeproj
rm -rf ~/Library/Developer/Xcode/DerivedData/NimbleScholar-* 2>/dev/null || true

# --- 5. generate -------------------------------------------------------------
echo "==> Generating NimbleScholar.xcodeproj"
xcodegen generate --spec project.yml

# --- 6. open or build+run ----------------------------------------------------
if [[ "$ACTION" == "run" ]]; then
  echo "==> Building (CLI). Compile errors, if any, print below."
  xcodebuild \
    -project NimbleScholar.xcodeproj \
    -scheme NimbleScholar \
    -configuration Debug \
    -derivedDataPath .build-xcode \
    build
  APP="$(/usr/bin/find .build-xcode/Build/Products/Debug -maxdepth 1 -name 'NimbleScholar.app' | head -1)"
  if [[ -n "$APP" ]]; then
    # Kill any already-running instance. Otherwise `open` would just re-activate the
    # OLD process (same bundle id) instead of launching the new build — and it would
    # keep holding port 8765.
    pkill -f "NimbleScholar.app/Contents/MacOS/NimbleScholar" 2>/dev/null || true
    sleep 1
    echo "==> Launching the freshly built binary directly (bypassing LaunchServices)."
    echo "    Logs print below; press Ctrl+C to quit the app."
    exec "$APP/Contents/MacOS/NimbleScholar"
  else
    echo "!! Build produced no .app — see errors above."; exit 1
  fi
else
  echo "==> Opening Xcode. Press ⌘R to run."
  open NimbleScholar.xcodeproj
fi

echo "==> Done."
