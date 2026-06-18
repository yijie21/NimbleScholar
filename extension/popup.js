const tagsInput = document.querySelector("#tagsInput");
const defaultTagsInput = document.querySelector("#defaultTagsInput");
const saveBtn = document.querySelector("#saveBtn");
const saveLinkBtn = document.querySelector("#saveLinkBtn");
const saveSettingsBtn = document.querySelector("#saveSettingsBtn");
const statusEl = document.querySelector("#status");

function setStatus(message, kind = "") {
  statusEl.textContent = message;
  statusEl.dataset.kind = kind;
}

async function loadSettings() {
  const settings = await chrome.storage.sync.get({ defaultTags: "to-read" });
  tagsInput.value = settings.defaultTags;
  defaultTagsInput.value = settings.defaultTags;
}

async function saveSettings() {
  await chrome.storage.sync.set({ defaultTags: defaultTagsInput.value.trim() || "to-read" });
  tagsInput.value = defaultTagsInput.value.trim() || "to-read";
  setStatus("Settings saved.", "success");
}

async function capture() {
  saveBtn.disabled = true;
  setStatus("Saving paper...", "");
  const response = await chrome.runtime.sendMessage({
    type: "capture-current-tab",
    tags: tagsInput.value.trim(),
  });
  saveBtn.disabled = false;

  if (!response?.ok) {
    setStatus(response?.error || "Could not save. Open Nimble Scholar.app first.", "error");
    return;
  }

  const paper = response.data?.paper;
  setStatus(paper?.title ? `Saved: ${paper.title}` : "Saved paper.", "success");
}

async function captureLink() {
  saveLinkBtn.disabled = true;
  setStatus("Saving link...", "");
  const response = await chrome.runtime.sendMessage({
    type: "capture-link-current-tab",
    tags: tagsInput.value.trim(),
  });
  saveLinkBtn.disabled = false;

  if (!response?.ok) {
    setStatus(response?.error || "Could not save. Open Nimble Scholar.app first.", "error");
    return;
  }
  setStatus("Saved as link.", "success");
}

saveBtn.addEventListener("click", capture);
saveLinkBtn.addEventListener("click", captureLink);
saveSettingsBtn.addEventListener("click", saveSettings);
// Don't auto-save on open any more: the page might be a paper OR a link, so let the
// user choose. (Previously opening the popup immediately saved the page as a paper.)
loadSettings();
