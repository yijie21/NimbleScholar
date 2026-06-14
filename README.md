# 🎓 Nimble Scholar

A fast, local-first macOS app for **collecting, organizing, reading, and annotating
research papers** — built around arXiv but works with any paper page. One-click capture
from your browser, a tag-first library, and a native PDF reader with highlights and notes.

Everything stays on your Mac. No account, no cloud.

---

## Install & run

Nimble Scholar is a native Swift/SwiftUI app. To build and launch it:

```bash
git clone https://github.com/yijie21/NimbleScholar.git
cd NimbleScholar
bash scripts/mac_bootstrap.sh full run
```

This generates the Xcode project, builds the app, and launches it. (It installs
[XcodeGen](https://github.com/yonsm/XcodeGen) via Homebrew on first run; you need Xcode
installed.) To just open it in Xcode instead, drop the `run`:

```bash
bash scripts/mac_bootstrap.sh full      # generate + open Xcode, then press ⌘R
```

---

## Quick start

1. Launch the app — you'll see your library (empty at first).
2. Click **Capture** in the toolbar, paste an arXiv URL (e.g. `https://arxiv.org/abs/1706.03762`), and hit **Capture**. The paper appears with its title, authors, abstract, and a figure.
3. Click **Read** (or double-click the card) to open it in the built-in PDF reader.
4. Select text → **right-click → Highlight** or **Add Note**.

---

## Capturing papers

There are three ways to add papers.

### 1. Capture URL (in-app)
Toolbar → **Capture** → paste any paper URL → **Capture**. Nimble Scholar fetches the
title, authors, abstract, PDF link, and (for arXiv) a teaser figure.

### 2. ➕ Add manually / drag in a PDF
Toolbar → **＋** → fill in the fields. Or **drag a `.pdf` from Finder** onto the window to add it
(its first page becomes the thumbnail). Re-capturing the same arXiv paper **updates** the existing
entry instead of creating a duplicate.

### 3. 🧩 Chrome / Edge extension (one-click from any paper page)

Save the page you're reading straight into Nimble Scholar.

**Install it once:**
1. Make sure **Nimble Scholar is running** (the app runs a small local capture server).
2. Open **`chrome://extensions`** (or `edge://extensions`).
3. Turn on **Developer mode** (top-right toggle).
4. Click **Load unpacked** and select the **`extension/`** folder inside this repo.
5. (Optional) Pin the **Nimble Scholar Capture** icon to your toolbar.

**Use it:**
1. Open a paper page (an arXiv abstract page, a journal page, etc.).
2. Click the **Nimble Scholar** extension icon.
3. It reads the page's metadata and saves the paper into your library — you'll see
   "Saved: <title>". The paper shows up in the app instantly.
4. You can set **default tags** in the extension popup (e.g. `to-read`), applied to every capture.

> The extension finds the running app automatically — no port setup needed. If it says it
> can't connect, just make sure the app is open.

---

## Organizing your library

- **View modes** (toolbar segmented control): **Three-pane** (list + detail), **Gallery**
  (figure grid), **Rows** (wide cards with inline editing). Your choice is remembered.
- **Sidebar**: **All papers**, **Unread**, **Recently added**, **Untagged**, and one entry per tag
  (with a colored dot + count). Right-click a tag to **Rename** or **Delete** it.
- **Read / Unread**: new papers show a blue dot; opening a paper marks it read. Toggle via
  right-click, or filter to **Unread** in the sidebar.
- **Search**: the toolbar search box matches title, authors, abstract, summary, venue, DOI
  (punctuation-safe).
- **Sort**: Recently updated / Newest year / Title A–Z (remembered across launches).
- **Tags & summary**: edit inline on Rows cards, or in the detail pane. Add a one-sentence
  takeaway to each paper. To reuse an existing tag, click the **tag menu** next to the
  add-tag field, or just start typing and pick a match from the **autocomplete** chips — no
  need to retype tag names.
- **Right-click any paper** → Read · Edit… · Re-fetch Metadata · Mark Read/Unread · Open in
  Browser · Open PDF in Default App · Reveal Cached PDF in Finder · Copy BibTeX · Delete.
- **Multi-select** (Three-pane): ⌘/shift-click several papers for a bulk bar (**Download** /
  **Delete**).
- **Per-paper status**: each card shows its own badge — a **spinner** while its figure/PDF
  download, a green **✓** once the PDF is cached ("ready"), or a tappable orange **↓** to
  retry a paper that hasn't loaded. The bar at the window bottom shows overall progress
  ("Preparing papers — 3/12") or **"Up to date"**.

Newly captured papers complete themselves automatically: the app fetches each missing
figure and PDF in the background, so a paper goes spinner → ready on its own.

**Bulk actions** (toolbar **⋯** menu): Download all PDFs · Load missing figures & PDFs ·
Re-fetch all figures (force a fresh scrape, repairing any paper stuck on its PDF first page) ·
Export BibTeX. (Export BibTeX is also ⇧⌘E.)

**Keyboard**: **Delete** removes the selected paper(s); **⌘O** opens the reader; **⌘F** focuses
search.

---

## Reading & annotating

Click **Read** to open a paper in the PDF reader.

- **Layout**: page **thumbnails** (left), the **PDF** (center), and an **inspector**
  (right) with the document **Outline** and your **Annotations**. Toggle the side panels
  from the toolbar.
- **Search** inside the PDF, **zoom** in/out, **Fit**, and switch single / continuous /
  two-up page modes.
- **Highlight / Note**: select text, then either use the toolbar buttons or
  **right-click → Highlight / Add Note**. Pick the highlight color from the toolbar palette
  (or in Settings).
- **Delete an annotation**: right-click it on the page → **Delete Annotation**, or use the
  Annotations list in the inspector.
- Highlights and notes are saved **into the PDF file**, so they open correctly in Preview
  or any other PDF app.
- **Export to Markdown**: the share button in the reader toolbar saves a `.md` of the paper's
  metadata + all your highlights and notes.
- The reader **remembers your last page** and reopens there.
- **Night reading** (Settings) inverts the page colors for dark reading.

---

## Settings (⌘,)

- **General** — default capture tags; the capture-server port (auto-discovered by the
  extension; change only if it conflicts); an optional **download proxy** (host + port) used
  for PDFs, figures, and metadata when your network needs it (restart to apply).
- **Reading** — night-reading toggle; default highlight color.
- **AI** — enable an OpenAI-compatible chat endpoint in the reader (a local server such as
  Ollama / LM Studio, or the OpenAI cloud).

---

## Backup & restore

**File → Back Up Library…** writes a `.zip` of your whole library (database + cached PDFs).
**File → Restore Library…** replaces the current library from a backup (the app quits; reopen it
afterward). Keep a backup before big changes.

---

## Where your data lives

```
~/Library/Application Support/Nimble Scholar/
    nimblescholar.sqlite3        # your library (papers, tags, annotations index)
    storage/pdfs/                # cached PDFs
~/Library/Caches/Nimble Scholar/
    thumbnails/                  # cached card images
```

---

## Troubleshooting

- **Extension says it can't save** → make sure the app is running; it must be open for the
  capture server to accept the request.
- **A figure is missing** → the app pulls the teaser/pipeline figure from the paper's HTML
  view (arXiv HTML → ar5iv fallback; CVF/publisher landing pages; `og:image` as a last
  resort). A few papers expose no online figure at all and fall back to the PDF's first page.
  Use **⋯ → "Load missing figures & PDFs"** or tap a paper's orange badge to retry.
- **Downloads are slow** → enable the **proxy** in Settings → General → Downloads, or check
  whether a paper's badge stays orange (a real download failure) vs. spinning (in progress).
- **Port conflict** → the app automatically tries the next free port; the extension probes
  for it, so you normally don't need to do anything.

---

## Tech notes

Native Swift/SwiftUI + PDFKit. Local SQLite (GRDB) store. The capture server is a tiny
embedded HTTP listener. See `docs/superpowers/` for the design spec and implementation plan,
and `NimbleScholarCore/` for the tested core package. The app icon is generated by
`scripts/generate_icon.py`.
