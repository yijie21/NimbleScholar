# Robust PDF figure extraction (caption-anchored)

**Date:** 2026-06-16
**Status:** Approved (validated against arXiv 2601.05237)

## Problem

`PDFFigureExtractor` finds a figure region by locating **raster image placements** (`Do` on Image
XObjects) in the page content stream. Many papers draw figures as **vector graphics** (TikZ,
matplotlib/Illustrator vector) with only tiny raster sub-tiles, so the region finder rejects them
(`minRegionSide=64`) and returns nil. The card then falls back to rendering the first page (a wall of
text). Confirmed on 2601.05237: figure pages have raster placements of only ~66×43 / 71×41, but every
figure has a clean `Fig. N:` caption.

The renderer (`render`, `ctx.drawPDFPage` clipped to a rect) already draws vector content fine — only
the *region finder* is raster-blind.

## Design

### 1. Caption-anchored region finder (primary; vector + raster)

Add `captionAnchoredFigure(path:maxPages:)`, tried before the existing raster method:

- Open with **PDFKit** for text; get each page's lines via
  `page.selection(for: mediaBox)?.selectionsByLine()` → `(bounds, string)`.
- **Column** x-range = min/max x of "wide" lines (`width > 0.45·pageWidth`).
- **Caption** = the topmost line matching `^(Figure|Fig\.?)\s*\d+` (case-insensitive; tables excluded).
- **Figure region** = the band *above* the caption (PDF y-up: from `caption.maxY` upward), column-wide,
  with the top found by a density walk: step up in 2pt bins, where a bin's coverage = widest line's
  `width/colWidth`; keep extending through sparse rows (figure labels) and **stop when a real paragraph
  — ≥22pt of continuous `coverage ≥ 0.55` — is reached** (its near edge becomes the figure top). Clamp
  to the page; require height ≥ 48pt, width ≥ 64pt.
- Render the region with the existing `render(region:of:)` via the matching `CGPDFPage` (same PDF user
  space; rotated pages are skipped by `render`).
- Return the **first** page (in order) that yields a region — i.e. the teaser / Fig 1.

Fallbacks unchanged: existing raster-region method, then (caller) first-page render.

Known minor: a running header/email can ride along at the top of the band; acceptable for a thumbnail,
can be trimmed later.

### 2. Regenerate figures for already-saved papers

PDF-extracted figures live only in `ThumbnailCache`, keyed by `teaser|pipeline|pdfPath`, so improving
the extractor doesn't refresh cached cards. Two changes:

- Add a **cache version** token to the key (bump now) → every card re-derives with the new extractor on
  next launch, automatically.
- Add `ThumbnailCache.clearAll()` and a **⋯ → "Regenerate figures from PDF"** action
  (`LibraryViewModel.regenerateFiguresFromPDF`) that clears the cache and reloads (which re-prewarms),
  for on-demand refresh.

## Touched files

`NimbleScholar/Library/PDFFigureExtractor.swift`, `ThumbnailCache.swift`, `LibraryViewModel.swift`,
`LibraryContentView.swift`.
