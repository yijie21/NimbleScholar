# Nimble Scholar

Nimble Scholar is a local, tag-first paper manager for collecting, organizing, reading, and annotating research papers. It was built mainly around arXiv workflows: one-click capture from a browser, automatic PDF URL detection, arXiv HTML figure extraction, local PDF caching, and an in-app PDF reader with highlights and notes.

The app is intentionally lightweight. The backend is a single Python HTTP server with SQLite storage. The frontend is plain HTML, CSS, and JavaScript. The macOS app is a small native WebKit wrapper around the local web app.

## Current Capabilities

- Local paper library stored in SQLite.
- Tag-based organization instead of folder-first management.
- Search across title, authors, abstract, DOI, venue, URL, summaries, and tags.
- Automatic tag colors in the left sidebar and paper cards.
- Manual paper entry and editing.
- URL capture from the app.
- Bookmarklet capture helper.
- Chrome/Edge extension for one-click capture from the current browser tab.
- arXiv metadata extraction from abstract pages.
- arXiv PDF URL normalization from `abs`, `pdf`, `html`, DOI, and arXiv ID fields.
- arXiv HTML figure extraction for paper cards.
- Figure preference order: teaser-like figure first, pipeline-like figure second, otherwise blank.
- Figure preview modal with click-outside-to-close behavior.
- One-sentence summary field directly on each paper card.
- Quick tag add directly on each paper card.
- Per-tag removal directly on each paper card.
- Paper deletion from the card or edit dialog.
- BibTeX export.
- Bulk arXiv figure enrichment for already-saved papers.
- Bulk PDF download for already-saved papers.
- Open paper PDF in the system browser.
- Open cached local PDF in the default system PDF reader.
- Built-in PDF reader.
- Continuous scrolling PDF pages.
- Page input, previous/next controls, zoom buttons, trackpad pinch zoom, and `Ctrl` wheel zoom.
- Text selection inside PDFs.
- Selection toolbar for highlight, note, and copy.
- Manual highlight and note tools.
- Saved highlight/note list in the right panel.
- Delete annotations from the right panel.
- Right-click or two-finger click a highlight/note to show a delete popover.
- `Command` + click PDF web links to open them in the system browser.
- Standalone Apple Silicon macOS app bundle.

## Repository Layout

```text
paper_app/
  README.md
  server.py
  paper_app.sqlite3
  storage/
    pdfs/
  static/
    index.html
    styles.css
    app.js
    vendor/
      pdfjs/
        pdf.min.mjs
        pdf.worker.min.mjs
  extension/
    manifest.json
    background.js
    popup.html
    popup.css
    popup.js
    icon-*.png
  scripts/
    NimbleScholarApp.m
    macos_launcher.c
    prepare_macos_app.sh
    generate_icons.py
  assets/
    nimble-scholar-1024.png
  Nimble Scholar.app/
    Contents/
      Info.plist
      MacOS/NimbleScholar
      Resources/
        app/
        seed/
```

Important files:

- `server.py`: Python backend, database schema, metadata extraction, PDF downloading, annotation API, static file serving.
- `static/index.html`: application shell, dialogs, PDF reader layout, annotation popovers.
- `static/styles.css`: Apple-style visual design, paper cards, PDF reader, annotation UI.
- `static/app.js`: frontend state, rendering, API calls, paper card behavior, PDF.js integration, annotations, zoom, link handling.
- `static/vendor/pdfjs/`: vendored PDF.js runtime used by the built-in PDF reader.
- `extension/`: Chrome/Edge extension for one-click capture into the local app.
- `scripts/NimbleScholarApp.m`: native macOS WebKit wrapper.
- `scripts/prepare_macos_app.sh`: rebuilds `Nimble Scholar.app` from current source files.
- `scripts/generate_icons.py`: generates app and extension icons.

## Running The App

### macOS App

Open:

```text
/Users/zed/Desktop/paper_app/Nimble Scholar.app
```

The app starts a local Python server and loads it in a native WebKit window. The wrapper uses `/usr/bin/python3` and targets Apple Silicon, so it should not require Rosetta on M-series Macs.

The default port is `8765`. To override it:

```bash
PAPER_APP_PORT=8781 open "/Users/zed/Desktop/paper_app/Nimble Scholar.app"
```

Logs are written to:

```text
~/Library/Logs/Nimble Scholar/nimble-scholar.log
```

### Terminal Web App

From the repository root:

```bash
python3 server.py
```

Then open:

```text
http://127.0.0.1:8765
```

To run on another port:

```bash
PORT=8781 python3 server.py
```

To use the same data directory as the macOS app:

```bash
PAPER_APP_DATA_DIR="$HOME/Library/Application Support/Nimble Scholar" python3 server.py
```

## Data Locations

Terminal mode defaults to the repository directory:

```text
/Users/zed/Desktop/paper_app/paper_app.sqlite3
/Users/zed/Desktop/paper_app/storage/pdfs/
```

The macOS app defaults to:

```text
~/Library/Application Support/Nimble Scholar/paper_app.sqlite3
~/Library/Application Support/Nimble Scholar/storage/pdfs/
```

The server reads `PAPER_APP_DATA_DIR` at startup. `DB_PATH` is `PAPER_APP_DATA_DIR/paper_app.sqlite3`; `PDF_DIR` is `PAPER_APP_DATA_DIR/storage/pdfs`.

## Database Schema

The schema is initialized in `server.py:init_db()`.

### `papers`

Stores paper metadata and local PDF cache information.

```text
id INTEGER PRIMARY KEY AUTOINCREMENT
title TEXT NOT NULL
authors TEXT NOT NULL DEFAULT ''
year TEXT NOT NULL DEFAULT ''
venue TEXT NOT NULL DEFAULT ''
doi TEXT NOT NULL DEFAULT ''
url TEXT NOT NULL DEFAULT ''
pdf_url TEXT NOT NULL DEFAULT ''
pdf_path TEXT NOT NULL DEFAULT ''
summary TEXT NOT NULL DEFAULT ''
teaser_url TEXT NOT NULL DEFAULT ''
pipeline_url TEXT NOT NULL DEFAULT ''
abstract TEXT NOT NULL DEFAULT ''
notes TEXT NOT NULL DEFAULT ''
source TEXT NOT NULL DEFAULT ''
created_at INTEGER NOT NULL
updated_at INTEGER NOT NULL
```

### `tags`

Stores normalized tag names.

```text
id INTEGER PRIMARY KEY AUTOINCREMENT
name TEXT NOT NULL UNIQUE
```

### `paper_tags`

Many-to-many relation between papers and tags.

```text
paper_id INTEGER NOT NULL REFERENCES papers(id) ON DELETE CASCADE
tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE
PRIMARY KEY (paper_id, tag_id)
```

### `pdf_annotations`

Stores built-in PDF reader highlights and notes.

```text
id INTEGER PRIMARY KEY AUTOINCREMENT
paper_id INTEGER NOT NULL REFERENCES papers(id) ON DELETE CASCADE
page INTEGER NOT NULL
kind TEXT NOT NULL DEFAULT 'highlight'
x REAL NOT NULL DEFAULT 0
y REAL NOT NULL DEFAULT 0
width REAL NOT NULL DEFAULT 0
height REAL NOT NULL DEFAULT 0
color TEXT NOT NULL DEFAULT '#ffd966'
text TEXT NOT NULL DEFAULT ''
created_at INTEGER NOT NULL
updated_at INTEGER NOT NULL
```

Annotation coordinates are page-relative fractions from `0` to `1`, not absolute pixels. This lets annotations survive zoom changes and PDF rerendering.

## Backend Architecture

`server.py` uses only the Python standard library:

- `ThreadingHTTPServer` and `SimpleHTTPRequestHandler` for HTTP.
- `sqlite3` for persistence.
- `urllib.request` for metadata, PDF, and arXiv HTML fetching.
- `HTMLParser` subclasses for metadata and arXiv figure extraction.
- `subprocess` for opening URLs or local PDFs through macOS.

Core backend sections:

- Constants: `ROOT`, `STATIC_DIR`, `DATA_DIR`, `DB_PATH`, `PDF_DIR`.
- Parsers:
  - `MetadataParser`: extracts title and meta tags from general pages.
  - `ArxivFigureParser`: extracts figure image URLs and captions from arXiv HTML.
- Database:
  - `db()`
  - `init_db()`
  - `row_to_paper()`
  - `list_papers()`
  - `create_paper()`
  - `update_paper()`
  - `delete_paper()`
  - `save_tags()`
  - `list_tags()`
- arXiv:
  - `extract_arxiv_id()`
  - `extract_arxiv()`
  - `fetch_arxiv_figures()`
  - `choose_arxiv_visual()`
  - `enrich_paper_figures()`
  - `enrich_all_arxiv_figures()`
- PDFs:
  - `pdf_url_for_paper()`
  - `download_pdf_for_paper()`
  - `download_all_pdfs()`
  - `pdf_file_for_paper()`
  - `open_local_pdf()`
- PDF annotations:
  - `list_pdf_annotations()`
  - `create_pdf_annotation()`
  - `delete_pdf_annotation()`
- Export:
  - `export_bibtex()`
- HTTP:
  - `Handler.do_GET()`
  - `Handler.do_POST()`
  - `Handler.do_PUT()`
  - `Handler.do_DELETE()`

## API Reference

All JSON endpoints use `Content-Type: application/json`.

### Papers

`GET /api/papers`

Returns all papers, optionally filtered.

Query parameters:

- `q`: search string.
- `tag`: tag name.

Response:

```json
{
  "papers": []
}
```

`POST /api/papers`

Creates a paper from JSON form data.

Accepted fields:

```json
{
  "title": "Paper title",
  "authors": "Author One, Author Two",
  "year": "2026",
  "venue": "arXiv",
  "doi": "arXiv:2606.00000",
  "url": "https://arxiv.org/abs/2606.00000",
  "pdf_url": "https://arxiv.org/pdf/2606.00000",
  "summary": "One sentence takeaway.",
  "teaser_url": "https://...",
  "pipeline_url": "https://...",
  "abstract": "...",
  "notes": "...",
  "source": "arxiv.org",
  "tags": "tag-one, tag-two"
}
```

Response:

```json
{
  "paper": {}
}
```

`PUT /api/papers/<id>`

Updates a paper. The payload shape is the same as `POST /api/papers`.

`DELETE /api/papers/<id>`

Deletes a paper, its tag links, annotations, and cached PDF file if the cached file is under the app PDF directory.

Response:

```json
{
  "ok": true
}
```

### Capture

`POST /api/capture`

Captures a paper from a URL. The server fetches metadata from the page, merges it with the supplied payload, creates the paper, and enriches arXiv figures when possible.

Typical payload:

```json
{
  "url": "https://arxiv.org/abs/2606.00000",
  "tags": "to-read",
  "title": "Optional title from extension",
  "authors": "Optional authors",
  "doi": "Optional DOI",
  "pdf_url": "Optional PDF URL",
  "teaser_url": "Optional image URL",
  "abstract": "Optional abstract",
  "source": "arxiv.org"
}
```

### Tags

`GET /api/tags`

Returns only tags currently used by at least one paper.

Response:

```json
{
  "tags": [
    {
      "name": "vla",
      "count": 2
    }
  ]
}
```

Unused tags disappear from the sidebar because `list_tags()` joins through `paper_tags`.

### PDF Cache And Opening

`POST /api/papers/<id>/download-pdf`

Downloads or reuses a local PDF for one paper.

Payload:

```json
{
  "overwrite": false
}
```

`POST /api/pdfs/download-all`

Downloads PDFs for all saved papers.

`GET /api/papers/<id>/pdf`

Serves the cached PDF inline. If the PDF is missing, the server downloads it first.

`POST /api/papers/<id>/open-local-pdf`

Downloads the PDF if needed and opens it with the system default PDF reader. The implementation uses `/usr/bin/open` on macOS.

Payload:

```json
{
  "reader_app": ""
}
```

The current UI sends an empty `reader_app`, so macOS chooses the default app.

`POST /api/open-url`

Opens an external `http` or `https` URL in the system browser.

Payload:

```json
{
  "url": "https://example.com"
}
```

### arXiv Figure Enrichment

`POST /api/enrich/arxiv-figures`

Rechecks saved arXiv papers and updates `teaser_url` or `pipeline_url`.

Payload:

```json
{
  "overwrite": false
}
```

When `overwrite` is false, papers with existing meaningful visuals are skipped.

### PDF Annotations

`GET /api/papers/<id>/annotations`

Returns saved highlights and notes for one paper.

`POST /api/papers/<id>/annotations`

Creates a highlight or note.

Payload:

```json
{
  "page": 1,
  "kind": "highlight",
  "x": 0.1,
  "y": 0.2,
  "width": 0.3,
  "height": 0.02,
  "color": "#ffd966",
  "text": "Selected text or note"
}
```

`DELETE /api/annotations/<id>`

Deletes one annotation.

### Export

`GET /api/export/bibtex`

Downloads a BibTeX file generated from saved papers.

## Frontend Architecture

The frontend is in `static/` and has no build step.

### `static/index.html`

Defines the app structure:

- Sidebar and tag filters.
- Top toolbar.
- Paper list.
- PDF reader overlay view.
- Selection toolbar.
- Annotation delete popover.
- Paper edit dialog.
- Capture dialog.
- Image preview dialog.

### `static/styles.css`

Contains the visual system:

- macOS-inspired layout and controls.
- Sidebar and tag color treatment.
- Paper card layout and quick controls.
- Dialogs and preview modals.
- PDF reader layout.
- Text, link, and annotation overlay layers.
- Selection toolbar and annotation delete popover.

Layer order in the PDF page shell:

```text
canvas
text-layer
pdf-link-layer
annotation-layer
```

The link layer is pointer-transparent. `Command` + click is handled by coordinate hit-testing in JavaScript so text selection still works normally.

### `static/app.js`

`state` is the central frontend state object. It stores:

- loaded papers and tags,
- current search and tag filter,
- current sort mode,
- PDF reader state,
- current PDF annotations,
- zoom state,
- active annotation popover state.

Important frontend functions:

- General:
  - `api()`: fetch wrapper.
  - `load()`: fetch papers and tags, then render.
  - `renderPapers()`: render paper cards and attach card events.
  - `renderTags()`: render sidebar tag filters.
  - `paperFromForm()` and `fillForm()`: edit dialog mapping.
- Paper interactions:
  - `openPaperInBrowser()`
  - `openPaperLocally()`
  - `openPaperReader()`
  - `deletePaperFromCard()`
  - `addQuickTag()`
  - `removeQuickTag()`
  - `saveQuickSummary()`
- PDF reader:
  - `renderPdfPages()`
  - `makePdfPageShell()`
  - `scrollToReaderPage()`
  - `readerAnchor()` and `restoreReaderAnchor()`
  - `applyLiveZoom()` and `commitLiveZoom()`
- PDF text selection:
  - `selectionRectsByPage()`
  - `updateSelectionToolbar()`
  - `highlightSelection()`
  - `noteSelection()`
  - `copySelectionText()`
- PDF annotations:
  - `saveAnnotation()`
  - `deleteAnnotation()`
  - `renderAnnotations()`
  - `renderAnnotationList()`
  - `annotationAtPoint()`
  - `showAnnotationMenu()`
- PDF links:
  - `renderPdfLinks()`
  - `pdfLinkAtPoint()`
  - `pdfAnnotationUrl()`

## Main User Workflows

### Capture An arXiv Paper

1. User opens an arXiv abstract page in the browser.
2. User clicks the Nimble Scholar browser extension.
3. Extension reads page metadata and default tags.
4. Extension posts to `POST /api/capture`.
5. Server fetches page metadata again as a fallback.
6. Server normalizes arXiv ID and PDF URL.
7. Server creates the paper in SQLite.
8. Server tries arXiv HTML figure enrichment.
9. Frontend reloads papers and tags.

### Read And Annotate A Paper

1. User clicks `Read` on a paper card.
2. Frontend posts to `/api/papers/<id>/download-pdf`.
3. Server downloads the PDF if needed.
4. Frontend loads annotations from `/api/papers/<id>/annotations`.
5. PDF.js loads `/api/papers/<id>/pdf`.
6. Frontend renders all pages continuously.
7. User selects text and chooses Highlight or Note.
8. Frontend stores each highlight/note through `POST /api/papers/<id>/annotations`.
9. Saved annotations are rendered on the PDF overlay and in the right panel.

### Delete A Highlight Or Note

There are two deletion paths:

- Right-click or two-finger click a highlight/note in the PDF, then click Delete in the popover.
- Click Delete in the right annotation panel.

Both paths call `DELETE /api/annotations/<id>` and then remove the annotation from frontend state.

### Open A Link Inside A PDF

1. PDF.js exposes link annotations through `page.getAnnotations({ intent: "display" })`.
2. `renderPdfLinks()` creates invisible rectangles for external links.
3. User holds `Command` and clicks the link area.
4. `pdfLinkAtPoint()` finds the matching link rectangle by pointer coordinates.
5. Frontend posts to `/api/open-url`.
6. Server opens the URL in the system browser.

## Browser Extension

The extension lives in `extension/` and uses Manifest V3.

Files:

- `manifest.json`: extension metadata, permissions, local host permissions.
- `background.js`: service worker that reads the active tab, extracts metadata, and posts to the local app.
- `popup.html`: popup UI.
- `popup.css`: popup styling.
- `popup.js`: popup behavior and settings.
- `icon-*.png`: extension icons.

The extension posts to:

```text
http://127.0.0.1:8765/api/capture
```

Required browser permissions:

- `activeTab`
- `scripting`
- `storage`

Host permissions:

- `http://127.0.0.1:8765/*`
- `http://localhost:8765/*`

Install locally:

1. Open Chrome or Edge.
2. Go to `chrome://extensions`.
3. Enable Developer Mode.
4. Click Load unpacked.
5. Select `/Users/zed/Desktop/paper_app/extension`.
6. Start `Nimble Scholar.app`.
7. Open an arXiv page and click the extension button.

The popup auto-captures on open by calling `loadSettings().then(capture)`.

## macOS App Wrapper

The app bundle is generated by:

```bash
scripts/prepare_macos_app.sh
```

This script:

1. Ensures icons exist.
2. Copies `server.py` into `Nimble Scholar.app/Contents/Resources/app/`.
3. Copies `static/` into the app payload.
4. Copies the current repository database and storage folder into `Resources/seed/`.
5. Compiles `scripts/NimbleScholarApp.m` into `Contents/MacOS/NimbleScholar`.
6. Runs `plutil -lint` on `Info.plist`.

The wrapper:

- creates a native `NSWindow`,
- embeds a `WKWebView`,
- checks whether the local server is already running,
- starts `/usr/bin/python3 app/server.py` if needed,
- passes `PORT` and `PAPER_APP_DATA_DIR`,
- seeds the user data directory on first launch,
- writes logs to `~/Library/Logs/Nimble Scholar/nimble-scholar.log`,
- loads `http://127.0.0.1:<port>`.

Rebuild the app bundle after changing any of these files:

- `server.py`
- `static/*`
- `scripts/NimbleScholarApp.m`
- icon assets

## Development Notes

### No Build Step

The web app is plain browser code. There is no npm, bundler, or transpiler. Edit `static/app.js`, `static/styles.css`, and `static/index.html` directly.

Because PDF.js is imported as an ES module, the app should be served over HTTP by `server.py`. Opening `static/index.html` directly from Finder is not the supported development path.

### Static Serving

`Handler.translate_path()` maps `/` to `static/index.html` and serves other static files from `STATIC_DIR`.

### CORS

`Handler.end_headers()` adds permissive local CORS headers:

```text
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type
```

This is what allows the browser extension to post into the local app.

### Tags

Tags are normalized in `normalize_tags()`:

- comma and semicolon separated strings are accepted,
- whitespace is collapsed,
- tag names are lowercased,
- duplicate tags are removed.

When updating a paper, `save_tags()` replaces the paper's tag set. The sidebar only shows tags returned by `list_tags()`, which counts currently linked papers.

### Paper Figures

Paper cards use:

```text
teaser_url first
pipeline_url second
blank if neither exists
```

arXiv figure extraction uses the HTML page:

```text
https://arxiv.org/html/<arxiv_id>
```

`choose_arxiv_visual()` looks at figure IDs, alt text, and captions. It prefers teaser-like or overview-like figures, then pipeline/method/architecture figures, then the first valid figure.

Placeholder icons, favicons, arXiv logos, and static browse images are filtered out.

### PDF Cache

`download_pdf_for_paper()` resolves the PDF URL, downloads it, checks that it looks like a PDF, stores it under `storage/pdfs/`, and records the absolute path in `papers.pdf_path`.

PDF filenames are generated by `safe_pdf_name()`.

### Built-In PDF Reader

The reader uses PDF.js from `static/vendor/pdfjs/`.

Rendering steps:

1. `openPaperReader()` ensures a PDF is cached.
2. `pdfjsLib.getDocument('/api/papers/<id>/pdf')` loads it.
3. `renderPdfPages()` renders every page into a canvas.
4. PDF text content is rendered through `pdfjsLib.TextLayer`.
5. PDF link annotations are converted to invisible link rectangles.
6. Saved app annotations are rendered in the annotation layer.

The reader intentionally renders all pages continuously because papers are usually read as long documents. For very large PDFs, future work could add virtualized rendering.

### Annotation Model

Highlights and notes are app-level annotations, not written back into the PDF file. They are stored in SQLite and rendered as overlays.

Each annotation stores:

- page number,
- type: `highlight` or `note`,
- page-relative rectangle,
- color,
- selected text or note text.

Deletion is supported through:

- right-click or two-finger click on the PDF overlay,
- right panel Delete button.

### PDF Link Behavior

Links inside PDFs are opened only with `Command` + click. Normal click remains available for selection and app annotation behavior.

Only `http` and `https` URLs are opened. Other PDF annotation destinations are ignored for now.

## Common Development Tasks

### Add A New Paper Field

1. Add the column in `server.py:init_db()`.
2. Add a migration check for older databases.
3. Add the field in `row_to_paper()`.
4. Add it to `create_paper()` and `update_paper()`.
5. Add form markup in `static/index.html`.
6. Add it to `fields`, `paperFromForm()`, and `fillForm()` in `static/app.js`.
7. Render it in `renderPapers()` if it should appear on cards.
8. Rebuild the macOS app with `scripts/prepare_macos_app.sh`.

### Add A New API Endpoint

1. Add backend helper functions near related code in `server.py`.
2. Add route handling in `Handler.do_GET`, `do_POST`, `do_PUT`, or `do_DELETE`.
3. Return JSON with `self.json_response()`.
4. Call it from `static/app.js` through `api()`.
5. If the extension needs it, update `extension/manifest.json` host permissions only if the port or origin changes.

### Change Paper Card UI

Edit `renderPapers()` in `static/app.js` and the related classes in `static/styles.css`.

Card click behavior:

- Single click outside controls opens the edit dialog.
- Double click outside controls opens the paper PDF in the browser.
- Elements with `data-no-card-open` do not trigger card open behavior.

### Change PDF Reader Behavior

Most reader behavior is in `static/app.js` from the reader helper functions through the event listeners near the end of the file.

Useful areas:

- Rendering: `renderPdfPages()`
- Zoom: `applyLiveZoom()` and `commitLiveZoom()`
- Page tracking: `updateCurrentPageFromScroll()`
- Selection: `updateSelectionToolbar()`
- Annotation saving: `saveAnnotation()`
- Annotation deletion: `deleteAnnotation()`, `showAnnotationMenu()`
- PDF links: `renderPdfLinks()`, `pdfLinkAtPoint()`

### Change Browser Extension Capture

Edit:

- `extension/background.js` for page metadata extraction and API payload.
- `extension/popup.js` for user interaction and settings.
- `extension/popup.html` and `extension/popup.css` for popup UI.

Reload the unpacked extension from `chrome://extensions` after changes.

### Rebuild The App Bundle

```bash
scripts/prepare_macos_app.sh
```

Then open:

```text
/Users/zed/Desktop/paper_app/Nimble Scholar.app
```

## Verification Commands

Basic Python syntax check:

```bash
python3 -m py_compile server.py
```

Run local server:

```bash
python3 server.py
```

Run local server against macOS app data:

```bash
PAPER_APP_DATA_DIR="$HOME/Library/Application Support/Nimble Scholar" PORT=8781 python3 server.py
```

Check papers:

```bash
curl -s http://127.0.0.1:8765/api/papers
```

Create a temporary annotation:

```bash
curl -s -X POST http://127.0.0.1:8765/api/papers/1/annotations \
  -H 'Content-Type: application/json' \
  -d '{"page":1,"kind":"highlight","x":0.1,"y":0.1,"width":0.1,"height":0.02,"color":"#ffd966","text":"temporary test"}'
```

Delete an annotation:

```bash
curl -s -X DELETE http://127.0.0.1:8765/api/annotations/<annotation_id>
```

Rebuild app:

```bash
scripts/prepare_macos_app.sh
```

## Troubleshooting

### `OSError: [Errno 48] Address already in use`

Another server is already using the port. Use a different port:

```bash
PORT=8781 python3 server.py
```

For the macOS app:

```bash
PAPER_APP_PORT=8781 open "/Users/zed/Desktop/paper_app/Nimble Scholar.app"
```

### App Opens But Data Looks Different

Terminal mode and macOS app mode may use different data directories.

Terminal default:

```text
/Users/zed/Desktop/paper_app/
```

macOS app default:

```text
~/Library/Application Support/Nimble Scholar/
```

Run terminal mode with the macOS app data directory if needed:

```bash
PAPER_APP_DATA_DIR="$HOME/Library/Application Support/Nimble Scholar" python3 server.py
```

### Browser Extension Says It Cannot Save

Check:

- `Nimble Scholar.app` is open.
- The local server is reachable at `http://127.0.0.1:8765`.
- The extension is loaded from the local `extension/` directory.
- Host permissions include the current local port.

### Figures Do Not Appear

Possible reasons:

- The paper is not an arXiv paper.
- arXiv HTML is unavailable for that paper.
- The HTML has no useful figure image.
- The detected image was filtered as a placeholder.
- Network fetching failed.

Use `Update Figures` in the toolbar to retry enrichment for saved papers.

### PDF Does Not Open Locally

Possible reasons:

- The PDF URL is missing or invalid.
- The paper page blocks PDF downloading.
- The downloaded content was not a PDF.
- macOS has no default PDF reader configured.

The Browser button can still open the remote PDF URL.

### Annotation Delete Does Not Appear

Use two-finger click or right-click directly on the highlighted region or note dot. You can also delete the same annotation from the right panel.

### PDF Link Does Not Open

Only external `http` and `https` PDF link annotations are supported. Hold `Command` while clicking the link area.

## Known Limitations

- App annotations are not embedded into the PDF file itself.
- Internal PDF links, page destinations, DOI resolver links without explicit URL annotations, and mail links are ignored.
- The PDF reader renders all pages at once, which may be slow for very large PDFs.
- Metadata extraction is heuristic and depends on publisher or arXiv page markup.
- The extension targets Chrome/Edge-style Manifest V3 browsers.
- There is no automated test suite yet.

## Design Principles

- Keep the app local-first.
- Keep paper organization tag-first.
- Prefer simple, inspectable code over frameworks for this prototype.
- Preserve fast capture and reading workflows.
- Avoid adding build tooling unless the app grows enough to justify it.
- Treat `server.py`, `static/app.js`, and SQLite schema changes as the main integration surface.
