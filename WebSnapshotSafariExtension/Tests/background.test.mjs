import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import vm from "node:vm";

const source = await readFile(new URL("../Resources/background.js", import.meta.url), "utf8");

function harness(sendNativeMessage = async () => ({ accepted: true })) {
    const messages = [], badges = [], titles = [];
    let click;
    vm.runInNewContext(source, {
        URL,
        crypto: { randomUUID: () => "ca5b1205-65ef-4210-9ab1-936936c159b0" },
        browser: {
            action: {
                onClicked: { addListener: callback => { click = callback; } },
                setBadgeText: async value => { badges.push(value); },
                setTitle: async value => { titles.push(value); },
            },
            runtime: { sendNativeMessage: async (app, message) => {
                messages.push({ app, message });
                return sendNativeMessage(app, message);
            } },
        },
    });
    return { click, messages, badges, titles };
}

test("one click delivers the current URL without claiming PDF completion", async () => {
    const h = harness();
    await h.click({ id: 7, url: "https://example.com/?q=a%26b#section" });
    assert.equal(h.messages.length, 1);
    assert.equal(h.messages[0].message.url, "https://example.com/?q=a%26b#section");
    assert.equal(h.messages[0].message.type, "save-page");
    assert.equal(h.badges.at(-1).text, "");
    assert.match(h.titles.at(-1).title, /Sent to WebSnapshot/);
});

test("unsupported and credential-bearing pages never reach the native app", async () => {
    for (const url of ["file:///private/a", "about:blank", "javascript:alert(1)", "https://user:pass@example.com", undefined]) {
        const h = harness();
        await h.click({ id: 1, url });
        assert.equal(h.messages.length, 0);
        assert.equal(h.badges.at(-1).text, "!");
    }
});

test("native delivery failure is visible and the button can be retried", async () => {
    const h = harness(async () => ({ accepted: false, error: "Open WebSnapshot first." }));
    await h.click({ id: 2, url: "https://example.com" });
    assert.equal(h.badges.at(-1).text, "!");
    assert.equal(h.titles.at(-1).title, "Open WebSnapshot first.");
    await h.click({ id: 2, url: "https://example.com" });
    assert.equal(h.messages.length, 2);
});

test("repeated clicks during delivery do not duplicate the request", async () => {
    let accept;
    const h = harness(() => new Promise(resolve => { accept = resolve; }));
    const first = h.click({ id: 4, url: "https://example.com" });
    await h.click({ id: 4, url: "https://example.com" });
    accept({ accepted: true });
    await first;
    assert.equal(h.messages.length, 1);
});

test("native transport errors are shown on the toolbar button", async () => {
    const h = harness(async () => { throw new Error("Extension unavailable"); });
    await h.click({ id: 5, url: "https://example.com" });
    assert.equal(h.badges.at(-1).text, "!");
    assert.match(h.titles.at(-1).title, /Extension unavailable/);
});
