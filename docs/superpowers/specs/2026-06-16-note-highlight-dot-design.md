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

## Revision 2026-06-16: margin placement + hover popover

The first cut placed the dot at the end of the last line, which overlaps following text when
the sentence ends mid-paragraph, and the dot was inert.

**Margin placement.** Put the dot in the page's blank side margin instead of inline:
- Side from the selection: if the selection sits entirely left of the page's horizontal centre
  (`selection.bounds.maxX < mediaBox.midX`) → **left** margin, else → **right** margin. This yields
  left-column notes on the left, right-column notes on the right, and single-column (full-width)
  notes on the right.
- `x` = just outside the selected text on that side (an ~8pt gap past `selection.bounds` min/maxX),
  clamped to the page, so the dot hugs the words in the margin/gutter rather than sitting at the page
  edge; `y` = vertically aligned to the note's **first** line. The indexed region is the union of the
  selection bounds and the dot rect, so region-based delete still removes highlight + dot together.

**Hover (grow + popover).** `AnnotatingPDFView` adds a mouse-moved tracking area. When the pointer is
over a note dot (a `.circle` annotation), the dot grows a few points and a small read-only `NSPopover`
(SwiftUI `Text` via `NSHostingController`) shows the note's text, pointing inward over the page;
moving off the dot restores its size and dismisses the popover. The grow is a transient bounds change
that is restored on exit (not persisted). Note text is identified via the annotation's `contents`.

## Revision 2026-06-16b: auto selection menu + dot matches highlight colour

- **Dot colour = highlight colour.** Drop the fixed accent; the dot's fill (and the note's indexed
  swatch colour) is the current highlight colour. Solid fill reads more saturated than the
  translucent highlight, so it stays visible.
- **Auto selection menu.** `AnnotatingPDFView.mouseUp` floats a transient `NSPopover` next to a fresh
  text selection with **Highlight** and **Add Note** buttons (a SwiftUI `SelectionMenu`), reusing the
  existing `onHighlight`/`onNote` wiring; it dismisses on click-away, a new selection, or after an
  action. The right-click menu remains as a fallback.
