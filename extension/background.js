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
        return {
          title: meta("citation_title") || meta("og:title") || document.title,
          authors: [...document.querySelectorAll('meta[name="citation_author"]')]
            .map((item) => item.content)
            .filter(Boolean)
            .join(", "),
          doi: meta("citation_doi"),
          pdf_url: meta("citation_pdf_url"),
          teaser_url: meta("og:image") || meta("twitter:image"),
          abstract: meta("description") || meta("og:description"),
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
  const pageMetadata = isPdf ? {} : await collectPageMetadata(tab.id);
  const payload = {
    ...pageMetadata,
    url: tab.url,
    tags: extra.tags ?? settings.defaultTags,
  };
  if (isPdf) {
    payload.pdf_url = tab.url;
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
  const settings = await readSettings();
  const meta = await collectLinkMetadata(tab.id);
  const payload = {
    ...meta,
    url: tab.url,
    tags: extra.tags ?? settings.defaultTags,
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

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "capture-current-tab") {
    captureCurrentTab({ tags: message.tags })
      .then((data) => sendResponse({ ok: true, data }))
      .catch((error) => sendResponse({ ok: false, error: error.message }));
    return true;
  }
  if (message?.type === "capture-link-current-tab") {
    captureLinkCurrentTab({ tags: message.tags })
      .then((data) => sendResponse({ ok: true, data }))
      .catch((error) => sendResponse({ ok: false, error: error.message }));
    return true;
  }
  return false;
});
