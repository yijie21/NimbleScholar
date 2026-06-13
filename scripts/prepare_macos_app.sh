#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/Nimble Scholar.app"
LAUNCHER="${APP}/Contents/MacOS/NimbleScholar"
RESOURCES="${APP}/Contents/Resources"
APP_PAYLOAD="${RESOURCES}/app"
SEED="${RESOURCES}/seed"

mkdir -p "${APP}/Contents/MacOS" "$RESOURCES"
if [[ ! -f "${ROOT}/assets/nimble-scholar-1024.png" || ! -f "${ROOT}/extension/icon-128.png" ]]; then
  python3 "${ROOT}/scripts/generate_icons.py"
fi
cp "${ROOT}/assets/nimble-scholar-1024.png" "${RESOURCES}/NimbleScholar.png"

rm -rf "$APP_PAYLOAD"
mkdir -p "$APP_PAYLOAD"
cp "${ROOT}/server.py" "$APP_PAYLOAD/server.py"
cp -R "${ROOT}/static" "$APP_PAYLOAD/static"

rm -rf "$SEED"
mkdir -p "$SEED"
if [[ -f "${ROOT}/paper_app.sqlite3" ]]; then
  cp "${ROOT}/paper_app.sqlite3" "$SEED/paper_app.sqlite3"
fi
if [[ -d "${ROOT}/storage" ]]; then
  cp -R "${ROOT}/storage" "$SEED/storage"
fi

/usr/bin/clang \
  -fobjc-arc \
  -target arm64-apple-macos11 \
  -framework Cocoa \
  -framework WebKit \
  -o "$LAUNCHER" \
  "${ROOT}/scripts/NimbleScholarApp.m"
chmod +x "$LAUNCHER"
/usr/bin/plutil -lint "${APP}/Contents/Info.plist"

echo "Nimble Scholar.app is ready:"
echo "$APP"
