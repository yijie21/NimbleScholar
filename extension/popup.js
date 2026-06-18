const tagsInput = document.querySelector("#tagsInput");
const defaultTagsInput = document.querySelector("#defaultTagsInput");
const saveBtn = document.querySelector("#saveBtn");
const savePaperBtn = document.querySelector("#savePaperBtn");
const saveLinkBtn = document.querySelector("#saveLinkBtn");
const saveSettingsBtn = document.querySelector("#saveSettingsBtn");
const statusEl = document.querySelector("#status");

const allButtons = [saveBtn, savePaperBtn, saveLinkBtn];

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

// Send a capture message and report the result. `type` picks auto / paper / link.
async function save(type, label) {
  allButtons.forEach((b) => (b.disabled = true));
  setStatus(`Saving${label ? " " + label : ""}…`, "");
  const response = await chrome.runtime.sendMessage({ type, tags: tagsInput.value.trim() });
  allButtons.forEach((b) => (b.disabled = false));

  if (!response?.ok) {
    setStatus(response?.error || "Could not save. Open Nimble Scholar.app first.", "error");
    return;
  }
  const kind = response.kind === "link" ? "link" : "paper";
  const title = response.data?.data?.paper?.title;
  setStatus(title ? `Saved ${kind}: ${title}` : `Saved as ${kind}.`, "success");
}

saveBtn.addEventListener("click", () => save("capture-auto"));
savePaperBtn.addEventListener("click", () => save("capture-current-tab", "as paper"));
saveLinkBtn.addEventListener("click", () => save("capture-link-current-tab", "as link"));
saveSettingsBtn.addEventListener("click", saveSettings);

loadSettings();
