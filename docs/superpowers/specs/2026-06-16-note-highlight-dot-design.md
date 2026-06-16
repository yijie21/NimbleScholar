# Reader annotations: highlight-on-note + elegant note marker

**Date:** 2026-06-16
**Status:** Approved

## Problem

The note workflow is poor:

1. **"Add Note" ignores the selection.** It places the note at the *page center*
   (`pdfView.convert(bounds.center, to: page)`), disconnected from the selected text, and
   adds no highlight.
2. **The marker is ugly.** A `.text` PDFAnnotation always renders as a large sticky-note icon
   whose appearance is fixed.
3. **The Outline inspector tab is unused.**

## Design

### 1. "Add Note" highlights the selection and drops a small dot

Replace `addNote(text:at:on:pdfView:)` with `addNote(text:selection:in:)`:

- Highlight **each line** of the selection in the current highlight color (same line-aware logic
  as plain `highlight()`), setting each annotation's `contents` to the note text.
- Draw a **small filled circle (~7pt)** just past the end of the last line — a `.circle`
  PDFAnnotation in a **fixed accent color** (`#4a90d9`), so "has a note" reads the same regardless
  of the highlight color. Its `contents` is the note text (hover tooltip).
- Index it as `kind: "note"`, `color: <note accent hex>`, `snippet: <note text>`, anchored to the
  whole-selection bounds (`selection.bounds(for:)`).
- Both the toolbar **Note** button and the right-click **"Add Note…"** use the current selection;
  with nothing selected they are a no-op (notes are always attached to text now).
- Plain **Highlight** is unchanged (color only, no dot, no note text).

### 2. Deleting a note removes its highlight(s) + dot together

A note (and a multi-line highlight) is several PDFAnnotations but one index row. Make deletion
region-based: `removeAnnotations(inRegionOf:on:)` removes every annotation intersecting the row's
recorded region (expanded ~16pt horizontally / 6pt vertically to include the trailing dot). Used by
both right-click delete and the inspector's swipe-delete. This also fixes a pre-existing bug where
deleting a multi-line highlight left orphaned line rectangles.

Right-click delete identifies which row was clicked by finding the index row whose (padded) region
intersects the clicked annotation, falling back to nearest-origin.

### 3. Remove the Outline tab

`InspectorPanel` drops the Outline segment and its `outline` view. Tabs become
**Annotations | Chat**, defaulting to Annotations.

## Scope / non-goals

- Existing old-style notes (center sticky-note icons) are left as-is; users can right-click → Delete
  them. Only *new* notes use the new rendering.
- No note-editing UI beyond the existing create + delete; note text is shown via hover tooltip and
  the Annotations inspector list.

## Touched files

`NimbleScholar/Reader/AnnotationController.swift`, `PDFKitView.swift`, `ReaderToolbar.swift`,
`InspectorPanel.swift`.
