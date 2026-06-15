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

# Versions: file defaults, overridable by env (release.sh sets them).
if [[ -f scripts/version.env ]]; then
  # shellcheck disable=SC1091
  source scripts/version.env
fi
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

echo "==> Nimble Scholar bootstrap  (mode=$MODE, action=$ACTION, version=$MARKETING_VERSION build=$BUILD_NUMBER)"
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
  echo "!! The 'c' (boot-check) mode was removed; use 'full'." >&2
  exit 1
else
  SOURCES='      - NimbleScholar/AppEnvironment.swift
      - NimbleScholar/App
      - NimbleScholar/Library
      - NimbleScholar/Reader
      - NimbleScholar/Settings
      - NimbleScholar/Update
      - NimbleScholar/Assets.xcassets'
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
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.0"
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
      - package: Sparkle
        product: Sparkle
    info:
      path: Generated/Info.plist
      properties:
        CFBundleDisplayName: Nimble Scholar
        LSMinimumSystemVersion: "14.0"
        CFBundleShortVersionString: "${MARKETING_VERSION}"
        CFBundleVersion: "${BUILD_NUMBER}"
        LSApplicationCategoryType: public.app-category.productivity
        # --- Sparkle auto-update (EdDSA-trusted; no Apple Developer account needed) ---
        SUFeedURL: "https://github.com/yijie21/NimbleScholar/releases/download/updates/appcast.xml"
        SUPublicEDKey: "REPLACE_WITH_PUBLIC_KEY"
        SUEnableAutomaticChecks: true
        SUScheduledCheckInterval: 86400
        NSPrincipalClass: NSApplication
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.yijie.nimblescholar
        SWIFT_VERSION: "5.0"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        MARKETING_VERSION: "${MARKETING_VERSION}"
        CURRENT_PROJECT_VERSION: "${BUILD_NUMBER}"
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
    # Kill any already-running instance so (a) ports free up and (b) `open -n`
    # launches THIS fresh build instead of re-activating an old one.
    pkill -9 -f 'MacOS/NimbleScholar' 2>/dev/null || true
    sleep 1
    rm -f /tmp/nimblescholar-port.txt
    echo "==> Launching $APP (new instance, real window)."
    open -n "$APP"
    echo "==> Waiting for the capture server to report its port…"
    for _ in $(seq 1 15); do
      [[ -f /tmp/nimblescholar-port.txt ]] && break
      sleep 1
    done
    if [[ -f /tmp/nimblescholar-port.txt ]]; then
      PORT="$(cat /tmp/nimblescholar-port.txt)"
      echo "==> ✅ Capture server: http://127.0.0.1:${PORT}/api/capture"
      echo "    Test it:  curl -s -X POST http://127.0.0.1:${PORT}/api/capture -H 'Content-Type: application/json' -d '{\"url\":\"https://arxiv.org/abs/1512.03385\",\"tags\":\"test\"}'"
    else
      echo "==> Could not read bound port — check Console.app (filter: NimbleScholar)."
    fi
  else
    echo "!! Build produced no .app — see errors above."; exit 1
  fi
elif [[ "$ACTION" == "generate" ]]; then
  echo "==> Project generated (no build, no open)."
else
  echo "==> Opening Xcode. Press ⌘R to run."
  open NimbleScholar.xcodeproj
fi

echo "==> Done."
