# In-Window PDF Reader — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open the PDF reader inside the main library window (full-window reading mode with a transition) instead of a separate window, and drop the reader's left page-thumbnail sidebar.

**Architecture:** A `readingPaperID` on `LibraryViewModel` drives a conditional swap in `LibraryContentView` between the library and a new `EmbeddedReader` (reuses `ReaderViewModel`/`PDFKitView`/`ReaderToolbar`/`InspectorPanel`, no thumbnails, Back button). The standalone reader `WindowGroup` and `ReaderWindow`/`ThumbnailSidebar` are removed; all Read entry points call `vm.openReader(paper)`.

**Tech Stack:** Swift/SwiftUI, PDFKit.

**Environment note:** building requires macOS + Xcode (run on the user's Mac). This is a UI/hosting change — no `swift test`-level logic changes; verify by building/running.

**Coupling note:** Tasks 2–5 are a tightly-coupled set (reader hosting swap). The app builds cleanly after **Task 5**; intermediate tasks may leave Read temporarily inert but still compile.

**Reference spec:** `docs/superpowers/specs/2026-06-15-in-window-reader-design.md`

---

## File map

**Create:**
- `NimbleScholar/Reader/EmbeddedReader.swift` — in-window reader (replaces `ReaderWindow`)

**Modify:**
- `NimbleScholar/Library/LibraryViewModel.swift` — `readingPaperID` + `openReader`/`closeReader`
- `NimbleScholar/Reader/ReaderToolbar.swift` — remove `showThumbs`
- `NimbleScholar/Library/LibraryContentView.swift` — conditional content + transition + ⌘O
- `NimbleScholar/Library/PaperDetailView.swift`, `PaperContextMenu.swift`, `GalleryView.swift`, `RowsView.swift` — repoint Read to `vm.openReader`
- `NimbleScholar/App/NimbleScholarApp.swift` — remove the reader `WindowGroup`

**Delete:**
- `NimbleScholar/Reader/ReaderWindow.swift`, `NimbleScholar/Reader/ThumbnailSidebar.swift`

---

## Task 1: Reading state on the view model

**Files:**
- Modify: `NimbleScholar/Library/LibraryViewModel.swift`

- [ ] **Step 1: Add the state + actions.** Add a published property next to the other `@Published`s (e.g. after `@Published var editingPaper: Paper? = nil`):

```swift
    @Published var readingPaperID: Int64? = nil   // non-nil → in-window reading mode
```

Add the actions next to `toggleImportant(_:)`:

```swift
    func openReader(_ paper: Paper) { readingPaperID = paper.id }
    func closeReader() { readingPaperID = nil }
```

- [ ] **Step 2: Verify it builds (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: builds (state unused so far).

- [ ] **Step 3: Commit.**

```bash
git add NimbleScholar/Library/LibraryViewModel.swift
git commit -m "feat(app): reading-mode state on LibraryViewModel"
```

---

## Task 2: Drop the thumbnails toggle from `ReaderToolbar`

**Files:**
- Modify: `NimbleScholar/Reader/ReaderToolbar.swift`

- [ ] **Step 1: Remove the `showThumbs` binding.** In `ReaderToolbar`, delete the property:

```swift
    @Binding var showThumbs: Bool
```

- [ ] **Step 2: Remove the thumbnails toggle button.** Delete the leading toolbar item:

```swift
        ToolbarItem(placement: .navigation) {
            Button { showThumbs.toggle() } label: { Image(systemName: "sidebar.left") }
        }
```

(The first remaining item becomes the `ToolbarItemGroup` with search/zoom/etc.)

- [ ] **Step 3: Commit.** (This temporarily breaks `ReaderWindow.swift`, which is deleted in Task 5; if executing strictly task-by-task, expect a compile error until then.)

```bash
git add NimbleScholar/Reader/ReaderToolbar.swift
git commit -m "feat(reader): remove thumbnails toggle from toolbar"
```

---

## Task 3: `EmbeddedReader`

**Files:**
- Create: `NimbleScholar/Reader/EmbeddedReader.swift`

- [ ] **Step 1: Create `EmbeddedReader.swift`.**

```swift
import SwiftUI
import PDFKit
import NimbleScholarCore

/// The PDF reader hosted inside the library window (full-window reading mode).
/// Reuses the reader internals; no page-thumbnail sidebar. `onClose` returns to the library.
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
                    .keyboardShortcut(.cancelAction)
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

- [ ] **Step 2: Commit.**

```bash
git add NimbleScholar/Reader/EmbeddedReader.swift
git commit -m "feat(reader): EmbeddedReader — in-window reader without thumbnails"
```

---

## Task 4: Host the reader in `LibraryContentView`

**Files:**
- Modify: `NimbleScholar/Library/LibraryContentView.swift`

- [ ] **Step 1: Swap `body` for conditional content; move the split view into `libraryBody`.** Replace the current `var body: some View { … }` with:

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

    @ViewBuilder private var libraryBody: some View {
        NavigationSplitView {
            SidebarView().environmentObject(vm).frame(minWidth: 200)
        } detail: {
            detail
        }
        .safeAreaInset(edge: .top) {
            if let e = env.startupError {
                Text("⚠️ Running on a temporary in-memory library — nothing will be saved.\n\(e)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
        .task { vm.reload() }
        .sheet(item: $vm.editingPaper) { PaperEditSheet(paper: $0).environmentObject(vm) }
    }
```

- [ ] **Step 2: Repoint ⌘O.** Replace `openSelectedReader()` and remove the openWindow env. Change:

```swift
    @Environment(\.openWindow) private var openWindow
```

to remove that line, and replace the method with:

```swift
    private func openSelectedReader() {
        if vm.multiSelection.count == 1, let id = vm.multiSelection.first,
           let paper = vm.papers.first(where: { $0.id == id }) {
            vm.openReader(paper)
        }
    }
```

- [ ] **Step 3: Commit.**

```bash
git add NimbleScholar/Library/LibraryContentView.swift
git commit -m "feat(app): host the reader in-window with a transition"
```

---

## Task 5: Repoint callers + remove the standalone window

**Files:**
- Modify: `NimbleScholar/Library/PaperDetailView.swift`, `PaperContextMenu.swift`, `GalleryView.swift`, `RowsView.swift`, `NimbleScholar/App/NimbleScholarApp.swift`
- Delete: `NimbleScholar/Reader/ReaderWindow.swift`, `NimbleScholar/Reader/ThumbnailSidebar.swift`

- [ ] **Step 1: `PaperDetailView` Read button.** Replace:

```swift
                    Button {
                        if let id = paper.id { openWindow(id: "reader", value: id) }
                    } label: { Label("Read", systemImage: "book") }
                    .buttonStyle(.borderedProminent)
```

with:

```swift
                    Button { vm.openReader(paper) } label: { Label("Read", systemImage: "book") }
                    .buttonStyle(.borderedProminent)
```

and remove the now-unused line `@Environment(\.openWindow) private var openWindow`.

- [ ] **Step 2: `PaperContextMenu` Read item.** Replace:

```swift
            Button { if let id = paper.id { openWindow(id: "reader", value: id) } } label: {
                Label("Read", systemImage: "book")
            }
```

with:

```swift
            Button { vm.openReader(paper) } label: {
                Label("Read", systemImage: "book")
            }
```

and remove `@Environment(\.openWindow) private var openWindow`.

- [ ] **Step 3: `GalleryView` double-click.** Replace:

```swift
        .onTapGesture(count: 2) { if let id = paper.id { openWindow(id: "reader", value: id) } }
```

with:

```swift
        .onTapGesture(count: 2) { vm.openReader(paper) }
```

and remove `@Environment(\.openWindow) private var openWindow`.

- [ ] **Step 4: `RowsView` Read button + double-click.** Replace:

```swift
            Button("Read") { if let id = paper.id { openWindow(id: "reader", value: id) } }
```

with:

```swift
            Button("Read") { vm.openReader(paper) }
```

and replace:

```swift
        .onTapGesture(count: 2) { if let id = paper.id { openWindow(id: "reader", value: id) } }
```

with:

```swift
        .onTapGesture(count: 2) { vm.openReader(paper) }
```

and remove `@Environment(\.openWindow) private var openWindow`.

- [ ] **Step 5: Remove the reader `WindowGroup`.** In `NimbleScholarApp.swift`, delete the whole scene:

```swift
        // One reader window per paper id.
        WindowGroup("Reader", id: "reader", for: Int64.self) { $paperID in
            ReaderWindow(paperID: paperID).environmentObject(env)
        }
        .defaultSize(width: 1100, height: 820)
```

- [ ] **Step 6: Delete the unused reader-window files.**

```bash
git rm NimbleScholar/Reader/ReaderWindow.swift NimbleScholar/Reader/ThumbnailSidebar.swift
```

- [ ] **Step 7: Build + verify (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: builds. Clicking **Read** (detail, right-click, double-click, rows button, ⌘O)
slides the PDF in full-window with **no left thumbnails**; the inspector toggles; highlight/
note/export work; **Back** (button or Escape) animates back to the library; the blue dot
clears on open.

- [ ] **Step 8: Commit.**

```bash
git add NimbleScholar/Library/PaperDetailView.swift NimbleScholar/Library/PaperContextMenu.swift NimbleScholar/Library/GalleryView.swift NimbleScholar/Library/RowsView.swift NimbleScholar/App/NimbleScholarApp.swift
git commit -m "feat(app): open reader in-window everywhere; remove standalone reader window"
```

---

## Self-review notes

- **Spec coverage:** `readingPaperID`/`openReader`/`closeReader` (Task 1); thumbnails removed from toolbar (Task 2); `EmbeddedReader` no-thumbnail + Back/Escape (Task 3); conditional content + transition + ⌘O (Task 4); repoint all 6 Read entry points + remove window + delete `ReaderWindow`/`ThumbnailSidebar` (Task 5). All spec sections mapped.
- **Type/name consistency:** `LibraryViewModel.readingPaperID`/`openReader(_:)`/`closeReader()`; `EmbeddedReader(paperID:onClose:)`; `ReaderToolbar(pdfView:displayMode:showInspector:vm:)` (no `showThumbs`); reused `ReaderViewModel.load()`/`flushSave()`/`paper`. Consistent.
- **Coupling:** Tasks 2–5 are interdependent (the toolbar signature, `EmbeddedReader`, and the window/file removals must land together). The app compiles cleanly after Task 5; if executed strictly per-task, the toolbar-signature change (Task 2) leaves `ReaderWindow.swift` uncompilable until it's deleted in Task 5 — expected, called out.
- **Unused env:** every `@Environment(\.openWindow)` in the Library views is removed once its only use (opening the reader) is repointed.
