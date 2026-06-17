# Nimble Scholar — Architecture

A developer's map of the codebase. For user-facing docs see `README.md`.

## Overview

Two layers:

- **`NimbleScholarCore/`** — a SwiftPM package with all non-UI logic: models, the GRDB SQLite
  store, services (arXiv/metadata/figures/PDF download/BibTeX/Markdown), and the embedded capture
  HTTP server. **No SwiftUI, no AppKit windows.** It is fully unit-tested with `swift test`, which
  is the project's main correctness signal.
- **`NimbleScholar/`** — the SwiftUI/PDFKit app target. It depends on the core package and holds
  windows, views, view models, and PDFKit/AppKit interop.

Why the split: the core can be tested on any machine with a Swift toolchain, independent of the
UI, and the boundary keeps business logic out of views.

## Module map

| Path | Responsibility |
|---|---|
| `Core/Models/Paper.swift` | Paper record (metadata, PDF cache, `isRead`); camelCase↔snake_case mapping |
| `Core/Models/Tag.swift` | `Tag`, `PaperTag` join, `TagCount` (sidebar) |
| `Core/Models/AnnotationIndex.swift` | Index row for one highlight/note (PDF file is source of truth) |
| `Core/Models/CapturePayload.swift` | JSON body from the extension |
| `Core/Store/LibraryStore.swift` | GRDB queue, migrations, CRUD, FTS5 search, tags, read state, change observation |
| `Core/Store/TagNormalizer.swift` | Split/lowercase/dedupe tag strings |
| `Core/Services/ArxivService.swift` | arXiv id extraction + PDF URL normalization |
| `Core/Services/MetadataService.swift` | Parse arXiv Atom XML + generic `<meta>` HTML |
| `Core/Services/FigureChooser.swift` / `ArxivFigureService.swift` | Scrape teaser/pipeline figures: arXiv HTML → ar5iv fallback, or any HTML landing page (`<figure>` + `og:image`) |
| `Core/Services/PDFDownloader.swift` | Resolve + download + cache a PDF |
| `Core/Services/BibTeXExporter.swift` / `MarkdownExporter.swift` | Export formats |
| `Core/Capture/CaptureHandler.swift` | Turn a payload into a saved/updated paper (with dedupe + figures) |
| `Core/Capture/CaptureServer.swift` | FlyingFox loopback server: `/api/capture`, `/api/ping` |
| `App/AppEnvironment.swift` | App-wide singleton: store, PDF cache, capture server (port auto-retry), metadata/figure resolvers |
| `App/App/NimbleScholarApp.swift` | `@main`; library + per-paper reader windows; menu commands |
| `App/Library/LibraryViewModel.swift` | Library state: scope/search/sort, batched tag map, observation, bulk ops |
| `App/Library/*View.swift` | Sidebar, the three view modes, detail, edit/capture sheets, context menu, thumbnails |
| `App/Library/ThumbnailCache.swift` | Two-level (memory + disk) card-image cache |
| `App/Library/ActivityCenter.swift` | Tracks global + per-paper download activity; drives the bottom status bar |
| `App/Library/PaperStatus.swift` | Per-paper readiness (`isReady`/`hasFigure`/`hasLocalPDF`) + card status badges |
| `App/Library/BackupManager.swift` | Zip backup/restore of the data dir via `ditto` |
| `App/Reader/*` | Reader window, `PDFKitView` (NSViewRepresentable), toolbar, inspector, `AnnotationController`, reader VM |
| `App/Settings/SettingsView.swift` | General (capture, port, download proxy) + Reading + AI settings |
| `App/Mindmap/*` | Mindmap view mode: `MindmapView`, `MindmapViewModel`, `MapBar` (map picker/create/delete), `PaperShelf` (searchable collapsible paper shelf), `MindmapCanvas` (two-layer rendering: committed tree Canvas + interactive drop-indicator overlay; pan/zoom/cull), `NodeView` + `NodePaperChip` (node card + attached-paper chips); auto-layout tree model with keyboard editing (Tab/Return/arrows/Space/Delete), drag-to-reparent, and undo/redo |
| `Core/Store/MindmapStore.swift` | Mindmap persistence (maps, nodes, edges, paper attachments, per-map viewport) sharing the GRDB queue; tree ops (add/move/delete node, collapse, reorder) + id-stable snapshot/restore for undo; `graph(forMap:)` returns the full node+edge graph |
| `Core/Services/CanvasTransform.swift` | Pure canvas↔screen coordinate math: pan/zoom transform, hit-testing, off-screen culling |
| `Core/Services/TreeLayout.swift` | Pure tidy left-to-right tree layout: computes node positions from the tree structure; positions are never persisted |
| `Core/Services/MindmapNodeSizing.swift` | Node-size estimation used by `TreeLayout` to allocate space for each node's label |
| `Core/Models/Mindmap.swift` | `Mindmap`, `MindmapNode`, `MindmapEdge`, `MindmapGraph` model records |

## Data flow

**Capture** (in-app sheet, or extension/bookmarklet over HTTP):
```
CaptureSheet / CaptureServer → CaptureHandler.capture(payload)
  → resolve metadata (arXiv API or <meta>) → dedupe via LibraryStore.existingPaper(forCaptureURL:)
  → create or update Paper → (best-effort) arXiv figure enrichment
LibraryStore write → GRDB ValueObservation → LibraryViewModel.reload() → views update live
  → reload() also runs autoCompleteIncomplete(): for each not-yet-ready paper, fetch its
    figure (arXiv/ar5iv/landing page) + PDF in the background, with per-item + status-bar
    progress (attempted once per session; orange badge / "Load missing…" re-arm a retry)
```

**Reading & annotating**:
```
openWindow("reader", id) → ReaderWindow → ReaderViewModel.load()
  → PDFDownloader.ensureLocalPDF (persists pdf_path) → PDFDocument → PDFKitView
  → mark read; restore last page; reconcile annotation index vs file
AnnotationController: add highlight/note → PDFAnnotation into the document + AnnotationIndex row
  → ReaderViewModel.scheduleSave() debounces the whole-file write (flushed on close)
```

**Thumbnails**: `PaperThumbnail` → `ThumbnailCache.image(for:)` → memory (NSCache) → disk PNG →
produce (download teaser/pipeline figure, else render PDF page 1). Disk capped; prewarmed after reload.

## Data model

Tables (see `LibraryStore.migrator`): `papers` (incl. `read`), `tags`, `paper_tags`,
`pdf_annotations`, and the `papers_fts` FTS5 virtual table synchronized with `papers`.
Mindmap tables added in `v9-mindmap`: `mindmaps`, `mindmap_nodes`, `mindmap_edges`,
`mindmap_node_papers` (all FK cascade).
The **`v10-mindmap-tree` migration** adds `parent_id`, `sort_order`, and `collapsed` columns
to `mindmap_nodes`. Tree structure is encoded entirely in `parent_id` (null = root); layout
coordinates are never stored (computed at render time by `TreeLayout`). The `mindmap_edges`
table is now dormant — no new tree code reads or writes it.
Migrations are **additive and idempotent** (`v1`, `v2-fts`, `v3-read`, …, `v9-mindmap`, `v10-mindmap-tree`); existing libraries
upgrade in place. Search uses FTS5 with `LibraryStore.ftsQuery` quoting each token so punctuation
can't break the query.

## How to add a feature

- **A new paper field**: add the column in a new migration; add the property + `Columns`/`CodingKeys`
  cases in `Paper.swift`; surface it in the edit sheet / detail / card as needed.
- **A new bulk action**: add a method on `LibraryViewModel` operating over `selectedPapers()`; add a
  button in the Three-pane bulk bar.
- **A new export/format**: add a pure function in `Core/Services` with a `swift test`; wire a
  toolbar/menu button that runs an `NSSavePanel`.

## Build & run

- App: `bash scripts/mac_bootstrap.sh full run` (generates the Xcode project with XcodeGen, builds,
  launches; no App Sandbox so the capture server + network work).
- Core tests: `cd NimbleScholarCore && swift test`.
- App icon: `python3 scripts/generate_icon.py` regenerates `Assets.xcassets/AppIcon.appiconset`.
