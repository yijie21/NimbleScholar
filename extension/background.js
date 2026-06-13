const PAPER_APP_ENDPOINT = "http://127.0.0.1:8765/api/capture";

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
}

async function captureCurrentTab(extra = {}) {
  const tab = await getActiveTab();
  const settings = await readSettings();
  const pageMetadata = await collectPageMetadata(tab.id);
  const payload = {
    ...pageMetadata,
    url: tab.url,
    tags: extra.tags ?? settings.defaultTags,
  };

  const response = await fetch(PAPER_APP_ENDPOINT, {
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
  if (message?.type !== "capture-current-tab") return false;
  captureCurrentTab({ tags: message.tags })
    .then((data) => sendResponse({ ok: true, data }))
    .catch((error) => sendResponse({ ok: false, error: error.message }));
  return true;
});
