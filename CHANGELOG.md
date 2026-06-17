# Changelog

## Milestone 8 — Mindmap view mode (2026-06-17, `v8.0.0`)

### Added
- **Mindmap** — a 4th library view mode beside Three-pane / Gallery / Rows. Build named
  idea-graphs on a native SwiftUI infinite canvas with smooth pan and zoom; off-screen
  nodes are culled for performance.
- **Named maps** — create, rename, and delete maps via the map bar; each map has its own
  canvas and its own pan/zoom viewport, persisted across relaunches.
- **Text nodes + free-form edges** — double-click empty canvas to create a node; double-click
  a node to edit its label; drag a node to reposition it. Drag from a node's trailing dot to
  another node to connect them; hover an edge midpoint and click × to delete it.
- **Searchable collapsible paper shelf** — a narrow shelf on the left edge lists your
  library papers (filterable by title). Drag a shelf card onto a node to attach it, or onto
  empty canvas to create a new node pre-attached. Click a paper chip on a node to open it in
  the reader; click × on a chip to detach it. Deleting a paper from the main library removes
  its chip from every node automatically (FK cascade).
- **`v9-mindmap` migration** — adds tables `mindmaps`, `mindmap_nodes`, `mindmap_edges`,
  `mindmap_node_papers` (all FK cascade) to the existing GRDB store.
- **`MindmapStore`** (Core) — CRUD for maps/nodes/edges/attachments + `graph(forMap:)`;
  shares the existing GRDB queue.
- **`CanvasTransform`** (Core, unit-tested) — pure canvas↔screen coordinate math: pan/zoom
  transform, hit-testing, and off-screen culling.

## Milestone 7 — In-window PDF reader (2026-06-15, `v7.0.0`)

### Changed
- **The PDF reader now opens inside the library window**, in the three-pane **detail
  pane**, with the paper list + sidebar still visible — instead of a separate window. A
  **Back** button (or Esc) returns to the paper detail. Reading from Gallery/Rows snaps to
  the three-pane layout. The standalone reader window is removed.
- **Two panels only:** the PDF (center) + the inspector (outline / annotations / chat).
  The **left page-thumbnail sidebar is gone** (scroll the PDF directly).

### Fixed
- Inspector panel rendered empty when nested — laid out as an inline trailing panel
  instead of SwiftUI's window-level `.inspector`.
- Inspector stayed on a perpetual spinner — `PDFKitView` now hands back its `PDFView` on
  the next runloop tick so the state actually updates.
- Paper-list width no longer jitters when the detail content changes (fixed-width list).

## Milestone 6 — First auto-update release + robust release pipeline (2026-06-15, `v6.0.0`)

### Added
- **First real Sparkle release published** to the rolling `updates` GitHub Release —
  installed copies can now auto-update via Check for Updates.

### Fixed
- **Release build numbers can no longer collide.** `CFBundleVersion` is now derived from
  the git commit count (`git rev-list --count HEAD`) in `mac_bootstrap.sh`, instead of a
  hand-incremented counter in `version.env`. A failed release run previously left the
  counter uncommitted, so a later run reused a build number and `generate_appcast` rejected
  the duplicate. `version.env` now holds only `MARKETING_VERSION`.

## Milestone 5 — Code-release watch, important star, read/tag polish (2026-06-15, `v5.0.0`)

### Added
- **Watch for code release.** Papers without confirmed code are re-checked (on launch +
  daily + manual "Check for code now"); when a **real** GitHub repo appears (not an
  empty/README-only placeholder, detected via the GitHub contents API) the paper gets a
  Code button and a **"Code released" notification that opens the repo on click**. First
  sweep reconciles existing links silently. `GitHubRepo` (Core) + `GitHubRepoChecker` +
  `CodeWatcher` + `Paper.code_ready` (`v6`).
- **"Re-validate code links"** (⋯ menu) — re-checks trusted links and demotes any that are
  actually empty back to "watching".
- **Mark papers important (star).** Gold star on cards / detail / right-click; starred
  papers float to the top of every list (All + any tag filter), with an **Important**
  sidebar filter. `Paper.important` (`v8`).
- **GitHub Octocat** mark on the Code button (template vector, light/dark adaptive).

### Changed
- **Unread = the `to-read` tag.** The blue dot, the Unread filter, and right-click
  Mark-as-Read all follow the `to-read` tag; opening via **Read** or **Browser** (or
  removing the tag) clears the dot. `LibraryStore.removeTag(_:fromPaper:)`.
- The detail **Browser** button now has a safari icon.
- Removed the in-app **Capture (URL)** and **Add (manual)** toolbar buttons (capture is via
  the browser extension / drag-in PDF; editing existing papers is unchanged).

### Fixed
- `v7`: existing code links no longer disappear behind re-validation — already-discovered
  links are trusted immediately; only new discoveries are validated.

## Milestone 4 — Project & code (GitHub) links (2026-06-15, `v4.0.0`)

### Added
- **Project-page and open-source (GitHub) link buttons** on the paper detail view.
  Links are auto-extracted from the cached PDF (link annotations + text) and the
  abstract/landing HTML page; if only a project page is found, it's fetched and scanned
  for a GitHub link. Project-page detection uses strong signals only (`*.github.io`,
  `sites.google.com`, links labeled "project page"/"website").
  - Core `LinkExtractor` (pure classification + SwiftSoup anchor parsing) + tests.
  - App `LinkFinder` (PDFKit + network orchestration).
  - `Paper.projectURL` / `codeURL` / `linksScanned` + `v5-links` migration.
- **Background backfill** for already-imported papers via the existing auto-complete loop,
  each showing a per-item **"Finding links…"** status; scanned once per paper.
- **Manual entry** — Project URL / Code URL fields in the Edit sheet, and an "Add links…"
  button in the detail view when none were found.

## Milestone 3 — Reliable capture: proxy default + error notifications (2026-06-15, `v3.0.0`)

### Fixed
- **Capture metadata silently failed on proxy-only networks.** A Finder-launched app's
  `URLSession` honors only macOS *System* proxy settings (not shell env vars), so the
  app couldn't reach arXiv and saved papers with the URL as their title.

### Changed / Added
- **Download proxy ON by default** — `AppDefaults` (proxy enabled, `127.0.0.1:7892`)
  registered into UserDefaults at launch; Settings fields read from it. Explicit user
  values still override.
- **Capture problems now surface as a macOS notification** instead of being swallowed.
  `CaptureHandler` reports an actionable message ("…check your network or proxy") when
  no title can be resolved; `AppEnvironment.makeCaptureHandler()` (shared by the capture
  server and the in-app Capture sheet) routes it to `Notifier`. + unit tests.

## Milestone 2 — New logo + one-click auto-update (2026-06-15, `v2.0.0`)

### Added
- **One-click auto-update via [Sparkle](https://sparkle-project.org) 2.x.** The app
  checks GitHub daily and via **Check for Updates…** (app menu + Settings ▸ General ▸
  Software updates), then downloads, installs in place, and relaunches — no Gatekeeper
  prompt after the first install. Trusted with **EdDSA** signatures, so it needs **no
  Apple Developer account**.
  - `NimbleScholarCore`: `UpdateFeed` GitHub appcast-URL builder (+ unit tests).
  - App: `UpdaterController`, menu command, Settings toggle.
  - Releases publish to a single rolling GitHub Release tagged `updates`
    (`appcast.xml` + version `.zip`s).
- **`scripts/release.sh`** — bump version, build Release, EdDSA-sign, regenerate
  `appcast.xml`, upload to the `updates` release. Auto-locates Sparkle tools
  (`~/tools/Sparkle-*/bin`, `~/Downloads/...`, DerivedData; or `SPARKLE_BIN` /
  `GEN_APPCAST`).
- **`scripts/install_app.sh`** — build Release and install into `/Applications`
  (locally built ⇒ not quarantined ⇒ launches without right-click→Open).
- **`scripts/version.env`** — env-driven `MARKETING_VERSION` / `BUILD_NUMBER`;
  `mac_bootstrap.sh` gains a `generate` action (project only, no build/open).

### Changed
- **New app icon** — "page + amber highlighter" mark on the indigo→blue squircle
  (replaces the graduation cap). Regenerated by `scripts/generate_icon.py`.
- **New Chrome/Edge extension toolbar icons** matching the app icon, via
  `scripts/generate_extension_icons.py`.

### Notes / not yet done
- First real release not cut yet: run `bash scripts/release.sh 0.1.1`
  (needs `gh auth login`).
- End-to-end update test still manual (see implementation-plan Task 11).
- The EdDSA **private key** lives only in the maintainer's login Keychain — back it up.

## Milestone 1 — Native macOS app (2026-06-14, `v1.0.0`)
Library + 3 view modes, PDFKit reader with annotations, capture (sheet / server /
extension) with dedupe, read/unread, import, backup, AI chat v1, full hardening pass.
