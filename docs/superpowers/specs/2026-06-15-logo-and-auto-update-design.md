# Design — New App Logo + One‑Click Auto‑Update

Date: 2026-06-15
Status: Approved (pending spec review)

## Overview

Two independent deliverables for Nimble Scholar:

1. **A new app logo** — replace the graduation‑cap icon with the "page + highlighter"
   mark (indigo→blue squircle, amber highlighter band over a paper page).
2. **One‑click auto‑update** — integrate the **Sparkle** framework so the installed
   `.app` updates itself (in‑app "Check for Updates", daily background checks,
   download + install + relaunch), with releases published to **GitHub Releases**.

The app is distributed **without an Apple Developer account** (ad‑hoc signing, no
notarization, no sandbox — see `scripts/mac_bootstrap.sh`). The design works within
that constraint; **EdDSA signatures** are the update trust anchor.

---

## Part 1 — App logo

### Final design
Concept "C / V1":
- macOS squircle background, vertical **indigo→blue** gradient
  (`#7C9AFF` → `#3C58D8`), with a soft top sheen — matching the existing brand.
- A white **paper page** centered, with a **folded top‑right corner** (light fold tint).
- Several ink text lines (soft indigo tint).
- One line sits under an **amber highlighter band** (`#FFC440`, rounded), which is
  the recognizable "this app highlights papers" signal.
- Subtle drop shadow under the page for depth.

Verified legible from 1024px down to 32px (at 16px it reads as a small document, the
same as other doc‑type icons — acceptable).

### Implementation
- Rewrite **`scripts/generate_icon.py`** so its `make_master()` draws the design above
  (replacing the graduation cap). Keep the existing supersampling + squircle helpers.
- It regenerates the full **`NimbleScholar/Assets.xcassets/AppIcon.appiconset`**:
  all 10 macOS entries (`16/32/128/256/512` @1x/@2x) + `Contents.json`, and writes the
  1024 master preview to `assets/nimble-scholar-icon-1024.png`.
- The app already builds its icon from the asset catalog
  (`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in `project.yml`); no app code change.
- Run `python3 scripts/generate_icon.py` to apply. (Requires Pillow.)

### Out of scope
- The root `*.iconset` folders and the committed `Nimble Scholar.app` bundle are legacy
  artifacts and are **not** updated by this change.

---

## Part 2 — Auto‑update (Sparkle + GitHub Releases)

### Trust model (no Apple Developer ID)
- **EdDSA (ed25519)** signatures are the security anchor (Sparkle's supported path for
  apps not signed with a Developer ID). Code‑signing identity match is **not** used.
- One‑time setup: run Sparkle's **`generate_keys`** → stores the private key in the
  login Keychain, prints the public key. The public key is embedded in Info.plist as
  **`SUPublicEDKey`**. The private key signs every release archive.
- Each release `.zip` is EdDSA‑signed; the app installs an update only if its signature
  verifies against the embedded public key. Feed is served over **HTTPS** (GitHub).

### Dependency & build
- Add **Sparkle 2.x** as a remote SPM package in `project.yml`:
  ```yaml
  packages:
    NimbleScholarCore:
      path: NimbleScholarCore
    Sparkle:
      url: https://github.com/sparkle-project/Sparkle
      from: "2.6.0"
  ```
  and add `- package: Sparkle` (product `Sparkle`) to the `NimbleScholar` target
  dependencies.
- Under the existing `CODE_SIGN_IDENTITY "-"`, Xcode embeds and ad‑hoc‑signs
  `Sparkle.framework` automatically. The app is **non‑sandboxed**, so Sparkle uses its
  simple in‑process installer (no XPC services / entitlements required).

### Info.plist keys (via `project.yml` `info.properties`)
- `SUFeedURL` =
  `https://github.com/yijie21/NimbleScholar/releases/download/updates/appcast.xml`
- `SUPublicEDKey` = `<base64 public key from generate_keys>`
- `SUEnableAutomaticChecks` = `true`
- `SUScheduledCheckInterval` = `86400` (daily)

### App wiring (`NimbleScholar/`)
- **`NimbleScholar/Update/UpdaterController.swift`** — an `ObservableObject` wrapping
  `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
  userDriverDelegate: nil)`. Exposes `checkForUpdates()` and a published
  `automaticallyChecksForUpdates` binding.
- **`NimbleScholar/App/NimbleScholarApp.swift`** — add a **"Check for Updates…"**
  command via `CommandGroup(after: .appInfo)` calling `updater.checkForUpdates()`.
  Hold the `UpdaterController` as a `@StateObject` (or in `AppEnvironment`).
- **`NimbleScholar/Settings/SettingsView.swift`** — General tab gains a
  **"Automatically check for updates"** toggle bound to
  `updater.automaticallyChecksForUpdates`, plus a "Check Now" button.

### Testable core (`NimbleScholarCore/`)
- **`Sources/NimbleScholarCore/Update/UpdateFeed.swift`** — pure helper:
  ```swift
  enum UpdateFeed {
      static let owner = "yijie21"
      static let repo  = "NimbleScholar"
      static let channelTag = "updates"
      static func appcastURL() -> URL { … }      // .../releases/download/updates/appcast.xml
      static func downloadPrefix() -> URL { … }  // .../releases/download/updates/
  }
  ```
  Unit‑tested in `swift test` (URL construction is the only pure logic in this feature).
  The Info.plist `SUFeedURL` must equal `UpdateFeed.appcastURL()`.

### Release & distribution model (GitHub Releases)
A single **rolling GitHub Release** under the fixed tag **`updates`** holds
`appcast.xml` plus every version's `.zip`. This yields stable URLs that match the
Info.plist feed and the `--download-url-prefix`.

New script **`scripts/release.sh <version>`** (macOS):
1. Set `MARKETING_VERSION` to `<version>` and **increment** `CURRENT_PROJECT_VERSION`
   (build number — Sparkle compares `CFBundleVersion`; it must increase every release)
   in `project.yml` (and the mirrored `CFBundleShortVersionString` / `CFBundleVersion`
   in `info.properties`).
2. `xcodegen generate` then build **Release**:
   `xcodebuild -scheme NimbleScholar -configuration Release -derivedDataPath .build-xcode build`.
3. Archive: `ditto -c -k --keepParent NimbleScholar.app NimbleScholar-<version>.zip`
   into a local `releases/` dir.
4. `generate_appcast releases/ --download-url-prefix
   https://github.com/yijie21/NimbleScholar/releases/download/updates/`
   (signs each archive with the Keychain EdDSA key and writes `releases/appcast.xml`).
5. Publish: ensure the `updates` release exists, then
   `gh release upload updates releases/NimbleScholar-<version>.zip releases/appcast.xml --clobber`.

The Sparkle CLI tools (`generate_keys`, `sign_update`, `generate_appcast`) ship inside
the resolved Sparkle SPM artifact; the script locates them (or uses a downloaded Sparkle
tarball). The release script documents this lookup.

### User experience
- **First install (one‑time):** user downloads the `.app`, right‑click → **Open** to
  clear Gatekeeper (unsigned app). Documented in README.
- **Every subsequent update:** Sparkle checks daily (and on demand via the menu), shows
  the standard "A new version is available" panel, downloads, **installs in place and
  relaunches with no Gatekeeper prompt** (Sparkle clears the quarantine attribute and
  handles permissions). This is the Cursor‑like one‑click flow.

### Documentation
- README gains: **"Updating the app"** (end‑user: it self‑updates; first‑install
  right‑click→Open note) and **"Cutting a release"** (developer: one‑time
  `generate_keys` + `SUPublicEDKey`, then `scripts/release.sh <version>`).

---

## Testing strategy
- **Unit (`swift test`):** `UpdateFeed` URL construction (appcast URL + download prefix
  match the documented GitHub paths).
- **Manual integration (steps in README / plan):**
  1. Build current version. 2. Point `SUFeedURL` at a local `file://` appcast describing
     a higher build number. 3. Launch, run **Check for Updates…**, confirm the panel,
     download, install, and relaunch into the new build. 4. Repeat against the real
     `updates` GitHub release once published.
- **Logo:** run `generate_icon.py`, confirm `AppIcon.appiconset` regenerates and the
  master preview matches the approved design; build the app and verify the Finder/Dock
  icon.

## Risks / notes
- **EdDSA key custody:** the private key lives only in the developer's login Keychain.
  Losing it means future updates can't be signed with the embedded public key (would
  require shipping a manually‑installed build carrying a new `SUPublicEDKey`). Back it up.
- **Build‑number monotonicity:** the release script must always increase
  `CURRENT_PROJECT_VERSION`; Sparkle uses it (not the marketing string) to detect updates.
- **Sparkle tool availability:** the CLI tools come from the SPM artifact path, which can
  change across Sparkle versions; the release script resolves the path defensively.

## References
- Sparkle documentation — https://sparkle-project.org/documentation/
- Sparkle (EdDSA signing, `generate_appcast`) — https://github.com/sparkle-project/Sparkle
