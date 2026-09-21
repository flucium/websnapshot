const sendingTabs = new Set();

browser.action.onClicked.addListener(async (tab) => {
    if (tab.id == null || sendingTabs.has(tab.id)) return;
    sendingTabs.add(tab.id);
    try {
        const url = new URL(tab.url);
        if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) {
            throw new Error("Open an HTTP or HTTPS webpage to save a PDF.");
        }
        await browser.action.setBadgeText({ tabId: tab.id, text: "…" });
        const response = await browser.runtime.sendNativeMessage("flucium.WebSnapshot", {
            type: "save-page",
            id: crypto.randomUUID(),
            url: url.href,
        });
        if (!response?.accepted) {
            throw new Error(response?.error || "WebSnapshot could not be opened.");
        }
        
        await browser.action.setBadgeText({ tabId: tab.id, text: "" });
        await browser.action.setTitle({ tabId: tab.id, title: "Sent to WebSnapshot — see the app for progress" });
    } catch (error) {
        await browser.action.setBadgeText({ tabId: tab.id, text: "!" }).catch(() => {});
        await browser.action.setTitle({
            tabId: tab.id,
            title: error.message || "Could not send this page to WebSnapshot.",
        }).catch(() => {});
    } finally {
        sendingTabs.delete(tab.id);
    }
});
