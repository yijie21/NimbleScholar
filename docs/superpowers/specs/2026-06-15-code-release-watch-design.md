# Design — Watch for Code Release

Date: 2026-06-15
Status: Approved (pending spec review)

## Overview

Notify the user when a paper's code is finally open-sourced. Many papers ship a project
page (or arXiv entry) before the code; this feature re-checks code-less papers on a
schedule, detects when a **real** GitHub repo appears (not an empty/README-only
placeholder), records it, and posts a macOS notification that opens the repo on click.

Decisions (from brainstorming):
- **Watch set:** all papers without confirmed code yet that have a re-checkable source.
- **Cadence:** sweep on app launch + a 24h timer while open + a manual "Check for code now".
- **Readiness rule:** a repo counts as released when the GitHub API shows its root has at
  least one file/folder that is **not** just README/LICENSE/.gitignore/CONTRIBUTING/etc.
  An empty repo (API 404 "repository is empty") or a docs-only repo is **not** released.
- **Rate limit:** unauthenticated GitHub API (60/hr). Sweeps stop gracefully on HTTP 403
  and resume next time.
- **Notification:** clicking it opens the GitHub repo (via a notification-center delegate).

This builds on Milestone 4 (`LinkExtractor`/`LinkFinder`, `Paper.projectURL`/`codeURL`) and
reuses `Notifier` (Milestone 3).

## 1. Data model

Add to `Paper`: `codeReady: Bool = false` → column `code_ready`.

Meaning of the code fields together:
- `codeURL` empty → no GitHub link found yet.
- `codeURL` set & `codeReady == false` → a link was found but the repo is empty/placeholder
  (or not yet validated). Still **watched**; not shown as released.
- `codeURL` set & `codeReady == true` → real code; shown with the Code button; watch stops.

Migration `v6-code-ready` (after `v5-links`):
```sql
ALTER TABLE papers ADD COLUMN code_ready INTEGER NOT NULL DEFAULT 0;
```
(`Paper.Columns` and `CodingKeys` gain `codeReady = "code_ready"`.)

## 2. Core: repo-readiness helper (pure, tested)

`NimbleScholarCore/Sources/NimbleScholarCore/Services/GitHubRepo.swift`:
```swift
public enum GitHubRepo {
    /// Parse "https://github.com/<owner>/<repo>" → (owner, repo). nil if not a repo URL.
    public static func ownerRepo(from url: String) -> (owner: String, repo: String)?
    /// Given the names in a repo's root, is there real content beyond docs/meta files?
    public static func isReleased(rootEntryNames: [String]) -> Bool
}
```
`isReleased` returns true if any entry is not a doc/meta file. Doc/meta (case-insensitive,
extension-stripped): `readme`, `license`/`licence`, `contributing`, `code_of_conduct`,
`citation`, `changelog`, `authors`, `notice`, and exact `.gitignore`, `.gitattributes`,
`.github`. Tested: real repo (has `src`/`train.py`) → true; only `README.md` → false;
`README.md` + `LICENSE` + `.gitignore` → false; `ownerRepo` parsing of with/without scheme
and trailing slash.

## 3. App: `GitHubRepoChecker` (network)

`NimbleScholar/Library/GitHubRepoChecker.swift`:
```swift
enum RepoStatus { case released, notReleased, rateLimited, error }
enum GitHubRepoChecker {
    static func check(_ codeURL: String, session: URLSession) async -> RepoStatus
}
```
- Resolve owner/repo via `GitHubRepo.ownerRepo`. GET
  `https://api.github.com/repos/<owner>/<repo>/contents` with headers
  `Accept: application/vnd.github+json` and `User-Agent: NimbleScholar` (GitHub rejects
  no-UA requests with 403).
- `404` → `.notReleased` (empty or missing). `403` → `.rateLimited`. `200` + JSON array →
  `GitHubRepo.isReleased(rootEntryNames:)` ? `.released` : `.notReleased`. Else `.error`.

## 4. App: `CodeWatcher` (orchestration)

`NimbleScholar/Library/CodeWatcher.swift`, a single instance owned by `AppEnvironment`
(started at launch). Holds a 24h repeating `Timer`.

**Watchable paper:** `!codeReady` and either `codeURL` is set (re-check that repo) or a
discovery source exists (`projectURL`, an arXiv id, or a landing page).

**`sweep(force:)`:**
- Throttle: skip if `force == false` and `UserDefaults["lastCodeWatchSweep"]` is < 20h ago;
  otherwise stamp it now. `ActivityCenter.begin("Checking for code…")` … `end()`.
- Read `reconciled = UserDefaults["codeWatchReconciled"]` (first-ever full sweep is silent).
- For each watchable paper (sequential, gentle on the API):
  - **Has a candidate `codeURL`:** `GitHubRepoChecker.check`:
    - `.released` → set `codeReady = true`, save; **notify if `reconciled`**.
    - `.notReleased` → keep watching (no change).
    - `.rateLimited` → stop the sweep now (do **not** set `reconciled`); resume next time.
    - `.error` → skip this paper this round.
  - **No `codeURL` yet:** run `LinkFinder.find`. Persist a newly found `projectURL`. If a
    `codeURL` is found, set it and `check` it: `.released` → `codeReady = true`, save,
    notify if `reconciled`; `.notReleased` → save (keep watching); `.rateLimited` → save,
    stop sweep.
- If the loop finishes without rate-limiting, set `UserDefaults["codeWatchReconciled"] = true`.

**Why the `reconciled` flag:** the first full sweep validates all pre-existing Milestone-4
`codeURL`s and discovers links silently (no notification storm). Every later transition to
`codeReady` is a genuine "they just released it" event and notifies. If the first sweep is
cut short by rate-limiting, `reconciled` stays false so it stays silent until it completes.

**Triggers:** `AppEnvironment.init` kicks off `sweep(force: false)`; the 24h timer repeats
it; a manual menu action calls `sweep(force: true)`.

## 5. Notification (actionable)

Extend `Notifier`:
- `notify(title:body:url:)` stores `url` in the request `userInfo`.
- Set `UNUserNotificationCenter.current().delegate` at launch to a small delegate whose
  `didReceive` opens `userInfo["url"]` with `NSWorkspace`, and whose `willPresent` returns
  `[.banner, .sound]` so notifications show while the app is foreground.
- Code-release notification: title "Code released", body the paper title, `url` = the repo.

## 6. UI

**Detail view** (`PaperDetailView`) — refine the links row:
- Project button when `projectURL` set (unchanged).
- **Code button only when `codeURL` set AND `codeReady`** (GitHub mark; unchanged styling).
- A subtle **"⏳ Watching for code release"** caption when the paper is watchable
  (`!codeReady` and `codeURL` set, or code-less but has a discovery source).
- "Add links…" only when there's nothing to show and nothing to watch.

**Edit sheet** (`PaperEditSheet`) — in the sheet's Save action, before `vm.save`, set
`paper.codeReady = !paper.codeURL.isEmpty` (a manually entered link is user-vouched, so it
shows the Code button immediately; clearing the field unsets it).

**Bulk menu (⋯)** — add **"Check for code now"** → `AppEnvironment.shared.codeWatcher.sweep(force: true)`.

When `codeReady` flips, the existing GRDB observation refreshes the library, so the Code
button appears without a manual reload.

## Testing strategy
- **Unit (`swift test`):** `GitHubRepo.isReleased` (real vs docs-only vs empty) and
  `ownerRepo` parsing; `Paper` `code_ready` round-trip via the store.
- **Manual:** point a watched paper's `codeURL` at (a) an empty repo, (b) a README-only
  repo, (c) a real repo; run "Check for code now" and confirm only (c) flips to a Code
  button + posts a clickable notification; verify the first sweep is silent and later
  transitions notify; verify a 403 stops the sweep without marking reconciled.

## Risks / notes
- **App must be running** to check; notifications fire on launch / while open (a local app
  can't check when closed — out of scope, would need a separate scheduled agent).
- **60 req/hr unauthenticated.** Each watched paper costs ~1 API call per sweep; large
  libraries may need several daily sweeps to complete the first reconciliation. Acceptable
  for a personal library; the sweep is sequential and resumes after rate-limit.
- **Heuristic readiness:** a repo that stores code only in releases/branches with a
  docs-only default-branch root would read as "not released"; rare, and the user can add
  the link manually (which marks it ready).
