# Design — In-Window PDF Reader (no thumbnail sidebar)

Date: 2026-06-15
Status: Implemented; **revised** after testing.

## Revision (2026-06-15): reader in the three-pane DETAIL pane (not full-window)

User feedback: the full-window mode felt like leaving the library. New behavior — the
reader shows in the **three-pane detail pane**, with the **paper list + sidebar still
visible**:
- `openReader(_:)` selects the paper (`selection`/`multiSelection`) and sets `readingPaperID`.
- `LibraryContentView.detail` forces the three-pane layout while `readingPaperID != nil`
  (so Read from Gallery/Rows lands in a detail pane too); the full-window swap is removed.
- `ThreePaneView`'s right pane shows `EmbeddedReader` (with a fade) when its selected paper
  is the one being read; Back/Esc → `closeReader()` restores `PaperDetailView`.
- `EmbeddedReader` (PDF + inspector, no thumbnails) and the window removal are unchanged.

The original full-window design below is superseded by this revision.

## Overview

Open the PDF reader **inside the main library window** (full-window reading mode) with a
smooth transition, instead of a separate window — so the user stays in context. While
reading, the sidebar + paper list + detail are replaced by the PDF (the right inspector
stays toggleable); a **Back** button returns to the library. The reader's **left page-
thumbnail sidebar is removed** (the user scrolls the PDF directly).

Decisions (from brainstorming):
- **Full-window reading mode** (hide sidebar/list/detail), not a detail-pane swap.
- **In-window only** — remove the standalone reader window.
- **Remove** the thumbnail sidebar.

The reader internals (`ReaderViewModel`, `PDFKitView`, annotations, AI chat, inspector,
toolbar minus thumbnails) are reused unchanged — this is a hosting change.

## 1. State (`LibraryViewModel`)

- `@Published var readingPaperID: Int64?` — non-nil ⇒ reading mode.
- `func openReader(_ paper: Paper) { readingPaperID = paper.id }`
- `func closeReader() { readingPaperID = nil }`

Opening still "marks read": the reader's `ReaderViewModel.load()` already removes the
`to-read` tag.

## 2. `LibraryContentView` — conditional content + transition

Extract the current body (the `NavigationSplitView` with its `.safeAreaInset`s, `.task`,
`.sheet(editingPaper)`, drop destination, ⌘O button, and `.toolbar`) into a computed
`libraryBody`. The new `body`:

```swift
var body: some View {
    Group {
        if let id = vm.readingPaperID {
            EmbeddedReader(paperID: id) { vm.closeReader() }
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            libraryBody
                .transition(.opacity)
        }
    }
    .animation(.easeInOut(duration: 0.25), value: vm.readingPaperID)
}
```

(The library `.onAppear { env.startCodeWatcherIfNeeded() }` stays on the outer view in
`NimbleScholarApp`, so the watcher is unaffected by reading mode.)

## 3. `EmbeddedReader` (new — `NimbleScholar/Reader/EmbeddedReader.swift`)

Replaces `ReaderWindow`. Reuses `ReaderViewModel` / `PDFKitView` / `ReaderToolbar` /
`InspectorPanel`. Wrapped in a `NavigationStack` so `.toolbar` / `.inspector` /
`.navigationTitle` host correctly in-window. **No `ThumbnailSidebar`.**

```swift
struct EmbeddedReader: View {
    @StateObject private var vm: ReaderViewModel
    @State private var displayMode: PDFDisplayMode = .singlePageContinuous
    @State private var showInspector = true
    @State private var pdfView: PDFView?
    let onClose: () -> Void

    init(paperID: Int64?, onClose: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: ReaderViewModel(paperID: paperID))
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            Group {
                if let doc = vm.document {
                    PDFKitView(document: doc, displayMode: $displayMode, vm: vm) { pv in
                        self.pdfView = pv
                        AnnotationController(vm: vm).reconcile(pdfView: pv)
                    }
                } else {
                    ContentUnavailableView(vm.status, systemImage: "doc.richtext")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { vm.flushSave(); onClose() } label: {
                        Label("Library", systemImage: "chevron.left")
                    }
                    .keyboardShortcut(.cancelAction)   // Escape returns to the library
                }
                ReaderToolbar(pdfView: $pdfView, displayMode: $displayMode,
                              showInspector: $showInspector, vm: vm)
            }
            .inspector(isPresented: $showInspector) {
                if let pv = pdfView { InspectorPanel(pdfView: pv, vm: vm) }
                else { Text("—").foregroundStyle(.secondary) }
            }
            .navigationTitle(vm.paper.title)
        }
        .task { await vm.load() }
        .onDisappear { vm.flushSave() }
    }
}
```

## 4. `ReaderToolbar`

Remove the `@Binding var showThumbs` property and the leading `sidebar.left` toggle button
(it only controlled the now-removed thumbnail panel). All other items unchanged.

## 5. Remove the standalone window + repoint callers

- `NimbleScholarApp.swift`: delete the `WindowGroup("Reader", id: "reader", for: Int64.self)
  { … ReaderWindow … }` scene.
- Delete `NimbleScholar/Reader/ReaderWindow.swift` and
  `NimbleScholar/Reader/ThumbnailSidebar.swift` (now unused).
- Replace every `openWindow(id: "reader", value: id)` with `vm.openReader(paper)`:
  - `PaperDetailView` (Read button), `PaperContextMenu` (Read), `GalleryView` (double-click),
    `RowsView` (Read button + double-click), `LibraryContentView.openSelectedReader` (⌘O).
  - Remove now-unused `@Environment(\.openWindow)` declarations in those files.

## Testing
- **Manual:** click Read (from detail, context menu, double-click, rows button, ⌘O) →
  the PDF slides in full-window with no left thumbnails; the inspector toggles; highlight/
  note/export still work; **Back** (button or Escape) animates back to the library with the
  selection intact; opening clears the paper's blue dot (to-read tag).
- No unit tests (pure hosting/UI change; `ReaderViewModel` logic unchanged).

## Risks / notes
- The library `.toolbar` and the reader `.toolbar` are mutually exclusive (conditional
  content), so they don't conflict.
- `.sheet(editingPaper)` and the bottom status bar live on `libraryBody`, so they're not
  shown during reading — acceptable (editing/import happen from the library).
- Removing the `reader` `WindowGroup` means ⌘N-style multiple reader windows are gone — by
  design (in-window only).
