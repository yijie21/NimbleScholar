# Nimble Scholar — Hardening & Completion (Design)

**Date:** 2026-06-14
**Status:** Approved for planning
**Author:** Brainstormed with Claude Code

## Summary

Nimble Scholar is a working native macOS paper manager (Swift/SwiftUI + PDFKit, a tested
`NimbleScholarCore` SwiftPM package, an embedded capture server). It was built quickly across
~25 commits and now needs a deliberate hardening pass: fix bugs, optimize performance, add the
features a paper manager should have, remove dead code, and document it — so it becomes a neat,
canonical, reliable app.

## Goals

Across four equally-weighted dimensions:

1. **Stability / bug-free** — correctness audit, edge cases, data integrity, no silent failures.
2. **Performance** — no main-thread stalls, no N+1 queries, smooth scrolling and annotations.
3. **Missing features** — capture quality, reading workflow, import/backup, power-user.
4. **Code neatness + documentation** — canonical structure, dead-code removal, doc comments,
   an architecture doc.

## Non-Goals

- Rewriting the architecture (it's sound: core package + SwiftUI app).
- iOS/iPad, cloud sync, multi-user.
- Incremental PDF annotation writes (whole-file write stays, just debounced) — revisit only if
  large-PDF annotation still stalls after Phase 2.

## Constraints & Verification

The development box (Linux) **cannot compile or run Swift** — only the user's Mac can. Therefore:

- **Methodology:** static file-by-file audit + fixes, with logic moved into the testable
  `NimbleScholarCore` package and covered by `swift test` wherever practical.
- **UI verification:** the user builds on the Mac after each phase (`bash scripts/mac_bootstrap.sh
  full run`) and reports compile errors / behavior; we iterate and keep `main` green.
- Each phase is a self-contained batch of commits.

## Phase 1 — Correctness & cleanup

### Dead code removal
- Delete `NimbleScholar/NimbleScholarApp.swift` (the minimal boot `@main`, superseded by
  `App/NimbleScholarApp.swift`) and `NimbleScholar/BootCheckView.swift`. The `mac_bootstrap.sh`
  `c` mode that referenced them is obsolete now that the full app is the only target; drop the
  `c` source set or repoint it.
- Delete `NimbleScholarCore/.../Placeholder.swift` (version stub) and its smoke-test assertion,
  or fold the version constant somewhere meaningful.

### Concrete bugs to fix
1. **Annotation deletion is inconsistent.** Inspector "Delete" (`InspectorPanel`) removes the
   SQLite index row via `store.deleteAnnotation` but does **not** remove the `PDFAnnotation` from
   the document/file, so the highlight stays visible in the PDF while vanishing from the list.
   - Fix: establish the **PDF file as the source of truth** for annotation geometry. On reader
     load, reconcile the index against the PDF (drop index rows whose annotations no longer
     exist). Deleting from the inspector must find and remove the matching `PDFAnnotation` on the
     page, persist, then delete the index row. Deleting on-page (already implemented) stays.
2. **FTS query is not sanitized.** `LibraryStore.ftsQuery` appends `*` to raw tokens; a query
   containing FTS operators/special characters (`:`, `-`, `^`, `"`, `(`, `)`, `*`, `AND`) can
   raise a SQLite FTS5 syntax error, which `try?` swallows → search silently returns nothing.
   - Fix: wrap each token as a quoted FTS string (`"token"*` with internal quotes doubled) or
     strip FTS-significant characters; add unit tests for queries like `c++`, `AT&T`, `"deep"`,
     `attention:`.
3. **Full-table scan to open a paper.** `ReaderViewModel.init` calls `store.allPapers()` to find
   one paper by id. Add `LibraryStore.paper(id:)` and use it.

### Edge-case audit (fix or surface gracefully)
- Empty library → friendly empty state in each view mode.
- PDF download failure / not a PDF / no PDF URL → clear reader message + "Open in Browser"
  fallback (exists; verify all paths).
- Network/proxy failure during capture or figure fetch → capture still saves with available
  metadata; user-visible note on hard failure.
- Malformed / missing arXiv Atom or generic meta → no crash, partial metadata saved.
- Non-paper URL capture → saved with URL as title; no crash.
- Audit `try!`, force-unwraps (`!`), and silent `try?` for spots that should log or surface.

## Phase 2 — Performance

1. **Eliminate N+1 tag queries (top priority).** `vm.tags(for:)` queries `paper_tags` per paper,
   called from Rows/Gallery/Detail on every render and every `reload()`. Add
   `LibraryStore.allTagsByPaper() -> [Int64: [String]]` (one query joining `paper_tags`+`tags`),
   load it once per `reload()` into the view model, and have views read the cached map.
2. **Paper lookup by id** (from Phase 1) removes the reader's full-table scan.
3. **Thumbnail cache**: add a disk-size cap (e.g. evict oldest beyond ~200 MB) and optional
   background prewarm right after a capture so the first scroll is instant.
4. **Observation coalescing**: confirm `observeChanges` doesn't fire redundant reloads; ensure
   `reload()` is cheap (single search query + the new batched tag map + tag counts).
5. Keep annotation saves debounced (Phase 2 baseline already merged); measure large-PDF behavior.

## Phase 3 — Features

### Capture quality
- **Duplicate detection**: before creating, look up an existing paper by normalized arXiv id (or
  exact URL). If found, **update** it (merge new metadata, keep tags/annotations) and surface
  "Updated existing" rather than creating a copy. Add `LibraryStore.paper(matchingURL:)` /
  `paper(arxivID:)`.
- **Reveal in Finder** and **Open in default PDF app** for the cached PDF (port the old
  `open_local_pdf` behavior) — in the paper context menu and detail pane.
- **Re-fetch metadata** action on a paper (re-runs resolve + figure enrichment, updates fields).

### Reading workflow
- **Read/Unread status**: add a `read INTEGER NOT NULL DEFAULT 0` column (+ migration). Show an
  unread dot on cards; toggle via context menu; add an **"Unread"** sidebar smart filter. Opening
  the reader marks a paper read.
- **Export annotations to Markdown**: a per-paper action producing a `.md` with the paper title,
  metadata, and each highlight/note (page + text), saved via a save panel.

### Import & backup
- **Local PDF import**: accept dropped `.pdf` files (and "Open With") → create a paper whose
  `pdf_path` points at a copy in the cache; title from the filename or PDF metadata; thumbnail
  from page 1.
- **Library backup & restore**: "Back Up Library…" zips the SQLite DB + `storage/pdfs/` to a
  user-chosen location; "Restore…" replaces the store from a backup (with confirmation).

### Power-user
- **Keyboard shortcuts**: Delete removes the selected paper (with confirm), ⌘O / Return opens the
  reader, ⌘F focuses search, ⌘⌫ in multi-select bulk-deletes.
- **Multi-select**: list/grid multi-selection driving bulk **Delete / Add tag / Download PDFs**.

## Phase 4 — Documentation

- Doc comments (`///`) on all `public` core APIs and non-obvious UI logic.
- New **`docs/ARCHITECTURE.md`**: module map (core vs app), data flow (capture → store →
  observation → UI; reader → annotation → file + index), key types, "how to add a feature,"
  and build/run.
- Update the user `README.md` for the new features (read/unread, import, backup, shortcuts).

## Data-model changes (with migrations)

- `papers.read INTEGER NOT NULL DEFAULT 0` (migration `v3-read`).
- New store methods: `paper(id:)`, `paper(arxivID:)` / `paper(matchingURL:)`,
  `allTagsByPaper()`, `setRead(paperID:read:)`, plus annotation reconciliation helpers.
- Migrations remain idempotent and additive; no destructive changes.

## Error handling

- Replace silent `try?` with logged failures where a user-visible outcome depends on it
  (capture, download, backup/restore, import).
- Surface capture failures in the in-app sheet (done) and consider a transient banner for
  background (extension) capture failures.

## Testing

Expand `NimbleScholarCoreTests`:
- FTS sanitization (special-character queries return sensibly, never throw).
- Duplicate detection (same arXiv id updates, doesn't duplicate; tags/annotations preserved).
- Read-status round-trip + migration from a v2 DB.
- `allTagsByPaper()` correctness.
- Backup zip round-trip (write → restore → same rows) — logic testable in core.
- Markdown export formatting.
- Metadata edge cases (empty/garbled Atom, missing meta tags).

UI behavior verified by build-and-run on the Mac per phase.

## Rollout

Phases land in order (1 → 4); each is a batch of commits the user builds and verifies before the
next. `main` stays green. Data migrations are additive so existing libraries upgrade cleanly.
