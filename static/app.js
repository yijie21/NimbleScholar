import * as pdfjsLib from "/vendor/pdfjs/pdf.min.mjs";

pdfjsLib.GlobalWorkerOptions.workerSrc = "/vendor/pdfjs/pdf.worker.min.mjs";

const state = {
  papers: [],
  tags: [],
  query: "",
  tag: "",
  sort: "updated",
  reader: {
    paper: null,
    pdfDoc: null,
    page: 1,
    pageCount: 0,
    scale: 1.2,
    tool: "read",
    annotations: [],
    renderId: 0,
    draft: null,
    dragStart: null,
    dragPage: 1,
    activeLayer: null,
    selection: null,
    gestureStartScale: 1,
    zoomTimer: null,
    zoomFrame: null,
    previewScale: null,
    zoomAnchorPage: 1,
    annotationMenuId: null,
  },
};

const els = {
  paperList: document.querySelector("#paperList"),
  emptyState: document.querySelector("#emptyState"),
  tagFilters: document.querySelector("#tagFilters"),
  allCount: document.querySelector("#allCount"),
  resultMeta: document.querySelector("#resultMeta"),
  viewTitle: document.querySelector("#viewTitle"),
  searchInput: document.querySelector("#searchInput"),
  sortSelect: document.querySelector("#sortSelect"),
  paperDialog: document.querySelector("#paperDialog"),
  paperForm: document.querySelector("#paperForm"),
  captureDialog: document.querySelector("#captureDialog"),
  captureForm: document.querySelector("#captureForm"),
  imageDialog: document.querySelector("#imageDialog"),
  imagePreview: document.querySelector("#imagePreview"),
  imageDialogTitle: document.querySelector("#imageDialogTitle"),
  readerView: document.querySelector("#readerView"),
  readerBackBtn: document.querySelector("#readerBackBtn"),
  readerTitle: document.querySelector("#readerTitle"),
  readerStatus: document.querySelector("#readerStatus"),
  readerPrevBtn: document.querySelector("#readerPrevBtn"),
  readerNextBtn: document.querySelector("#readerNextBtn"),
  readerPageInput: document.querySelector("#readerPageInput"),
  readerPageCount: document.querySelector("#readerPageCount"),
  readerZoomOutBtn: document.querySelector("#readerZoomOutBtn"),
  readerZoomInBtn: document.querySelector("#readerZoomInBtn"),
  pdfStage: document.querySelector(".pdf-stage"),
  pdfPages: document.querySelector("#pdfPages"),
  annotationList: document.querySelector("#annotationList"),
  annotationCount: document.querySelector("#annotationCount"),
  selectionToolbar: document.querySelector("#selectionToolbar"),
  annotationMenu: document.querySelector("#annotationMenu"),
  annotationMenuText: document.querySelector("#annotationMenuText"),
  annotationMenuCancel: document.querySelector("#annotationMenuCancel"),
  annotationMenuDelete: document.querySelector("#annotationMenuDelete"),
};

const fields = {
  id: document.querySelector("#paperId"),
  title: document.querySelector("#titleField"),
  authors: document.querySelector("#authorsField"),
  year: document.querySelector("#yearField"),
  venue: document.querySelector("#venueField"),
  doi: document.querySelector("#doiField"),
  url: document.querySelector("#urlField"),
  pdf_url: document.querySelector("#pdfUrlField"),
  tags: document.querySelector("#tagsField"),
  summary: document.querySelector("#summaryField"),
  teaser_url: document.querySelector("#teaserUrlField"),
  pipeline_url: document.querySelector("#pipelineUrlField"),
  abstract: document.querySelector("#abstractField"),
  notes: document.querySelector("#notesField"),
};

function escapeHtml(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function tagStyle(name) {
  const palette = [
    { bg: "#eef4ff", fg: "#315f9f", dot: "#5e8ed6" },
    { bg: "#f2f7ee", fg: "#48713d", dot: "#7aaa62" },
    { bg: "#fff3e8", fg: "#99613a", dot: "#d7975d" },
    { bg: "#f6effa", fg: "#765091", dot: "#a575c0" },
    { bg: "#edf8f6", fg: "#327467", dot: "#5eb4a6" },
    { bg: "#fff0f3", fg: "#9b5263", dot: "#d77b8f" },
    { bg: "#f4f1ea", fg: "#725f3e", dot: "#b89a5e" },
    { bg: "#eff2f7", fg: "#4c5f7e", dot: "#7c91b4" },
  ];
  let hash = 0;
  for (const char of String(name || "")) {
    hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  }
  const color = palette[hash % palette.length];
  return `--tag-bg:${color.bg};--tag-fg:${color.fg};--tag-dot:${color.dot}`;
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    ...options,
  });
  if (!response.ok) {
    throw new Error(`Request failed: ${response.status}`);
  }
  const body = await response.text();
  if (!body) return {};
  return JSON.parse(body);
}

function sortedPapers() {
  const papers = [...state.papers];
  if (state.sort === "year") {
    papers.sort((a, b) => Number(b.year || 0) - Number(a.year || 0) || a.title.localeCompare(b.title));
  } else if (state.sort === "title") {
    papers.sort((a, b) => a.title.localeCompare(b.title));
  }
  return papers;
}

function paperMeta(paper) {
  return [paper.authors, paper.year, paper.venue, paper.doi].filter(Boolean).join(" • ");
}

function pdfUrlForPaper(paper) {
  if (paper.pdf_url) return paper.pdf_url;
  const candidates = [paper.url, paper.doi].filter(Boolean);
  for (const value of candidates) {
    const modern = String(value).match(/arxiv\.org\/(?:abs|pdf)\/([0-9]{4}\.[0-9]{4,5})(?:v[0-9]+)?/i);
    if (modern) return `https://arxiv.org/pdf/${modern[1]}`;
    const arxivDoi = String(value).match(/arxiv:([0-9]{4}\.[0-9]{4,5})(?:v[0-9]+)?/i);
    if (arxivDoi) return `https://arxiv.org/pdf/${arxivDoi[1]}`;
  }
  return paper.url || "";
}

async function openPaperInBrowser(url) {
  if (!url) return;
  try {
    const result = await api("/api/open-url", {
      method: "POST",
      body: JSON.stringify({ url }),
    });
    if (result.ok) return;
  } catch (error) {
    console.warn("Falling back to window.open", error);
  }
  window.open(url, "_blank", "noopener,noreferrer");
}

async function openPaperLocally(id, button) {
  const originalText = button?.textContent || "";
  if (button) {
    button.disabled = true;
    button.textContent = "Opening...";
  }
  try {
    const result = await api(`/api/papers/${id}/open-local-pdf`, {
      method: "POST",
      body: JSON.stringify({}),
    });
    if (result.paper) setPaperInState(result.paper);
    if (!result.ok) {
      alert(`Could not open local PDF: ${result.error || "Unknown error"}`);
    }
  } catch (error) {
    console.error(error);
    alert("Could not open local PDF.");
  } finally {
    if (button) {
      button.disabled = false;
      button.textContent = originalText;
    }
  }
}

function setReaderStatus(message) {
  els.readerStatus.textContent = message || "";
}

function currentPaperAnnotations(page = state.reader.page) {
  return state.reader.annotations.filter((annotation) => annotation.page === page);
}

function setReaderTool(tool) {
  state.reader.tool = tool;
  document.querySelectorAll("[data-reader-tool]").forEach((button) => {
    button.classList.toggle("active", button.dataset.readerTool === tool);
  });
  els.pdfPages.dataset.tool = tool;
  if (tool !== "read") {
    window.getSelection()?.removeAllRanges();
    hideSelectionToolbar();
  }
}

function readerPoint(event, layer) {
  const rect = layer.getBoundingClientRect();
  return {
    x: Math.min(Math.max((event.clientX - rect.left) / rect.width, 0), 1),
    y: Math.min(Math.max((event.clientY - rect.top) / rect.height, 0), 1),
  };
}

function clampScale(value) {
  return Math.min(Math.max(value, 0.65), 3);
}

function hideSelectionToolbar() {
  els.selectionToolbar.classList.add("hidden");
  els.selectionToolbar.setAttribute("aria-hidden", "true");
}

function annotationById(id) {
  return state.reader.annotations.find((entry) => String(entry.id) === String(id));
}

function hideAnnotationMenu() {
  state.reader.annotationMenuId = null;
  els.annotationMenu.classList.add("hidden");
  els.annotationMenu.setAttribute("aria-hidden", "true");
}

function showAnnotationMenu(annotation, clientX, clientY) {
  if (!annotation) return;
  state.reader.annotationMenuId = annotation.id;
  const label = annotation.kind === "note" ? "note" : "highlight";
  const text = annotation.text ? `Delete this ${label}: "${annotation.text}"?` : `Delete this ${label}?`;
  els.annotationMenuText.textContent = text.length > 180 ? `${text.slice(0, 177)}...` : text;
  els.annotationMenu.classList.remove("hidden");
  els.annotationMenu.setAttribute("aria-hidden", "false");
  const rect = els.annotationMenu.getBoundingClientRect();
  const left = Math.min(Math.max(clientX, 12), window.innerWidth - rect.width - 12);
  const top = Math.min(Math.max(clientY, 12), window.innerHeight - rect.height - 12);
  els.annotationMenu.style.left = `${left}px`;
  els.annotationMenu.style.top = `${top}px`;
}

function selectionRectsByPage(range) {
  const rects = [];
  for (const rect of range.getClientRects()) {
    if (rect.width < 2 || rect.height < 2) continue;
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;
    const shell = document.elementFromPoint(centerX, centerY)?.closest(".pdf-page-shell");
    if (!shell) continue;
    const layer = shell.querySelector(".annotation-layer");
    if (!layer) continue;
    const layerRect = layer.getBoundingClientRect();
    const left = Math.max(rect.left, layerRect.left);
    const top = Math.max(rect.top, layerRect.top);
    const right = Math.min(rect.right, layerRect.right);
    const bottom = Math.min(rect.bottom, layerRect.bottom);
    if (right <= left || bottom <= top) continue;
    rects.push({
      page: Number(shell.dataset.page),
      x: (left - layerRect.left) / layerRect.width,
      y: (top - layerRect.top) / layerRect.height,
      width: (right - left) / layerRect.width,
      height: (bottom - top) / layerRect.height,
      screen: { left, top, right, bottom },
    });
  }
  return rects;
}

function updateSelectionToolbar() {
  if (!document.body.classList.contains("reader-open") || state.reader.tool !== "read") {
    hideSelectionToolbar();
    return;
  }
  const selection = window.getSelection();
  if (!selection || selection.isCollapsed || !selection.rangeCount) {
    hideSelectionToolbar();
    return;
  }
  const text = selection.toString().trim();
  if (!text) {
    hideSelectionToolbar();
    return;
  }
  const range = selection.getRangeAt(0);
  const rects = selectionRectsByPage(range);
  if (!rects.length) {
    hideSelectionToolbar();
    return;
  }
  state.reader.selection = { text, rects };
  const top = Math.min(...rects.map((rect) => rect.screen.top));
  const left = (Math.min(...rects.map((rect) => rect.screen.left)) + Math.max(...rects.map((rect) => rect.screen.right))) / 2;
  els.selectionToolbar.style.left = `${left}px`;
  els.selectionToolbar.style.top = `${Math.max(top - 46, 8)}px`;
  els.selectionToolbar.classList.remove("hidden");
  els.selectionToolbar.setAttribute("aria-hidden", "false");
}

async function highlightSelection() {
  const selection = state.reader.selection;
  if (!selection?.rects?.length) return;
  for (const rect of selection.rects) {
    await saveAnnotation({
      page: rect.page,
      kind: "highlight",
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
      color: "#ffd966",
      text: selection.text,
    });
  }
  window.getSelection()?.removeAllRanges();
  hideSelectionToolbar();
}

async function noteSelection() {
  const selection = state.reader.selection;
  if (!selection?.rects?.length) return;
  const note = prompt("Note for selected text", selection.text);
  if (!note) return;
  const rect = selection.rects[0];
  await saveAnnotation({
    page: rect.page,
    kind: "note",
    x: rect.x,
    y: rect.y,
    width: Math.max(rect.width, 0.026),
    height: Math.max(rect.height, 0.026),
    color: "#7cc4ff",
    text: note,
  });
  window.getSelection()?.removeAllRanges();
  hideSelectionToolbar();
}

async function copySelectionText() {
  const selection = state.reader.selection;
  if (!selection?.text) return;
  await navigator.clipboard.writeText(selection.text);
  hideSelectionToolbar();
}

function annotationBox(start, end) {
  const x = Math.min(start.x, end.x);
  const y = Math.min(start.y, end.y);
  return {
    x,
    y,
    width: Math.abs(start.x - end.x),
    height: Math.abs(start.y - end.y),
  };
}

function setDraftBox(box) {
  if (!state.reader.draft) return;
  Object.assign(state.reader.draft.style, {
    left: `${box.x * 100}%`,
    top: `${box.y * 100}%`,
    width: `${box.width * 100}%`,
    height: `${box.height * 100}%`,
  });
}

function renderAnnotations() {
  els.pdfPages.querySelectorAll(".annotation, .annotation-draft").forEach((node) => node.remove());
  state.reader.annotations.forEach((annotation) => {
    const layer = els.pdfPages.querySelector(`.annotation-layer[data-page="${annotation.page}"]`);
    if (!layer) return;
    const marker = document.createElement("button");
    marker.type = "button";
    marker.className = `annotation ${annotation.kind}`;
    marker.dataset.annotationId = String(annotation.id);
    marker.title = "Right-click to delete";
    marker.style.left = `${annotation.x * 100}%`;
    marker.style.top = `${annotation.y * 100}%`;
    marker.style.width = `${Math.max(annotation.width, annotation.kind === "note" ? 0.024 : 0.006) * 100}%`;
    marker.style.height = `${Math.max(annotation.height, annotation.kind === "note" ? 0.024 : 0.006) * 100}%`;
    marker.style.setProperty("--annotation-color", annotation.color || "#ffd966");
    marker.addEventListener("click", (event) => {
      event.stopPropagation();
      if (annotation.text) alert(annotation.text);
    });
    marker.addEventListener("contextmenu", (event) => {
      event.preventDefault();
      event.stopPropagation();
      showAnnotationMenu(annotation, event.clientX, event.clientY);
    });
    layer.appendChild(marker);
  });
  renderAnnotationList();
}

function renderAnnotationList() {
  const annotations = state.reader.annotations;
  els.annotationCount.textContent = `${annotations.length} saved`;
  if (!annotations.length) {
    els.annotationList.innerHTML = `<div class="annotation-empty">No annotations yet.</div>`;
    return;
  }
  els.annotationList.innerHTML = annotations.map((annotation) => `
    <div class="annotation-item" data-id="${annotation.id}">
      <button class="annotation-jump" type="button">
        <span class="annotation-kind ${annotation.kind}"></span>
        <span>
          <strong>Page ${annotation.page}</strong>
          <small>${escapeHtml(annotation.text || (annotation.kind === "note" ? "Note" : "Highlight"))}</small>
        </span>
      </button>
      <button class="annotation-delete" type="button" title="Delete annotation">Delete</button>
    </div>
  `).join("");
  els.annotationList.querySelectorAll(".annotation-item").forEach((item) => {
    const annotation = annotationById(item.dataset.id);
    item.querySelector(".annotation-jump").addEventListener("click", async () => {
      if (!annotation) return;
      scrollToReaderPage(annotation.page);
    });
    item.querySelector(".annotation-delete").addEventListener("click", async () => {
      await deleteAnnotation(annotation, false);
    });
  });
}

async function saveAnnotation(data) {
  if (!state.reader.paper) return;
  const result = await api(`/api/papers/${state.reader.paper.id}/annotations`, {
    method: "POST",
    body: JSON.stringify(data),
  });
  state.reader.annotations.push(result.annotation);
  renderAnnotations();
}

async function deleteAnnotation(annotation, confirmFirst = true) {
  if (!annotation) return;
  const label = annotation.kind === "note" ? "note" : "highlight";
  const detail = annotation.text ? `\n\n${annotation.text}` : "";
  if (confirmFirst && !confirm(`Delete this ${label}?${detail}`)) return;
  const result = await api(`/api/annotations/${annotation.id}`, { method: "DELETE" });
  if (result.ok === false) {
    alert("This annotation was already deleted.");
  }
  state.reader.annotations = state.reader.annotations.filter((entry) => String(entry.id) !== String(annotation.id));
  hideAnnotationMenu();
  renderAnnotations();
}

function annotationAtPoint(clientX, clientY) {
  for (const marker of els.pdfPages.querySelectorAll(".annotation")) {
    const rect = marker.getBoundingClientRect();
    if (
      clientX >= rect.left
      && clientX <= rect.right
      && clientY >= rect.top
      && clientY <= rect.bottom
    ) {
      return annotationById(marker.dataset.annotationId);
    }
  }
  return null;
}

function updateReaderProgress() {
  els.readerPageInput.value = state.reader.page;
  els.readerPageInput.max = state.reader.pageCount;
  els.readerPageCount.textContent = `/ ${state.reader.pageCount}`;
  els.readerPrevBtn.disabled = state.reader.page <= 1;
  els.readerNextBtn.disabled = state.reader.page >= state.reader.pageCount;
  setReaderStatus(`${Math.round(state.reader.scale * 100)}% zoom`);
}

function updateCurrentPageFromScroll() {
  if (!state.reader.pdfDoc) return;
  const stageRect = els.pdfStage.getBoundingClientRect();
  const readingLine = stageRect.top + Math.min(stageRect.height * 0.35, 220);
  const shells = [...els.pdfPages.querySelectorAll(".pdf-page-shell")];
  let current = state.reader.page;
  for (const shell of shells) {
    const rect = shell.getBoundingClientRect();
    if (rect.top <= readingLine && rect.bottom > stageRect.top + 30) {
      current = Number(shell.dataset.page);
    }
  }
  if (current !== state.reader.page) {
    state.reader.page = current;
    updateReaderProgress();
  }
}

function readerAnchor(fallbackPage = state.reader.page) {
  const stageRect = els.pdfStage.getBoundingClientRect();
  const focusY = stageRect.top + Math.min(stageRect.height * 0.35, 220);
  const shells = [...els.pdfPages.querySelectorAll(".pdf-page-shell")];
  for (const shell of shells) {
    const rect = shell.getBoundingClientRect();
    if (rect.top <= focusY && rect.bottom >= focusY) {
      return {
        page: Number(shell.dataset.page),
        y: Math.min(Math.max((focusY - rect.top) / rect.height, 0), 1),
      };
    }
  }
  return { page: fallbackPage, y: 0 };
}

function restoreReaderAnchor(anchor) {
  const shell = els.pdfPages.querySelector(`.pdf-page-shell[data-page="${anchor.page}"]`);
  if (!shell) {
    scrollToReaderPage(anchor.page);
    return;
  }
  const viewportOffset = Math.min(els.pdfStage.clientHeight * 0.35, 220);
  els.pdfStage.scrollTop = shell.offsetTop + shell.offsetHeight * anchor.y - viewportOffset;
  centerReaderHorizontally();
  state.reader.page = anchor.page;
  updateReaderProgress();
}

function scrollToReaderPage(page) {
  const nextPage = Math.min(Math.max(Number(page) || 1, 1), state.reader.pageCount || 1);
  const shell = els.pdfPages.querySelector(`.pdf-page-shell[data-page="${nextPage}"]`);
  if (!shell) return;
  state.reader.page = nextPage;
  shell.scrollIntoView({ block: "start", inline: "nearest" });
  centerReaderHorizontally();
  updateReaderProgress();
}

function centerReaderHorizontally() {
  const maxLeft = Math.max(0, els.pdfStage.scrollWidth - els.pdfStage.clientWidth);
  els.pdfStage.scrollLeft = maxLeft / 2;
}

function setCenteredZoomOrigin() {
  els.pdfPages.style.transformOrigin = "50% 0";
}

function normalizeViewportRect(rect) {
  const left = Math.min(rect[0], rect[2]);
  const top = Math.min(rect[1], rect[3]);
  const right = Math.max(rect[0], rect[2]);
  const bottom = Math.max(rect[1], rect[3]);
  return { left, top, width: right - left, height: bottom - top };
}

function isExternalPdfUrl(url) {
  return /^https?:\/\//i.test(String(url || ""));
}

function pdfAnnotationUrl(annotation) {
  const url = annotation?.url || annotation?.unsafeUrl || "";
  return isExternalPdfUrl(url) ? url : "";
}

function renderPdfLinks(linkLayer, annotations, viewport) {
  linkLayer.replaceChildren();
  annotations
    .filter((annotation) => annotation.subtype === "Link" && pdfAnnotationUrl(annotation) && annotation.rect)
    .forEach((annotation) => {
      const url = pdfAnnotationUrl(annotation);
      const box = normalizeViewportRect(viewport.convertToViewportRectangle(annotation.rect));
      if (box.width < 2 || box.height < 2) return;
      const link = document.createElement("a");
      link.className = "pdf-link";
      link.href = url;
      link.dataset.url = url;
      link.title = `Command-click to open ${url}`;
      link.setAttribute("aria-label", `Command-click to open ${url}`);
      Object.assign(link.style, {
        left: `${box.left}px`,
        top: `${box.top}px`,
        width: `${box.width}px`,
        height: `${box.height}px`,
      });
      linkLayer.appendChild(link);
    });
}

function pdfLinkAtPoint(clientX, clientY) {
  for (const link of els.pdfPages.querySelectorAll(".pdf-link[data-url]")) {
    const rect = link.getBoundingClientRect();
    if (
      clientX >= rect.left
      && clientX <= rect.right
      && clientY >= rect.top
      && clientY <= rect.bottom
    ) {
      return link.dataset.url;
    }
  }
  return "";
}

function applyLiveZoom(nextScale) {
  if (!state.reader.pdfDoc) return;
  hideSelectionToolbar();
  window.getSelection()?.removeAllRanges();
  if (!state.reader.previewScale) {
    state.reader.zoomAnchorPage = state.reader.page;
  }
  state.reader.previewScale = clampScale(nextScale);
  const ratio = state.reader.previewScale / state.reader.scale;
  setCenteredZoomOrigin();
  cancelAnimationFrame(state.reader.zoomFrame);
  state.reader.zoomFrame = requestAnimationFrame(() => {
    els.pdfPages.classList.add("zooming");
    els.pdfPages.style.transform = `scale(${ratio})`;
    setReaderStatus(`${Math.round(state.reader.previewScale * 100)}% zoom`);
  });
}

function commitLiveZoom(delay = 140) {
  if (!state.reader.pdfDoc || !state.reader.previewScale) return;
  clearTimeout(state.reader.zoomTimer);
  state.reader.zoomTimer = setTimeout(() => {
    const anchor = readerAnchor(state.reader.zoomAnchorPage || state.reader.page);
    state.reader.scale = state.reader.previewScale;
    state.reader.previewScale = null;
    state.reader.zoomAnchorPage = state.reader.page;
    renderPdfPages(anchor).catch(console.error);
  }, delay);
}

function makePdfPageShell(pageNumber) {
  const shell = document.createElement("section");
  shell.className = "pdf-page-shell";
  shell.dataset.page = String(pageNumber);

  const label = document.createElement("div");
  label.className = "pdf-page-label";
  label.textContent = `Page ${pageNumber}`;

  const canvas = document.createElement("canvas");
  const textLayer = document.createElement("div");
  textLayer.className = "text-layer";
  textLayer.dataset.page = String(pageNumber);
  const linkLayer = document.createElement("div");
  linkLayer.className = "pdf-link-layer";
  linkLayer.dataset.page = String(pageNumber);
  const layer = document.createElement("div");
  layer.className = "annotation-layer";
  layer.dataset.page = String(pageNumber);

  shell.append(label, canvas, textLayer, linkLayer, layer);
  return { shell, canvas, textLayer, linkLayer, layer };
}

async function renderPdfPages(anchorOrPage = state.reader.page) {
  const reader = state.reader;
  if (!reader.pdfDoc) return;
  const renderId = ++reader.renderId;
  const anchor = typeof anchorOrPage === "object"
    ? anchorOrPage
    : { page: anchorOrPage, y: 0 };
  window.getSelection()?.removeAllRanges();
  hideSelectionToolbar();
  const nextPages = document.createElement("div");
  nextPages.dataset.tool = state.reader.tool;
  setReaderStatus("Rendering pages...");
  const outputScale = window.devicePixelRatio || 1;
  for (let pageNumber = 1; pageNumber <= reader.pageCount; pageNumber += 1) {
    if (renderId !== reader.renderId) return;
    const page = await reader.pdfDoc.getPage(pageNumber);
    const viewport = page.getViewport({ scale: reader.scale });
    const { shell, canvas, textLayer, linkLayer } = makePdfPageShell(pageNumber);
    const context = canvas.getContext("2d");
    canvas.width = Math.floor(viewport.width * outputScale);
    canvas.height = Math.floor(viewport.height * outputScale);
    canvas.style.width = `${Math.floor(viewport.width)}px`;
    canvas.style.height = `${Math.floor(viewport.height)}px`;
    shell.style.width = canvas.style.width;
    shell.style.minHeight = canvas.style.height;
    context.setTransform(outputScale, 0, 0, outputScale, 0, 0);
    nextPages.appendChild(shell);
    setReaderStatus(`Rendering page ${pageNumber} / ${reader.pageCount}...`);
    const [textContent, linkAnnotations] = await Promise.all([
      page.getTextContent(),
      page.getAnnotations({ intent: "display" }),
    ]);
    renderPdfLinks(linkLayer, linkAnnotations, viewport);
    await Promise.all([
      page.render({ canvasContext: context, viewport }).promise,
      new pdfjsLib.TextLayer({ textContentSource: textContent, container: textLayer, viewport }).render(),
    ]);
  }
  if (renderId !== reader.renderId) return;
  cancelAnimationFrame(reader.zoomFrame);
  els.pdfPages.classList.remove("zooming");
  els.pdfPages.style.transform = "";
  els.pdfPages.style.transformOrigin = "50% 0";
  els.pdfPages.replaceChildren(...nextPages.childNodes);
  state.reader.page = Math.min(Math.max(anchor.page, 1), reader.pageCount || 1);
  renderAnnotations();
  updateReaderProgress();
  requestAnimationFrame(() => restoreReaderAnchor(anchor));
}

async function openPaperReader(id, button) {
  const paper = state.papers.find((item) => item.id === id);
  if (!paper) return;
  const originalText = button?.textContent || "";
  if (button) {
    button.disabled = true;
    button.textContent = "Opening...";
  }
  document.body.classList.add("reader-open");
  els.readerView.classList.remove("hidden");
  els.readerView.setAttribute("aria-hidden", "false");
  els.readerTitle.textContent = paper.title || "PDF Reader";
  setReaderStatus("Preparing local PDF...");
  try {
    const cached = await api(`/api/papers/${id}/download-pdf`, {
      method: "POST",
      body: JSON.stringify({}),
    });
    if (!cached.ok) {
      alert(`Could not prepare PDF: ${cached.error || "Unknown error"}`);
      closeReader();
      return;
    }
    if (cached.paper) setPaperInState(cached.paper);
    state.reader.paper = cached.paper || paper;
    state.reader.page = 1;
    state.reader.scale = 1.2;
    state.reader.annotations = [];
    setReaderTool("read");
    setReaderStatus("Loading PDF...");
    const annotations = await api(`/api/papers/${id}/annotations`);
    state.reader.annotations = annotations.annotations || [];
    state.reader.pdfDoc = await pdfjsLib.getDocument(`/api/papers/${id}/pdf`).promise;
    state.reader.pageCount = state.reader.pdfDoc.numPages;
    await renderPdfPages(1);
  } catch (error) {
    console.error(error);
    alert("Could not open the built-in PDF reader.");
    closeReader();
  } finally {
    if (button) {
      button.disabled = false;
      button.textContent = originalText;
    }
  }
}

function closeReader() {
  state.reader.pdfDoc = null;
  state.reader.paper = null;
  state.reader.annotations = [];
  state.reader.draft?.remove();
  state.reader.draft = null;
  state.reader.dragStart = null;
  state.reader.activeLayer = null;
  clearTimeout(state.reader.zoomTimer);
  cancelAnimationFrame(state.reader.zoomFrame);
  state.reader.previewScale = null;
  state.reader.zoomAnchorPage = 1;
  state.reader.selection = null;
  state.reader.annotationMenuId = null;
  hideSelectionToolbar();
  hideAnnotationMenu();
  document.body.classList.remove("reader-open");
  els.readerView.classList.add("hidden");
  els.readerView.setAttribute("aria-hidden", "true");
  els.pdfPages.innerHTML = "";
  els.annotationList.innerHTML = "";
  load().catch(console.error);
}

function imageUrlForPaper(paper) {
  return paper.teaser_url || paper.pipeline_url || "";
}

function setPaperInState(updated) {
  state.papers = state.papers.map((paper) => paper.id === updated.id ? updated : paper);
}

function openImagePreview(paper) {
  const imageUrl = imageUrlForPaper(paper);
  if (!imageUrl) return;
  els.imagePreview.src = imageUrl;
  els.imagePreview.alt = paper.title || "Paper image";
  els.imageDialogTitle.textContent = paper.title || "Paper Image";
  els.imageDialog.showModal();
}

async function deletePaperFromCard(id) {
  const paper = state.papers.find((item) => item.id === id);
  const label = paper ? `"${paper.title}"` : "this paper";
  if (!confirm(`Delete ${label}?`)) return;
  await api(`/api/papers/${id}`, { method: "DELETE" });
  await load();
}

async function addQuickTag(id, value, statusEl) {
  const tag = value.trim().toLowerCase();
  if (!tag) return false;
  const paper = state.papers.find((item) => item.id === id);
  if (!paper) return false;
  const tags = paper.tags || [];
  if (tags.includes(tag)) {
    statusEl.textContent = "Already added";
    setTimeout(() => {
      statusEl.textContent = "";
    }, 1200);
    return true;
  }
  statusEl.textContent = "Saving...";
  try {
    await api(`/api/papers/${id}`, {
      method: "PUT",
      body: JSON.stringify({ tags: [...tags, tag] }),
    });
    await load();
    return true;
  } catch (error) {
    console.error(error);
    statusEl.textContent = "Could not save";
    return false;
  }
}

async function removeQuickTag(id, tag) {
  const paper = state.papers.find((item) => item.id === id);
  if (!paper) return;
  const tags = (paper.tags || []).filter((item) => item !== tag);
  await api(`/api/papers/${id}`, {
    method: "PUT",
    body: JSON.stringify({ tags }),
  });
  if (state.tag === tag && !tags.includes(tag)) {
    state.tag = "";
  }
  await load();
}

async function saveQuickSummary(id, value, statusEl) {
  const paper = state.papers.find((item) => item.id === id);
  if (!paper || value === (paper.summary || "")) return;
  statusEl.textContent = "Saving...";
  try {
    const data = await api(`/api/papers/${id}`, {
      method: "PUT",
      body: JSON.stringify({ summary: value }),
    });
    setPaperInState(data.paper);
    statusEl.textContent = "Saved";
    setTimeout(() => {
      statusEl.textContent = "";
    }, 1200);
  } catch (error) {
    console.error(error);
    statusEl.textContent = "Could not save";
  }
}

function renderPapers() {
  const papers = sortedPapers();
  els.paperList.innerHTML = papers.map((paper) => `
    <article class="paper-card" data-id="${paper.id}">
      <div class="${imageUrlForPaper(paper) ? "paper-card-grid" : ""}">
        ${imageUrlForPaper(paper) ? `
          <button class="paper-visual" data-action="preview-image" data-no-card-open type="button" title="Open image preview">
            <img src="${escapeHtml(imageUrlForPaper(paper))}" alt="">
          </button>
        ` : ""}
        <div class="paper-main">
          <div class="paper-top">
            <div>
              <h3>${escapeHtml(paper.title)}</h3>
              <p class="paper-meta">${escapeHtml(paperMeta(paper) || "No metadata yet")}</p>
            </div>
            <div class="paper-actions" data-no-card-open>
              <button class="paper-open primary-lite" data-action="open-reader" type="button" title="Read and annotate inside Nimble Scholar">Read</button>
              <button class="paper-open" data-action="open-browser" type="button" title="Open PDF in browser">Browser</button>
              <button class="paper-open ${paper.pdf_path ? "cached" : ""}" data-action="open-local" type="button" title="Open local PDF with the default PDF reader">Local</button>
              <button class="paper-delete" data-action="delete-paper" type="button" title="Delete paper">Delete</button>
            </div>
          </div>
          <div class="quick-summary" data-no-card-open>
            <label for="summary-${paper.id}">Summary</label>
            <input id="summary-${paper.id}" class="summary-input" maxlength="240" value="${escapeHtml(paper.summary || "")}" placeholder="Add one sentence after reading">
            <span class="summary-status" aria-live="polite"></span>
          </div>
          <div class="tag-row">
            ${(paper.tags || []).map((tag) => `
              <span class="tag" style="${tagStyle(tag)}">
                <span>${escapeHtml(tag)}</span>
                <button class="tag-remove" data-action="remove-tag" data-tag="${escapeHtml(tag)}" data-no-card-open type="button" aria-label="Remove ${escapeHtml(tag)} tag">x</button>
              </span>
            `).join("")}
            <form class="quick-tag" data-no-card-open>
              <input id="tag-${paper.id}" class="tag-input" placeholder="+ tag" autocomplete="off" aria-label="Add tag">
              <button type="submit">Add</button>
              <span class="tag-status" aria-live="polite"></span>
            </form>
          </div>
        </div>
      </div>
    </article>
  `).join("");
  els.emptyState.style.display = papers.length ? "none" : "block";
  els.resultMeta.textContent = `${papers.length} ${papers.length === 1 ? "paper" : "papers"}`;
  els.viewTitle.textContent = state.tag ? state.tag : "All papers";
  els.paperList.querySelectorAll(".paper-card").forEach((card) => {
    let clickTimer = null;
    card.querySelector('[data-action="preview-image"]')?.addEventListener("click", () => {
      const paper = state.papers.find((item) => item.id === Number(card.dataset.id));
      if (paper) openImagePreview(paper);
    });
    card.querySelector('[data-action="delete-paper"]')?.addEventListener("click", async () => {
      await deletePaperFromCard(Number(card.dataset.id));
    });
    card.querySelector('[data-action="open-browser"]')?.addEventListener("click", () => {
      const paper = state.papers.find((item) => item.id === Number(card.dataset.id));
      const pdfUrl = paper ? pdfUrlForPaper(paper) : "";
      openPaperInBrowser(pdfUrl);
    });
    card.querySelector('[data-action="open-reader"]')?.addEventListener("click", async (event) => {
      await openPaperReader(Number(card.dataset.id), event.currentTarget);
    });
    card.querySelector('[data-action="open-local"]')?.addEventListener("click", async (event) => {
      await openPaperLocally(Number(card.dataset.id), event.currentTarget);
    });
    card.querySelectorAll('[data-action="remove-tag"]').forEach((button) => {
      button.addEventListener("click", async () => {
        await removeQuickTag(Number(card.dataset.id), button.dataset.tag);
      });
    });
    card.addEventListener("dblclick", (event) => {
      if (event.target.closest("[data-no-card-open]")) return;
      clearTimeout(clickTimer);
      const paper = state.papers.find((item) => item.id === Number(card.dataset.id));
      const pdfUrl = paper ? pdfUrlForPaper(paper) : "";
      openPaperInBrowser(pdfUrl);
    });
    card.addEventListener("click", (event) => {
      if (event.target.closest("[data-no-card-open]")) return;
      clearTimeout(clickTimer);
      clickTimer = setTimeout(() => openPaper(Number(card.dataset.id)), 220);
    });
  });
  els.paperList.querySelectorAll(".summary-input").forEach((input) => {
    let timer = null;
    const card = input.closest(".paper-card");
    const status = card.querySelector(".summary-status");
    const save = () => saveQuickSummary(Number(card.dataset.id), input.value.trim(), status);
    input.addEventListener("input", () => {
      clearTimeout(timer);
      timer = setTimeout(save, 700);
    });
    input.addEventListener("blur", save);
    input.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        input.blur();
      }
    });
  });
  els.paperList.querySelectorAll(".quick-tag").forEach((form) => {
    const card = form.closest(".paper-card");
    const input = form.querySelector(".tag-input");
    const status = form.querySelector(".tag-status");
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const saved = await addQuickTag(Number(card.dataset.id), input.value, status);
      if (saved) input.value = "";
    });
  });
}

function renderTags() {
  els.allCount.textContent = state.papers.length;
  document.querySelector('[data-tag=""]').classList.toggle("active", !state.tag);
  els.tagFilters.innerHTML = state.tags.map((tag) => `
    <button class="tag-filter ${state.tag === tag.name ? "active" : ""}" data-tag="${escapeHtml(tag.name)}" style="${tagStyle(tag.name)}">
      <span class="tag-filter-name"><span class="tag-dot"></span>${escapeHtml(tag.name)}</span><span class="tag-count">${tag.count}</span>
    </button>
  `).join("");
  document.querySelectorAll(".tag-filter").forEach((button) => {
    button.addEventListener("click", () => {
      state.tag = button.dataset.tag || "";
      load();
    });
  });
}

async function load() {
  const params = new URLSearchParams();
  if (state.query) params.set("q", state.query);
  if (state.tag) params.set("tag", state.tag);
  const [papersData, tagsData] = await Promise.all([
    api(`/api/papers?${params}`),
    api("/api/tags"),
  ]);
  state.papers = papersData.papers;
  state.tags = tagsData.tags;
  renderTags();
  renderPapers();
}

function paperFromForm() {
  return {
    title: fields.title.value.trim(),
    authors: fields.authors.value.trim(),
    year: fields.year.value.trim(),
    venue: fields.venue.value.trim(),
    doi: fields.doi.value.trim(),
    url: fields.url.value.trim(),
    pdf_url: fields.pdf_url.value.trim(),
    tags: fields.tags.value.split(",").map((tag) => tag.trim()).filter(Boolean),
    summary: fields.summary.value.trim(),
    teaser_url: fields.teaser_url.value.trim(),
    pipeline_url: fields.pipeline_url.value.trim(),
    abstract: fields.abstract.value.trim(),
    notes: fields.notes.value.trim(),
  };
}

function fillForm(paper = {}) {
  fields.id.value = paper.id || "";
  fields.title.value = paper.title || "";
  fields.authors.value = paper.authors || "";
  fields.year.value = paper.year || "";
  fields.venue.value = paper.venue || "";
  fields.doi.value = paper.doi || "";
  fields.url.value = paper.url || "";
  fields.pdf_url.value = paper.pdf_url || "";
  fields.tags.value = (paper.tags || []).join(", ");
  fields.summary.value = paper.summary || "";
  fields.teaser_url.value = paper.teaser_url || "";
  fields.pipeline_url.value = paper.pipeline_url || "";
  fields.abstract.value = paper.abstract || "";
  fields.notes.value = paper.notes || "";
  document.querySelector("#deleteBtn").style.visibility = paper.id ? "visible" : "hidden";
  document.querySelector("#dialogTitle").textContent = paper.id ? "Edit Paper" : "Add Paper";
}

function openPaper(id) {
  const paper = state.papers.find((item) => item.id === id);
  fillForm(paper);
  els.paperDialog.showModal();
}

function bookmarkletCode() {
  const endpoint = `${location.origin}/api/capture`;
  return `javascript:(()=>{const meta=(n)=>document.querySelector('meta[name="'+n+'"],meta[property="'+n+'"]')?.content||'';fetch('${endpoint}',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({url:location.href,title:meta('citation_title')||meta('og:title')||document.title,authors:[...document.querySelectorAll('meta[name="citation_author"]')].map(m=>m.content).join(', '),doi:meta('citation_doi'),pdf_url:meta('citation_pdf_url'),teaser_url:meta('og:image')||meta('twitter:image'),abstract:meta('description')||meta('og:description'),source:location.hostname,tags:prompt('Tags for Nimble Scholar, comma-separated','to-read')||''})}).then(()=>alert('Saved to Nimble Scholar')).catch(e=>alert('Nimble Scholar capture failed: '+e.message));})();`;
}

document.querySelector("#newPaperBtn").addEventListener("click", () => {
  fillForm();
  els.paperDialog.showModal();
});

document.querySelector("#captureBtn").addEventListener("click", () => {
  document.querySelector("#captureUrlField").value = "";
  document.querySelector("#captureTagsField").value = "";
  els.captureDialog.showModal();
});

document.querySelector("#bookmarkletBtn").addEventListener("click", async () => {
  await navigator.clipboard.writeText(bookmarkletCode());
  document.querySelector("#bookmarkletBtn").textContent = "Copied";
  setTimeout(() => {
    document.querySelector("#bookmarkletBtn").textContent = "Bookmarklet";
  }, 1400);
});

document.querySelector("#updateFiguresBtn").addEventListener("click", async () => {
  const button = document.querySelector("#updateFiguresBtn");
  button.disabled = true;
  button.textContent = "Updating...";
  try {
    const result = await api("/api/enrich/arxiv-figures", {
      method: "POST",
      body: JSON.stringify({ overwrite: false }),
    });
    button.textContent = `Updated ${result.updated}`;
    await load();
  } catch (error) {
    console.error(error);
    button.textContent = "Update failed";
  } finally {
    setTimeout(() => {
      button.disabled = false;
      button.textContent = "Update Figures";
    }, 1800);
  }
});

document.querySelector("#downloadPdfsBtn").addEventListener("click", async () => {
  const button = document.querySelector("#downloadPdfsBtn");
  button.disabled = true;
  button.textContent = "Downloading...";
  try {
    const result = await api("/api/pdfs/download-all", {
      method: "POST",
      body: JSON.stringify({ overwrite: false }),
    });
    button.textContent = `PDFs ${result.downloaded}/${result.checked}`;
    await load();
    if (result.failed) {
      alert(`${result.failed} PDF${result.failed === 1 ? "" : "s"} could not be downloaded. Papers without a PDF URL or with network errors were skipped.`);
    }
  } catch (error) {
    console.error(error);
    button.textContent = "Download failed";
  } finally {
    setTimeout(() => {
      button.disabled = false;
      button.textContent = "Download PDFs";
    }, 2200);
  }
});

document.querySelector("#closeDialogBtn").addEventListener("click", () => els.paperDialog.close());
document.querySelector("#cancelBtn").addEventListener("click", () => els.paperDialog.close());
document.querySelector("#closeCaptureBtn").addEventListener("click", () => els.captureDialog.close());
document.querySelector("#cancelCaptureBtn").addEventListener("click", () => els.captureDialog.close());
document.querySelector("#closeImageBtn").addEventListener("click", () => els.imageDialog.close());
els.imageDialog.addEventListener("click", (event) => {
  if (event.target === els.imageDialog) {
    els.imageDialog.close();
  }
});
els.imageDialog.addEventListener("close", () => {
  els.imagePreview.removeAttribute("src");
});

els.readerBackBtn.addEventListener("click", closeReader);
els.pdfStage.addEventListener("scroll", () => {
  clearTimeout(window.readerScrollTimer);
  window.readerScrollTimer = setTimeout(updateCurrentPageFromScroll, 60);
});
els.readerPrevBtn.addEventListener("click", () => {
  if (state.reader.page <= 1) return;
  scrollToReaderPage(state.reader.page - 1);
});
els.readerNextBtn.addEventListener("click", () => {
  if (state.reader.page >= state.reader.pageCount) return;
  scrollToReaderPage(state.reader.page + 1);
});
els.readerPageInput.addEventListener("change", () => {
  const page = Math.min(Math.max(Number(els.readerPageInput.value) || 1, 1), state.reader.pageCount || 1);
  scrollToReaderPage(page);
});
els.readerZoomOutBtn.addEventListener("click", async () => {
  const keepPage = state.reader.page;
  state.reader.scale = Math.max(0.7, Number((state.reader.scale - 0.15).toFixed(2)));
  await renderPdfPages(keepPage);
});
els.readerZoomInBtn.addEventListener("click", async () => {
  const keepPage = state.reader.page;
  state.reader.scale = Math.min(2.4, Number((state.reader.scale + 0.15).toFixed(2)));
  await renderPdfPages(keepPage);
});
els.pdfStage.addEventListener("wheel", (event) => {
  if (!state.reader.pdfDoc || !event.ctrlKey) return;
  event.preventDefault();
  const baseScale = state.reader.previewScale || state.reader.scale;
  const nextScale = baseScale * Math.exp(-event.deltaY * 0.002);
  applyLiveZoom(nextScale);
  commitLiveZoom(180);
}, { passive: false });
els.pdfStage.addEventListener("gesturestart", (event) => {
  if (!state.reader.pdfDoc) return;
  event.preventDefault();
  clearTimeout(state.reader.zoomTimer);
  state.reader.gestureStartScale = state.reader.previewScale || state.reader.scale;
  state.reader.zoomAnchorPage = state.reader.page;
  setCenteredZoomOrigin();
});
els.pdfStage.addEventListener("gesturechange", (event) => {
  if (!state.reader.pdfDoc) return;
  event.preventDefault();
  const nextScale = state.reader.gestureStartScale * event.scale;
  applyLiveZoom(nextScale);
});
els.pdfStage.addEventListener("gestureend", (event) => {
  if (!state.reader.pdfDoc) return;
  event.preventDefault();
  commitLiveZoom(60);
});
document.querySelectorAll("[data-reader-tool]").forEach((button) => {
  button.addEventListener("click", () => setReaderTool(button.dataset.readerTool));
});
document.addEventListener("selectionchange", () => {
  clearTimeout(window.readerSelectionTimer);
  window.readerSelectionTimer = setTimeout(updateSelectionToolbar, 80);
});
els.pdfStage.addEventListener("mouseup", () => setTimeout(updateSelectionToolbar, 0));
els.pdfStage.addEventListener("keyup", () => setTimeout(updateSelectionToolbar, 0));
els.pdfStage.addEventListener("click", async (event) => {
  if (!state.reader.pdfDoc || !event.metaKey) return;
  const url = pdfLinkAtPoint(event.clientX, event.clientY);
  if (!url) return;
  event.preventDefault();
  event.stopPropagation();
  hideSelectionToolbar();
  await openPaperInBrowser(url);
});
els.selectionToolbar.addEventListener("mousedown", (event) => event.preventDefault());
els.selectionToolbar.addEventListener("click", async (event) => {
  const action = event.target.closest("[data-selection-action]")?.dataset.selectionAction;
  if (!action) return;
  if (action === "highlight") {
    await highlightSelection();
  } else if (action === "note") {
    await noteSelection();
  } else if (action === "copy") {
    await copySelectionText();
  }
});
els.annotationMenu.addEventListener("click", (event) => {
  event.stopPropagation();
});
els.annotationMenuCancel.addEventListener("click", hideAnnotationMenu);
els.annotationMenuDelete.addEventListener("click", async () => {
  const annotation = annotationById(state.reader.annotationMenuId);
  await deleteAnnotation(annotation, false);
});
els.pdfPages.addEventListener("contextmenu", async (event) => {
  const marker = event.target.closest(".annotation");
  const annotation = marker
    ? annotationById(marker.dataset.annotationId)
    : annotationAtPoint(event.clientX, event.clientY);
  if (!annotation) return;
  event.preventDefault();
  event.stopPropagation();
  showAnnotationMenu(annotation, event.clientX, event.clientY);
});
els.pdfStage.addEventListener("contextmenu", async (event) => {
  const annotation = annotationAtPoint(event.clientX, event.clientY);
  if (!annotation) return;
  event.preventDefault();
  event.stopPropagation();
  showAnnotationMenu(annotation, event.clientX, event.clientY);
});
document.addEventListener("click", (event) => {
  if (event.target.closest("#annotationMenu")) return;
  hideAnnotationMenu();
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") hideAnnotationMenu();
});
els.pdfPages.addEventListener("pointerdown", (event) => {
  if (!state.reader.pdfDoc || state.reader.tool === "read") return;
  if (event.target.closest(".annotation")) return;
  const layer = event.target.closest(".annotation-layer");
  if (!layer) return;
  event.preventDefault();
  const start = readerPoint(event, layer);
  const page = Number(layer.dataset.page);
  if (state.reader.tool === "note") {
    const text = prompt("Note for this location");
    if (!text) return;
    saveAnnotation({
      page,
      kind: "note",
      x: start.x,
      y: start.y,
      width: 0.026,
      height: 0.026,
      color: "#7cc4ff",
      text,
    }).catch(console.error);
    return;
  }
  const draft = document.createElement("div");
  draft.className = "annotation-draft";
  layer.appendChild(draft);
  state.reader.draft = draft;
  state.reader.dragStart = start;
  state.reader.dragPage = page;
  state.reader.activeLayer = layer;
  setDraftBox({ ...start, width: 0, height: 0 });
  layer.setPointerCapture(event.pointerId);
});
els.pdfPages.addEventListener("pointermove", (event) => {
  if (!state.reader.draft || !state.reader.dragStart || !state.reader.activeLayer) return;
  setDraftBox(annotationBox(state.reader.dragStart, readerPoint(event, state.reader.activeLayer)));
});
els.pdfPages.addEventListener("pointerup", async (event) => {
  if (!state.reader.draft || !state.reader.dragStart || !state.reader.activeLayer) return;
  const box = annotationBox(state.reader.dragStart, readerPoint(event, state.reader.activeLayer));
  state.reader.draft.remove();
  state.reader.draft = null;
  state.reader.dragStart = null;
  state.reader.activeLayer = null;
  if (box.width < 0.006 || box.height < 0.006) return;
  await saveAnnotation({
    page: state.reader.dragPage,
    kind: "highlight",
    ...box,
    color: "#ffd966",
  });
});
window.addEventListener("keydown", async (event) => {
  if (!document.body.classList.contains("reader-open")) return;
  if (event.key === "Escape") {
    closeReader();
  } else if (event.key === "ArrowLeft" && state.reader.page > 1) {
    scrollToReaderPage(state.reader.page - 1);
  } else if (event.key === "ArrowRight" && state.reader.page < state.reader.pageCount) {
    scrollToReaderPage(state.reader.page + 1);
  }
});

document.querySelector("#deleteBtn").addEventListener("click", async () => {
  const id = fields.id.value;
  if (!id || !confirm("Delete this paper?")) return;
  await api(`/api/papers/${id}`, { method: "DELETE" });
  els.paperDialog.close();
  await load();
});

els.paperForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const id = fields.id.value;
  const data = paperFromForm();
  if (id) {
    await api(`/api/papers/${id}`, { method: "PUT", body: JSON.stringify(data) });
  } else {
    await api("/api/papers", { method: "POST", body: JSON.stringify(data) });
  }
  els.paperDialog.close();
  await load();
});

els.captureForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  await api("/api/capture", {
    method: "POST",
    body: JSON.stringify({
      url: document.querySelector("#captureUrlField").value.trim(),
      tags: document.querySelector("#captureTagsField").value.split(",").map((tag) => tag.trim()).filter(Boolean),
    }),
  });
  els.captureDialog.close();
  await load();
});

els.searchInput.addEventListener("input", () => {
  state.query = els.searchInput.value.trim();
  clearTimeout(window.searchTimer);
  window.searchTimer = setTimeout(load, 160);
});

els.sortSelect.addEventListener("change", () => {
  state.sort = els.sortSelect.value;
  renderPapers();
});

load().catch((error) => {
  console.error(error);
  alert("Could not load Nimble Scholar data.");
});
