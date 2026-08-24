function showError(message) {
  chrome.action.setBadgeBackgroundColor({ color: "#d20f39" });
  chrome.action.setBadgeText({ text: "!" });
  chrome.notifications.create({
    type: "basic",
    iconUrl: "error.svg",
    title: "Download Video failed",
    message,
    priority: 2
  });
}

function sendUrl(url) {
  if (!url || !/^https?:/i.test(url)) {
    showError("The active tab is not an HTTP or HTTPS page.");
    return;
  }
  chrome.action.setBadgeText({ text: "" });
  chrome.runtime.sendNativeMessage("com.omarchy.ytdlp", { url }, (response) => {
    const error = chrome.runtime.lastError;
    if (error) {
      showError("Could not start the native downloader: " + error.message);
      return;
    }
    if (!response || response.accepted !== true) {
      showError("The native downloader rejected the request.");
    }
  });
}

function triggerDownload(tab) {
  if (!tab) {
    showError("Brave did not provide an active tab.");
    return;
  }
  if (tab.url) {
    sendUrl(tab.url);
    return;
  }
  if (tab.id === undefined) {
    showError("Brave did not provide the active page URL.");
    return;
  }
  chrome.scripting
    .executeScript({ target: { tabId: tab.id }, func: () => location.href })
    .then((results) => sendUrl(results && results[0] && results[0].result))
    .catch((error) => showError("Could not read the active page URL: " + error));
}

chrome.commands.onCommand.addListener((command) => {
  if (command !== "download-video") return;
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    triggerDownload(tabs[0]);
  });
});

chrome.action.onClicked.addListener(triggerDownload);
