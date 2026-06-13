# Nimble Scholar — Native macOS Rewrite (Design)

**Date:** 2026-06-13
**Status:** Approved for planning
**Author:** Brainstormed with Claude Code

## Summary

Nimble Scholar today is a Python HTTP server with a plain HTML/CSS/JS frontend, rendered inside a WKWebView and shipped as a macOS app. The built-in PDF reader uses PDF.js with a hand-rolled selection/annotation system, and the UI is hand-styled "Apple-ish" CSS.

This project replaces that stack with a **fully native Swift/SwiftUI macOS app** that uses **PDFKit** for reading. The goal is a reader that feels like a commercial PDF app (Preview / PDF Expert / Adobe) and a library that looks genuinely native, while preserving the workflows the user values: tag-first library, one-click browser-extension capture, and arXiv metadata + figure enrichment.

## Goals

- A reading experience on par with commercial macOS PDF readers: native text search, text selection, page thumbnails, document outline, smooth zoom with fit-width/fit-page, lazy page rendering, real PDF annotations.
- A native-looking, switchable library UI (no more hand-rolled CSS).
- Preserve: tag-first library with search/sort, browser-extension capture, arXiv metadata + figure enrichment, BibTeX export.
- Keep everything local-first.

## Non-Goals (this phase)

- Migrating the existing SQLite library/PDFs (fresh store; optional importer left as a stub).
- Safari App Extension capture route (keep the existing Chrome/Edge extension via an embedded server).
- iOS/iPadOS, multi-PDF tabs in a single window.
- Dark/sepia rendering of PDF *content* beyond an optional "Night reading" invert (nice-to-have).

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Stack | Swift + SwiftUI, AppKit interop for PDFKit | Native feel; PDFKit gives reader features for free |
| Target | macOS 14 (Sonoma)+, Apple Silicon | Modern SwiftUI window/inspector APIs |
| Data | Local SQLite via **GRDB.swift** | Inspectable file, FTS, simple capture-server wiring |
| Capture | Embedded loopback HTTP server on `127.0.0.1:8765` | Existing Chrome/Edge extension + bookmarklet keep working unchanged |
| Annotations | Written into the PDF file as real `PDFAnnotation`s, indexed in SQLite | Portable like Preview/PDF Expert; index powers list + cross-paper search |
| Library layout | Three switchable view modes: Three-pane / Gallery / Rows | User wants all three with a toolbar switcher, persisted |
| Reader layout | Layout A: collapsible thumbnails + center PDF + collapsible inspector | User selection |

## Architecture

Single native macOS app. No Python, no WebView.

- SwiftUI App lifecycle; a main **Library window** and one **Reader window per open paper** (native multi-window via `openWindow`).
- `PDFView` (AppKit) wrapped in `NSViewRepresentable` for the reader.
- GRDB SQLite store in `~/Library/Application Support/Nimble Scholar/`, PDFs cached alongside.
- Embedded HTTP listener (FlyingFox or Swifter) for capture, started on app launch.

### Module structure

```
NimbleScholar.xcodeproj
  App/        NimbleScholarApp.swift  (scenes: Library window, Reader window)
  Models/     Paper, Tag, Annotation
  Store/      LibraryStore (GRDB), schema + FTS5, migrations
  Library/    SidebarView, ViewModeSwitcher, ThreePaneView, GalleryView, RowsView,
              PaperDetailView, PaperEditSheet, CaptureSheet, LibraryViewModel
  Reader/     ReaderView (PDFView wrapper), ReaderToolbar, ThumbnailSidebar,
              InspectorPanel (Outline + Annotations tabs), AnnotationController, ReaderViewModel
  Capture/    CaptureServer (loopback HTTP), MetadataService (arXiv API),
              ArxivFigureService (HTML scrape), PDFDownloader
  Services/   BibTeXExporter
```

## Components

### Data model (Store)

- `papers`: id, title, authors, year, venue, doi, url, pdf_url, pdf_path, summary, teaser_url, pipeline_url, abstract, notes, source, created_at, updated_at. Mirrors today's schema.
- `tags`: id, name (unique, normalized lowercase).
- `paper_tags`: many-to-many (paper_id, tag_id), cascade delete.
- `pdf_annotations` (**index only**, PDF file is source of truth): id, paper_id, page, kind (highlight|note), color, snippet text, normalized bounds, created_at, updated_at.
- FTS5 virtual table over title/authors/abstract/summary/venue/doi/tags for search.

`LibraryStore` exposes CRUD + observable queries (GRDB `ValueObservation`) consumed by `LibraryViewModel`.

### Library window

- `NavigationSplitView`: sidebar ‖ content.
- **Sidebar:** smart items (*All papers*, *Untagged*, *Recently added*) + tag list (colored dots, counts). Tag colors derived deterministically from the tag name (port current scheme).
- **View-mode switcher** (toolbar segmented control), `@AppStorage("libraryViewMode")`:
  - *Three-pane*: compact list + `PaperDetailView` (figure, metadata, abstract, tags, Read).
  - *Gallery*: figure-forward grid; click opens detail.
  - *Rows*: wide cards (refined version of today's design).
- Toolbar: search field, sort menu (Recently updated / Newest year / Title A–Z), **+ Add Paper**, **Capture URL**, **Export BibTeX**.
- Quick-tag add/remove and quick one-sentence summary editing carried over to the detail/cards.
- `PaperEditSheet` and `CaptureSheet` replace today's `<dialog>` forms.

### Reader window (layout A)

- **Center:** `PDFView`, continuous scroll, lazy rendering, native zoom (pinch + ⌘+/−), Fit Width / Fit Page.
- **Left (collapsible):** `PDFThumbnailView`.
- **Right inspector (collapsible):** SwiftUI `.inspector`, tabs:
  - *Outline*: `PDFOutline` table of contents, click to navigate.
  - *Annotations*: list of highlights/notes (color swatch, page, snippet), click to jump, swipe/delete.
- **Toolbar:** native find (⌘F) via `PDFView` search, page field + prev/next, zoom + fit modes, display mode (single / continuous / two-up), annotation tools (Highlight, Note, color).
- **AnnotationController:**
  - Highlight: from a text selection, create a `PDFAnnotation(.highlight)` hugging the selection's `selectionsByLine` quads (text-aware, fixes today's box-drag).
  - Note: `PDFAnnotation(.text)` (or freeText) at the click point; edited inline, not via `prompt()`.
  - On create/edit/delete: mutate the `PDFDocument`, write back to the cached file, and upsert/delete the SQLite index row.
  - On open: load annotations from the PDF (truth) and reconcile the index.
- **Night reading** (nice-to-have): invert page colors via a Core Image filter on the `PDFView` layer.

### Capture & arXiv (ported from `server.py`)

- **CaptureServer:** loopback HTTP on `127.0.0.1:8765`, started at launch. Implements the endpoints the extension/bookmarklet use, at minimum `POST /api/capture` with today's JSON contract; permissive local CORS so the extension origin works. Configurable port (env/setting) to match today.
- **MetadataService:** prefer official arXiv API (`export.arxiv.org/api/query`) for title/authors/abstract; fall back to page `<meta>` scraping (SwiftSoup) for non-arXiv.
- **ArxivFigureService:** scrape arXiv HTML (`arxiv.org/html/<id>`) for figures; port `choose_arxiv_visual` heuristics (teaser-like first, pipeline/method second, filter placeholders/logos).
- **PDFDownloader:** resolve PDF URL (port `pdf_url_for_paper` arXiv normalization), download to cache dir, validate PDF magic bytes.
- **BibTeXExporter:** generate `.bib` from saved papers (port `export_bibtex`).

### Settings

`@AppStorage`: library view mode, sort, reader display mode, night reading on/off, capture port. A small Settings scene.

## Data Flow

**Capture:** extension/bookmarklet → `POST 127.0.0.1:8765/api/capture` → CaptureServer → MetadataService (arXiv API / meta) → create paper in LibraryStore → ArxivFigureService enrich (async) → `ValueObservation` pushes update → library UI refreshes.

**Read & annotate:** open Reader window → PDFDownloader ensures cached PDF → `PDFView` loads it → user selects text, Highlight/Note → AnnotationController writes `PDFAnnotation` into the file + upserts index row → Annotations inspector updates.

## Error Handling

- Capture: invalid/unfetchable URL → server returns JSON error; UI shows a non-blocking message; partial metadata still saved.
- PDF download: missing/invalid PDF → reader shows an inline error with an "Open in browser" fallback (port today's behavior).
- Annotation write-back: if the file write fails, keep the in-memory annotation, surface an error, and do not drop the index row silently.
- Embedded server: if the port is taken, fall back to the next port and record it (extension host permission note in docs).

## Testing

- **Unit:** arXiv ID/PDF-URL normalization, metadata parsing (fixture XML/HTML), figure-choice heuristic, BibTeX generation, tag normalization, annotation index round-trip.
- **Store:** GRDB migrations, CRUD, FTS search results.
- **Capture server:** POST `/api/capture` with sample payloads → expected DB rows (the extension contract is the regression surface).
- **Manual (on Mac):** reader search/zoom/fit, thumbnails, outline navigation, highlight hugs text, note edit inline, annotations persist and open correctly in Preview, all three library view modes, switcher persistence.

## Build / Run Reality

Source and the Xcode project are authored in this repo, but **compiling, running, and iterating happen on the user's Mac in Xcode** — the dev Linux box cannot build macOS apps. The implementation plan must be structured for incremental build-on-Mac: scaffold project → data layer → library shell → one view mode → reader shell → annotations → capture server → arXiv services → polish.

## Open Questions / Future

- Optional one-time importer for the existing SQLite library + cached PDFs.
- Two-up / multi-PDF tabs, reading-position memory across launches.
- Code signing / notarization for distribution beyond local use.
```
