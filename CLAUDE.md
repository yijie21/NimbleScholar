# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Nimble Scholar — a local-first macOS app (Swift/SwiftUI + PDFKit) for capturing, organizing, reading, and annotating research papers. Local SQLite (GRDB) storage, an embedded HTTP capture server (FlyingFox) that a Chrome/Edge extension posts to, and Sparkle auto-updates.

`docs/ARCHITECTURE.md` is the authoritative developer map (module table, data flows, schema); keep it updated when you change architecture. Feature work is documented in `docs/superpowers/specs/` (design specs) and `docs/superpowers/plans/` (implementation plans); `CHANGELOG.md` records milestones.

## Commands

Everything below requires **macOS with Xcode** (the core package needs only a Swift toolchain). There is no Node/Python build; `server.py` + `static/` are the retired Python prototype (see `docs/legacy-prototype-readme.md`) — don't extend them.

```bash
# Build + launch the app (generates the Xcode project via XcodeGen first)
bash scripts/mac_bootstrap.sh full run

# Generate the project and open Xcode instead
bash scripts/mac_bootstrap.sh full

# Core tests — the project's main correctness signal
cd NimbleScholarCore && swift test

# Run a single test
cd NimbleScholarCore && swift test --filter LibraryStoreTests            # one class
cd NimbleScholarCore && swift test --filter LibraryStoreTests/testName   # one method

# Cut a release (bumps version, builds Release, Sparkle-signs, publishes to the rolling "updates" GitHub Release)
bash scripts/release.sh 0.2.0

# Regenerate app icon assets
python3 scripts/generate_icon.py
```

`NimbleScholar.xcodeproj` and `project.yml` are **generated and gitignored** — never edit them. The XcodeGen spec is a heredoc inside `scripts/mac_bootstrap.sh`; that's where project settings live, and **a new top-level source directory under `NimbleScholar/` must be added to the `SOURCES` list there** or it won't compile into the app.

Versioning: the user-facing version is `scripts/version.env` (`MARKETING_VERSION`, written by `release.sh`); the build number is the git commit count, so it's monotonic automatically.

## Architecture

Two layers, split so business logic is testable without the UI:

- **`NimbleScholarCore/`** — SwiftPM package with all non-UI logic: models, the GRDB store, services (arXiv/metadata/figure scraping/PDF download/BibTeX/Markdown exporters/mindmap layout), and the capture HTTP server. **No SwiftUI or AppKit allowed here.** Fully unit-tested (`Tests/NimbleScholarCoreTests/`, with `Fixtures/` resources). Dependencies: GRDB, FlyingFox, SwiftSoup.
- **`NimbleScholar/`** — the app target: windows, views, view models, PDFKit/AppKit interop. Organized by feature: `App/`, `Library/`, `Links/`, `Mindmap/`, `Reader/`, `Settings/`, `Update/`. `AppEnvironment.swift` is the app-wide singleton wiring store + PDF cache + capture server (with port auto-retry) + resolvers. The app deliberately has **no App Sandbox** so the capture server and network fetches work.

Key flows (detailed diagrams in `docs/ARCHITECTURE.md`):

- **Capture**: in-app sheet or extension HTTP POST → `CaptureHandler.capture(payload)` → metadata resolution (arXiv Atom API or `<meta>` scraping) → dedupe by capture URL → create/update `Paper` → best-effort figure enrichment. Store writes propagate via GRDB `ValueObservation` → `LibraryViewModel.reload()` → views update live; `reload()` also background-completes missing figures/PDFs once per session.
- **Reader**: per-paper window → `ReaderViewModel.load()` → `PDFDownloader.ensureLocalPDF` → `PDFKitView`. Annotations are written **into the PDF file itself** (source of truth) with an `AnnotationIndex` row for listing; saves are debounced and flushed on close/quit.

## Database rules

Schema lives in `LibraryStore.migrator` (plus `MindmapStore`). Migrations are **additive and idempotent, named `v1`, `v2-fts`, `v3-read`, … — never edit an existing migration; add a new one** so existing user libraries upgrade in place. Search is FTS5 (`papers_fts`); `LibraryStore.ftsQuery` quotes each token so punctuation can't break queries. Mindmap tree structure is encoded in `mindmap_nodes.parent_id` with persisted `x`/`y` positions (`mindmap_edges` is dormant — don't read/write it).

## Adding features (recipes from docs/ARCHITECTURE.md)

- **New paper field**: new migration + property/`Columns`/`CodingKeys` in `Paper.swift` + surface in edit sheet/detail/card.
- **New bulk action**: method on `LibraryViewModel` over `selectedPapers()` + button in the Three-pane bulk bar.
- **New export format**: pure function in `Core/Services` with a `swift test`, wired to a toolbar/menu button running `NSSavePanel`.

## Conventions

- Commits are conventional-commit style with feature scopes: `feat(library):`, `fix(reader):`, `feat(core):`, `docs:`, etc.
- Logic goes in the core package with tests first; the app layer stays thin. If it can be a pure function in `Core/Services`, it should be.
