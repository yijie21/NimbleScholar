#!/usr/bin/env bash
#
# Nimble Scholar — build, sign, and publish a release to GitHub Releases.
#
# Usage:  bash scripts/release.sh <marketing-version>      e.g.  bash scripts/release.sh 0.2.0
#
# Publishes the app .zip + appcast.xml as assets on a single rolling GitHub
# Release tagged "updates" (matches UpdateFeed / SUFeedURL). Requires: macOS,
# Xcode, gh (authenticated), and a Sparkle EdDSA key in your login Keychain.
set -euo pipefail

VERSION="${1:?usage: release.sh <marketing-version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname)" != "Darwin" ]]; then echo "!! macOS only."; exit 1; fi
command -v gh >/dev/null || { echo "!! gh CLI not found (brew install gh; gh auth login)"; exit 1; }

# --- 1. bump versions (build number must increase for Sparkle) ----------------
source scripts/version.env
NEW_BUILD=$(( BUILD_NUMBER + 1 ))
cat > scripts/version.env <<EOF
# Versions baked into the app at generate time. release.sh bumps these.
# MARKETING_VERSION: user-facing (CFBundleShortVersionString).
# BUILD_NUMBER: monotonic integer Sparkle compares (CFBundleVersion) — must increase every release.
MARKETING_VERSION=${VERSION}
BUILD_NUMBER=${NEW_BUILD}
EOF
echo "==> Releasing ${VERSION} (build ${NEW_BUILD})"

# --- 2. generate project + build Release --------------------------------------
MARKETING_VERSION="${VERSION}" BUILD_NUMBER="${NEW_BUILD}" bash scripts/mac_bootstrap.sh full generate
xcodebuild -project NimbleScholar.xcodeproj -scheme NimbleScholar \
  -configuration Release -derivedDataPath .build-release build
APP="$(/usr/bin/find .build-release/Build/Products/Release -maxdepth 1 -name 'NimbleScholar.app' | head -1)"
[[ -n "$APP" ]] || { echo "!! build produced no .app"; exit 1; }

# --- 3. archive into releases/ ------------------------------------------------
mkdir -p releases
ZIP="releases/NimbleScholar-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "==> Archived $ZIP"

# --- 4. sign + (re)generate appcast.xml ---------------------------------------
GEN_APPCAST="${GEN_APPCAST:-$(find ~/Library/Developer/Xcode/DerivedData -path '*/Sparkle/bin/generate_appcast' 2>/dev/null | head -1)}"
[[ -n "$GEN_APPCAST" ]] || { echo "!! generate_appcast not found — build once so SPM resolves Sparkle, or download the Sparkle release tarball and set GEN_APPCAST=/path/to/bin/generate_appcast."; exit 1; }
"$GEN_APPCAST" releases/ \
  --download-url-prefix "https://github.com/yijie21/NimbleScholar/releases/download/updates/"
echo "==> Wrote releases/appcast.xml"

# --- 5. publish to the rolling 'updates' release ------------------------------
if ! gh release view updates >/dev/null 2>&1; then
  gh release create updates --title "Auto-update channel" \
    --notes "Rolling channel: holds appcast.xml + all version archives for in-app updates." --latest=false
fi
gh release upload updates releases/*.zip releases/appcast.xml --clobber
echo "==> ✅ Published ${VERSION}. Users on older builds will be offered the update."

# --- 6. record the version bump ----------------------------------------------
git add scripts/version.env
git commit -m "release: ${VERSION} (build ${NEW_BUILD})" || true
echo "==> Committed version bump. Tag/push as you like."
