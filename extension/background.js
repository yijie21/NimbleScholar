// The app binds a fixed base port (8917) and walks forward if it's busy. We probe a
// wide set of candidate ports in PARALLEL (covering the current + historical defaults)
// and use whichever answers /api/ping first.
let cachedPort = null;

function candidatePorts() {
  const ports = new Set();
  for (let p = 8917; p <= 8940; p++) ports.add(p);   // current default range
  for (let p = 8780; p <= 8800; p++) ports.add(p);   // earlier default range
  [8765, 8766, 8767, 8768, 8781, 8782, 8783].forEach((p) => ports.add(p));
  return [...ports];
}

async function pingPort(port, timeoutMs = 600) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`http://127.0.0.1:${port}/api/ping`, { signal: controller.signal });
    if (!res.ok) return false;
    const data = await res.json().catch(() => ({}));
    return data?.app === "nimble-scholar";
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

async function findBase() {
  if (cachedPort && (await pingPort(cachedPort))) {
    return `http://127.0.0.1:${cachedPort}`;
  }
  // Probe all candidates concurrently; resolve with the first that answers.
  const found = await Promise.any(
    candidatePorts().map(async (p) => {
      if (await pingPort(p)) return p;
      throw new Error("no");
    })
  ).catch(() => null);
  if (found) {
    cachedPort = found;
    return `http://127.0.0.1:${found}`;
  }
  throw new Error(
    "Nimble Scholar isn't running, or the browser can't reach 127.0.0.1 (a proxy may be blocking localhost). " +
      "Open the app, and add 127.0.0.1/localhost to your proxy bypass list."
  );
}

async function findEndpoint() {
  return `${await findBase()}/api/capture`;
}

async function readSettings() {
  const result = await chrome.storage.sync.get({
    defaultTags: "to-read",
    autoClose: false,
  });
  return result;
}

async function getActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab || !tab.id || !tab.url) {
    throw new Error("No active browser tab found.");
  }
  return tab;
}

async function collectPageMetadata(tabId) {
  try {
    const [result] = await chrome.scripting.executeScript({
      target: { tabId },
      func: () => {
        const meta = (name) =>
          document.querySelector(`meta[name="${name}"],meta[property="${name}"]`)?.content || "";
        // Sites emit either repeated citation_author tags or one semicolon-separated
        // citation_authors tag (OpenReview does the latter).
        const authors =
          [...document.querySelectorAll('meta[name="citation_author"]')]
            .map((item) => item.content)
            .filter(Boolean)
            .join(", ") ||
          meta("citation_authors")
            .split(";")
            .map((s) => s.trim())
            .filter(Boolean)
            .join(", ");
        return {
          title: meta("citation_title") || meta("og:title") || document.title,
          authors,
          doi: meta("citation_doi"),
          pdf_url: meta("citation_pdf_url"),
          teaser_url: meta("og:image") || meta("twitter:image"),
          abstract: meta("citation_abstract") || meta("description") || meta("og:description"),
          source: location.hostname,
        };
      },
    });
    return result?.result || {};
  } catch {
    // PDF viewer / restricted page — can't inject. Capture with just the URL.
    return {};
  }
}

// --- OpenReview -------------------------------------------------------------
// The site (pages, API, PDFs) sits behind a Cloudflare browser check that server-side
// fetches from the app fail — but THIS browser has already passed it. So for OpenReview
// we read the forum page from here, with the browser's cookies, and hand the app
// complete metadata it could never fetch itself.

function openReviewID(url) {
  try {
    const u = new URL(url);
    if (!/(^|\.)openreview\.net$/.test(u.hostname)) return null;
    if (!/^\/(forum|pdf|attachment)$/.test(u.pathname)) return null;
    return u.searchParams.get("id");
  } catch {
    return null;
  }
}

function decodeEntities(s) {
  return (s || "")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#0*39;/g, "'").replace(/&apos;/g, "'");
}

// Service workers have no DOMParser — pull <meta> tags out with a tolerant regex.
function parseMetaTags(html) {
  const out = {};
  for (const tag of html.match(/<meta\s[^>]*>/gi) || []) {
    const name = tag.match(/(?:name|property)\s*=\s*["']([^"']+)["']/i)?.[1]?.toLowerCase();
    const content = tag.match(/content\s*=\s*["']([^"']*)["']/i)?.[1];
    if (!name || content == null) continue;
    (out[name] ||= []).push(decodeEntities(content));
  }
  return out;
}

async function fetchOpenReviewMetadata(id) {
  try {
    const res = await fetch(`https://openreview.net/forum?id=${encodeURIComponent(id)}`, {
      credentials: "include",
    });
    if (!res.ok) return {};
    const tags = parseMetaTags(await res.text());
    const first = (name) => tags[name]?.[0] || "";
    const authors =
      (tags["citation_author"] || []).join(", ") ||
      first("citation_authors").split(";").map((s) => s.trim()).filter(Boolean).join(", ");
    return {
      title: first("citation_title") || first("og:title").replace(/\s*\|\s*OpenReview\s*$/i, ""),
      authors,
      abstract: first("citation_abstract") || first("description") || first("og:description"),
      pdf_url: first("citation_pdf_url") || `https://openreview.net/pdf?id=${id}`,
      source: "openreview.net",
    };
  } catch {
    return {};
  }
}

function titleFromPdfURL(url) {
  try {
    const file = decodeURIComponent(url.split("?")[0].split("/").pop() || "");
    return file.replace(/\.pdf$/i, "").replace(/[_+]/g, " ").trim();
  } catch {
    return "";
  }
}

async function captureCurrentTab(extra = {}) {
  const tab = await getActiveTab();
  const settings = await readSettings();
  const isPdf = /\.pdf($|\?)/i.test(tab.url);
  const orId = openReviewID(tab.url);
  let pageMetadata = {};
  if (orId && !/\/forum$/.test(new URL(tab.url).pathname)) {
    // OpenReview PDF/attachment tab: the PDF viewer can't be injected — read the
    // forum page from here instead (the app's own fetch would hit the browser check).
    pageMetadata = await fetchOpenReviewMetadata(orId);
  } else if (!isPdf) {
    pageMetadata = await collectPageMetadata(tab.id);
    // Forum tab captured before the SPA populated its meta tags → fetch it directly.
    if (orId && !pageMetadata.title) pageMetadata = await fetchOpenReviewMetadata(orId);
  }
  const payload = {
    ...pageMetadata,
    url: tab.url,
    // Papers fall back to the default tag when none were typed.
    tags: extra.tags && extra.tags.trim() ? extra.tags : settings.defaultTags,
  };
  if (orId) {
    // Canonical forum URL keeps duplicates merged across forum/pdf captures.
    payload.url = `https://openreview.net/forum?id=${orId}`;
    if (!payload.pdf_url) payload.pdf_url = `https://openreview.net/pdf?id=${orId}`;
  }
  if (isPdf) {
    payload.pdf_url = payload.pdf_url || tab.url;
    if (!payload.title) payload.title = titleFromPdfURL(tab.url);
  }

  const endpoint = await findEndpoint();
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    throw new Error(`Nimble Scholar returned ${response.status}.`);
  }
  return response.json();
}

// --- Save as Link (webpage / GitHub) ----------------------------------------

async function collectLinkMetadata(tabId) {
  try {
    const [result] = await chrome.scripting.executeScript({
      target: { tabId },
      func: () => {
        const meta = (name) =>
          document.querySelector(`meta[name="${name}"],meta[property="${name}"]`)?.content || "";
        return {
          title: meta("og:title") || document.title,
          image_url: meta("og:image") || meta("twitter:image"),
          description: meta("og:description") || meta("description"),
          source: location.hostname,
        };
      },
    });
    return result?.result || {};
  } catch {
    return {};
  }
}

async function captureLinkCurrentTab(extra = {}) {
  const tab = await getActiveTab();
  const meta = await collectLinkMetadata(tab.id);
  const payload = {
    ...meta,
    url: tab.url,
    // Links never get the default tag — only what the user explicitly typed.
    tags: extra.tags && extra.tags.trim() ? extra.tags : "",
  };
  const base = await findBase();
  const response = await fetch(`${base}/api/capture-link`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    throw new Error(`Nimble Scholar returned ${response.status}.`);
  }
  return response.json();
}

// --- Auto-detect: paper vs link ---------------------------------------------

// Hosts that are (almost) always scholarly papers.
const PAPER_HOSTS = [
  "arxiv.org", "ar5iv.org", "ar5iv.labs.arxiv.org", "openreview.net",
  "aclanthology.org", "thecvf.com", "proceedings.mlr.press", "papers.nips.cc",
  "dl.acm.org", "ieeexplore.ieee.org", "link.springer.com", "nature.com",
  "sciencedirect.com", "biorxiv.org", "medrxiv.org", "pubmed.ncbi.nlm.nih.gov",
  "ncbi.nlm.nih.gov", "semanticscholar.org", "jmlr.org",
];

async function pageHasCitationMeta(tabId) {
  try {
    const [r] = await chrome.scripting.executeScript({
      target: { tabId },
      func: () =>
        !!document.querySelector(
          'meta[name="citation_title"],meta[name="citation_pdf_url"],meta[name="citation_doi"]'
        ),
    });
    return !!r?.result;
  } catch {
    return false;
  }
}

// Decide whether the active tab should be saved as a paper or a link.
async function decideKind() {
  const tab = await getActiveTab();
  if (/\.pdf($|\?)/i.test(tab.url)) return "paper";          // a PDF is a paper
  let host = "";
  try { host = new URL(tab.url).hostname.replace(/^www\./, ""); } catch {}
  if (host.endsWith("github.com")) return "link";            // code repo → link
  if (PAPER_HOSTS.some((h) => host === h || host.endsWith("." + h))) return "paper";
  // Pages exposing Highwire/Scholar citation tags are papers; everything else is a link.
  return (await pageHasCitationMeta(tab.id)) ? "paper" : "link";
}

async function captureAuto(extra = {}) {
  const kind = await decideKind();
  const data = kind === "paper"
    ? await captureCurrentTab(extra)
    : await captureLinkCurrentTab(extra);
  return { kind, data };
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "capture-auto") {
    captureAuto({ tags: message.tags })
      .then((res) => sendResponse({ ok: true, kind: res.kind, data: res.data }))
      .catch((error) => sendResponse({ ok: false, error: error.message }));
    return true;
  }
  if (message?.type === "capture-current-tab") {
    captureCurrentTab({ tags: message.tags })
      .then((data) => sendResponse({ ok: true, kind: "paper", data }))
      .catch((error) => sendResponse({ ok: false, error: error.message }));
    return true;
  }
  if (message?.type === "capture-link-current-tab") {
    captureLinkCurrentTab({ tags: message.tags })
      .then((data) => sendResponse({ ok: true, kind: "link", data }))
      .catch((error) => sendResponse({ ok: false, error: error.message }));
    return true;
  }
  return false;
});
