# Design — Project & Code (GitHub) Links

Date: 2026-06-15
Status: Approved (pending spec review)

## Overview

Surface a paper's **project page** and **open-source code (GitHub)** links as small
buttons on the detail page. Links are auto-extracted from the cached PDF and the paper's
abstract/landing HTML page; if a project page is found but no GitHub link, the project
page is fetched and scanned for one. When nothing is found, the user can add links
manually. Already-imported papers are backfilled automatically on next launch, each
showing a per-item "Finding links…" status (like the existing PDF/figure backfill).

Decisions (from brainstorming):
- **Sources:** PDF text + abstract/landing HTML page.
- **Project-page detection:** strong signals only (low false positives).
- **Follow project page** to extract a GitHub link when the paper itself has none.
- **Manual entry:** fields in the Edit sheet + an "Add links…" affordance in the detail view.

## 1. Data model

Add to `Paper` (`NimbleScholarCore/Sources/.../Models/Paper.swift`), with snake_case
columns in both `Columns` and `CodingKeys`:
- `projectURL: String = ""`  → `project_url`
- `codeURL: String = ""`     → `code_url`
- `linksScanned: Bool = false` → `links_scanned`

`linksScanned` records that extraction already ran (even with no result), so the backfill
scans each paper once and the detail view can show "Add links…" instead of re-scanning.

Migration `v5-links` in `LibraryStore` (additive, idempotent, after `v4-chat`):
```sql
ALTER TABLE papers ADD COLUMN project_url TEXT NOT NULL DEFAULT '';
ALTER TABLE papers ADD COLUMN code_url TEXT NOT NULL DEFAULT '';
ALTER TABLE papers ADD COLUMN links_scanned INTEGER NOT NULL DEFAULT 0;
```
Links are **not** added to `papers_fts` (no search requirement).

## 2. Core: `LinkExtractor` (pure, unit-tested)

`NimbleScholarCore/Sources/NimbleScholarCore/Services/LinkExtractor.swift`:

```swift
public struct ExtractedLinks: Equatable {
    public var projectURL: String?
    public var codeURL: String?
}
public struct HTMLAnchor: Equatable { public let href: String; public let label: String }
```

- `static func extract(text: String, anchors: [HTMLAnchor] = []) -> ExtractedLinks`
  - **codeURL:** first match of `https?://github\.com/<owner>/<repo>` in `text` or in any
    anchor href. Normalize: drop a trailing `.git`, strip trailing `).,;]>` and quotes.
    Reject bare `github.com/<owner>` (no repo) and `*.github.io` hosts.
  - **projectURL (strong signals only):**
    1. an anchor whose `label` matches `(?i)project\s*(page|website|site)?|home\s*page|website`
       and whose `href` is http(s) and not arXiv/DOI/`github.com`; else
    2. a `*.github.io` URL (in text or anchors); else
    3. a `sites.google.com` URL.
- `static func codeURL(in text: String) -> String?` and
  `static func codeURL(inAnchors:) -> String?` — reused for the "follow project page" pass.
- `static func anchors(inHTMLData data: Data) -> [HTMLAnchor]` — SwiftSoup; returns `<a>`
  href + trimmed visible text. Keeps HTML parsing in Core.

Tested in `LinkExtractorTests`: GitHub found in line-wrapped text; `.git`/punctuation
stripped; bare-owner and `github.io` rejected as code; project page detected from a
labeled anchor and from a `github.io` URL; arXiv/DOI ignored; `anchors(inHTMLData:)`
parses a small HTML fixture.

## 3. App: `LinkFinder` (PDF + network orchestration)

`NimbleScholar/Library/LinkFinder.swift` (app target; PDFKit is AppKit-only):

```swift
enum LinkFinder {
    static func find(for paper: Paper, session: URLSession, followProject: Bool = true) async -> ExtractedLinks
}
```
Steps:
1. **PDF text:** open `paper.pdfPath` with `PDFDocument`. Collect link-annotation URLs
   (clean) from every page + `document.string` (fallback). Join into one text blob.
2. **Abstract/landing HTML:** fetch arXiv `https://arxiv.org/abs/<id>` (when
   `ArxivService.extractID` matches) else the landing page (`LibraryViewModel.landingPageURL`
   logic, reused). Parse with `LinkExtractor.anchors(inHTMLData:)`.
3. `var links = LinkExtractor.extract(text: pdfText, anchors: htmlAnchors)`.
4. **Follow project page:** if `links.projectURL != nil && links.codeURL == nil &&
   followProject`, fetch the project page HTML, and set
   `links.codeURL = LinkExtractor.codeURL(inAnchors: anchors) ?? LinkExtractor.codeURL(in: text)`.
5. Return `links`. All network via the passed `session` (proxy-aware).

Failures (no PDF yet, network error) return whatever was found (possibly empty); the
caller still marks the paper scanned so it isn't retried forever. When nothing is found,
the user adds links via the Edit sheet / "Add links…" (section 5).

## 4. Backfill + per-item status (`LibraryViewModel`)

Reuse the existing auto-complete loop:
- `needsCompletion(_:)` also returns `true` when `!p.linksScanned` **and** the paper has a
  scan source (a local PDF, an arXiv id, or a landing page).
- `complete(_:)` gains **step 3** after the figure + PDF steps:
  ```swift
  if !cur.linksScanned {
      ActivityCenter.shared.beginItem(id, "Finding links…")
      let links = await LinkFinder.find(for: cur, session: AppEnvironment.shared.networkSession)
      cur.projectURL = links.projectURL ?? cur.projectURL
      cur.codeURL = links.codeURL ?? cur.codeURL
      cur.linksScanned = true
      _ = try? store.update(cur)
  }
  ```
- Existing papers (already have PDFs) therefore get scanned once on next load, showing
  per-item "Finding links…" plus the bottom "Preparing papers — n/m" bar. `linksScanned`
  prevents re-loops. The toolbar "Load missing…" (`retryAllIncomplete`) re-arms them.

## 5. UI

**Detail view** (`PaperDetailView`) — add a links row under the Read/Browser buttons:
- If `projectURL` non-empty: a small button **Project** (`globe`) opening it in the browser.
- If `codeURL` non-empty: a small button **Code** (`chevron.left.forward.slash`) opening it.
- If both empty: a subtle **"Add links…"** button → `vm.editingPaper = paper` (opens Edit).

**Edit sheet** (`PaperEditSheet`) — add two `TextField`s: **Project URL** (`$paper.projectURL`)
and **Code URL** (`$paper.codeURL`), saved via the existing `vm.save(paper)`. Manually
setting either also implicitly means the paper is "done" (it already has `linksScanned`
set by the backfill, or will be once scanned).

## Testing strategy
- **Unit (`swift test`):** `LinkExtractorTests` — classification + `anchors(inHTMLData:)`
  against fixtures. `LibraryStore` migration smoke (new columns round-trip via `Paper`).
- **Manual:** import/keep a paper with a known GitHub link (e.g. a CVPR paper) and a
  project-page-only paper; confirm the Code/Project buttons appear, the "follow project
  page" pass finds GitHub, "Finding links…" shows during backfill, and "Add links…" +
  Edit fields work when nothing is found.

## Risks / notes
- **Project-page identification is heuristic** — strong-signal-only keeps false positives
  low but will miss some project pages; users can add them manually.
- **PDF text URLs wrap across lines.** Annotation URLs (preferred) avoid this; the text
  regex is a best-effort fallback and tolerates wrapping by also scanning annotation URLs.
- **Backfill cost:** one extra HTML fetch (and possibly a project-page fetch) per paper,
  once. Runs in the existing background loop, one paper at a time, proxy-aware.
