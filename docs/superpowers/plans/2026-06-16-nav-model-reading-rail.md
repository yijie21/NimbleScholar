# Navigation Model Cleanup + Reading Icon Rail — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the app's selection/navigation state into one owner with named transitions, fix the related stale-state bugs, and replace the disappearing sidebar (during reading) with a slim clickable icon rail.

**Architecture:** `LibraryViewModel` owns one selection (`multiSelection`) + `readingPaperID`; `scope`'s `didSet` exits reading + reloads, and `reload()` prunes any selection no longer visible. A new `ReadingRail` (56pt, scope icons + tag dots) shows beside the split view while reading; clicking a scope sets `vm.scope` (which exits the reader).

**Tech Stack:** Swift/SwiftUI.

**Environment note:** building requires macOS + Xcode (run on the user's Mac). UI/navigation change — verify by building/running; no `swift test` coverage (the view model is app-target and tied to `AppEnvironment.shared`).

**Reference spec:** `docs/superpowers/specs/2026-06-16-nav-model-reading-rail-design.md`

---

## File map

**Create:**
- `NimbleScholar/Library/ReadingRail.swift` — the icon rail shown while reading

**Modify:**
- `NimbleScholar/Library/LibraryViewModel.swift` — unify selection, transition methods, exit-on-scope-change, prune
- `NimbleScholar/Library/GalleryView.swift`, `RowsView.swift` — use `multiSelection`
- `NimbleScholar/Library/LibraryContentView.swift` — host the rail; ⌘O via `currentPaperID`

---

## Task 1: Unify selection + transitions in the view model

**Files:**
- Modify: `NimbleScholar/Library/LibraryViewModel.swift`

- [ ] **Step 1: Exit reading on any scope change.** Change the `scope` property's `didSet`:

```swift
    @Published var scope: LibraryScope = .all { didSet { readingPaperID = nil; reload() } }
```

- [ ] **Step 2: Remove the separate `selection`; add `currentPaperID` + `select`.** Delete:

```swift
    @Published var selection: Paper.ID? = nil
```

Add (next to `multiSelection`):

```swift
    /// The single "current paper" (one selected). Drives the detail pane, ⌘O, openReader.
    var currentPaperID: Int64? { multiSelection.count == 1 ? multiSelection.first : nil }

    func select(_ paper: Paper) { if let id = paper.id { multiSelection = [id] } }
```

- [ ] **Step 3: Drop the `selection` write in `openReader`.** Replace:

```swift
    func openReader(_ paper: Paper) {
        guard let id = paper.id else { return }
        selection = id
        multiSelection = [id]          // so the three-pane detail shows this paper
        readingPaperID = id
    }
    func closeReader() { readingPaperID = nil }
```

with:

```swift
    func openReader(_ paper: Paper) {
        guard let id = paper.id else { return }
        multiSelection = [id]
        readingPaperID = id
    }
    func closeReader() { readingPaperID = nil }
```

- [ ] **Step 4: Prune stale selection at the end of `reload()`.** After the line
`papers = floatImportant(ordered)` add:

```swift
        // Drop any selection that's no longer in the visible list (e.g. after a scope change).
        let visible = Set(papers.compactMap(\.id))
        if !multiSelection.isSubset(of: visible) { multiSelection = multiSelection.intersection(visible) }
```

- [ ] **Step 5: Verify it builds (macOS).** (Gallery/Rows still reference `vm.selection` until Task 2 — expect a compile error there until then.)

Run: `bash scripts/mac_bootstrap.sh full generate`
Expected: `LibraryViewModel.swift` compiles; the only remaining `selection` references are in Gallery/Rows (fixed next).

- [ ] **Step 6: Commit.**

```bash
git add NimbleScholar/Library/LibraryViewModel.swift
git commit -m "feat(app): unify selection, exit reading on scope change, prune stale selection"
```

---

## Task 2: Point Gallery/Rows at the unified selection

**Files:**
- Modify: `NimbleScholar/Library/GalleryView.swift`, `NimbleScholar/Library/RowsView.swift`

- [ ] **Step 1: GalleryView — selected ring + tap.** Replace:

```swift
    private var selected: Bool { vm.selection == paper.id }
```

with:

```swift
    private var selected: Bool { vm.multiSelection.contains(paper.id ?? -1) }
```

and replace:

```swift
        .onTapGesture { vm.selection = paper.id }
```

with:

```swift
        .onTapGesture { vm.select(paper) }
```

- [ ] **Step 2: RowsView — selected ring + tap.** Apply the identical two replacements in `RowsView.swift`:

```swift
    private var selected: Bool { vm.multiSelection.contains(paper.id ?? -1) }
```

and

```swift
        .onTapGesture { vm.select(paper) }
```

- [ ] **Step 3: Verify it builds (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: builds; tapping a card in Gallery/Rows selects it; switching to Three-pane keeps
that selection; ⌘O opens it.

- [ ] **Step 4: Commit.**

```bash
git add NimbleScholar/Library/GalleryView.swift NimbleScholar/Library/RowsView.swift
git commit -m "feat(app): Gallery/Rows use the unified multiSelection"
```

---

## Task 3: `ReadingRail`

**Files:**
- Create: `NimbleScholar/Library/ReadingRail.swift`

- [ ] **Step 1: Create `ReadingRail.swift`.**

```swift
import SwiftUI
import NimbleScholarCore

/// A slim icon rail shown in place of the sidebar while reading. Clicking a scope sets
/// `vm.scope`, whose didSet exits the reader and shows that scope.
struct ReadingRail: View {
    @EnvironmentObject var vm: LibraryViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                scopeButton(.all, "tray.full", "All papers")
                scopeButton(.important, "star.fill", "Important", tint: .yellow)
                scopeButton(.unread, "circle.fill", "Unread")
                scopeButton(.recent, "clock", "Recently added")
                scopeButton(.untagged, "tag.slash", "Untagged")
                if !vm.tagCounts.isEmpty {
                    Divider().padding(.horizontal, 12).padding(.vertical, 4)
                    ForEach(vm.tagCounts, id: \.name) { tc in
                        Button { vm.scope = .tag(tc.name) } label: {
                            Circle().fill(TagColor.color(for: tc.name))
                                .frame(width: 12, height: 12)
                                .frame(width: 40, height: 30)
                                .background(isTag(tc.name) ? Color.accentColor.opacity(0.2) : .clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .help(tc.name)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 56)
        .background(.bar)
    }

    @ViewBuilder
    private func scopeButton(_ scope: LibraryScope, _ icon: String, _ name: String, tint: Color? = nil) -> some View {
        Button { vm.scope = scope } label: {
            Image(systemName: icon)
                .foregroundStyle(tint ?? .primary)
                .frame(width: 40, height: 30)
                .background(vm.scope == scope ? Color.accentColor.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(name)
    }

    private func isTag(_ name: String) -> Bool {
        if case .tag(let t) = vm.scope { return t == name }
        return false
    }
}
```

- [ ] **Step 2: Commit.**

```bash
git add NimbleScholar/Library/ReadingRail.swift
git commit -m "feat(app): ReadingRail — icon rail of scopes shown while reading"
```

---

## Task 4: Host the rail in `LibraryContentView`

**Files:**
- Modify: `NimbleScholar/Library/LibraryContentView.swift`

- [ ] **Step 1: Wrap the split view in an HStack with the rail.** Replace the start of `body`
(`var body: some View { NavigationSplitView(columnVisibility: $columns) {`) so the split
view moves into a `splitView` property and `body` adds the rail:

```swift
    var body: some View {
        HStack(spacing: 0) {
            if vm.readingPaperID != nil {
                ReadingRail()
                    .environmentObject(vm)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            splitView
        }
        .animation(.easeInOut(duration: 0.25), value: vm.readingPaperID)
    }

    @ViewBuilder private var splitView: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView().environmentObject(vm).frame(minWidth: 200)
        } detail: {
            detail
        }
        .onChange(of: vm.readingPaperID) { _, reading in
            withAnimation(.easeInOut(duration: 0.25)) {
                columns = (reading != nil) ? .detailOnly : .all
            }
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

(Everything from the old `body` after `} detail: { detail }` — the `onChange`, the two
`safeAreaInset`s, `.task`, and `.sheet` — moves verbatim onto `splitView`. The `detail`
computed property below is unchanged.)

- [ ] **Step 2: Route ⌘O through `currentPaperID`.** Replace `openSelectedReader()`:

```swift
    private func openSelectedReader() {
        if let id = vm.currentPaperID, let paper = vm.papers.first(where: { $0.id == id }) {
            vm.openReader(paper)
        }
    }
```

- [ ] **Step 3: Verify (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: builds. Open a paper → the full sidebar collapses and a 56pt **icon rail** slides
in (All / Important / Unread / Recent / Untagged + tag dots), the active scope highlighted.
Clicking a rail icon **exits the reader** and shows that scope with the full sidebar back.
Deleting the current tag while reading also exits the reader.

- [ ] **Step 4: Commit.**

```bash
git add NimbleScholar/Library/LibraryContentView.swift
git commit -m "feat(app): show the reading icon rail beside the library; ⌘O uses currentPaperID"
```

---

## Self-review notes

- **Spec coverage:** unified selection + `currentPaperID`/`select` (Task 1); exit-reading-on-scope-change via `scope.didSet` + prune in `reload()` (Task 1); Gallery/Rows on `multiSelection` (Task 2); `ReadingRail` (Task 3); rail hosting + ⌘O via `currentPaperID` (Task 4). Rail click → `vm.scope = …` → `didSet` exits reader (spec's "exit reader + show scope"). All spec sections mapped. (The spec's `setScope` method is realized as `scope.didSet`, which is simpler and covers the sidebar binding, the rail, and tag rename/delete uniformly.)
- **Type/name consistency:** `LibraryViewModel.multiSelection` / `currentPaperID` / `select(_:)` / `openReader(_:)` / `closeReader()` / `scope`; `ReadingRail`; Gallery/Rows use `vm.multiSelection.contains` + `vm.select`. `LibraryScope` is `Equatable` so `vm.scope == scope` is valid for non-tag cases; tag uses `isTag(_:)`.
- **Coupling note:** Tasks 1–2 are a pair (removing `selection` breaks Gallery/Rows until Task 2). Build cleanly after Task 2; Tasks 3–4 add the rail.
- **No double sidebar:** while reading, `columns = .detailOnly` collapses the split view's sidebar, and the rail stands in for it; `.all` restores it when reading ends.
