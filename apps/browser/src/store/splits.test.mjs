import assert from "node:assert/strict";
import { test } from "node:test";
const { useBrowser } = await import("./browser.ts");
const { activeTabId } = await import("./model.ts");
const { slotsOf } = await import("./splits.ts");
const S = () => useBrowser.getState();

function setup() {
  S().hydrate({});
  S().updateSettings({ cmdClickCreatesTabGroup: false, newTabPosition: "bottom" });
  const windowId = S().createWindow({ url: "https://a.example" });
  const a = S().windows[windowId].tabIds[0];
  const [b, c, d] = ["b", "c", "d"].map((name) => S().newTab(windowId, { url: `https://${name}.example`, background: true }));
  return { windowId, a, b, c, d };
}

test("split existing tabs and add a third without replacing their live pages", () => {
  const { windowId, a, b, c, d } = setup();
  S().updateLive(a, { audio: true });
  const live = S().live[a];
  const urls = [a, b, c].map((id) => S().tabs[id].url);
  const first = S().openSplitPane(windowId, { anchorTabId: a, tabId: c });
  assert.equal(first.ok, true);
  const added = S().openSplitPane(windowId, { anchorTabId: c, tabId: b });
  assert.equal(added.ok, true);
  assert.equal(added.splitId, first.splitId);
  assert.deepEqual(S().splits[first.splitId].tabIds, [a, c, b]);
  assert.deepEqual(S().windows[windowId].tabIds, [a, c, b, d]);
  assert.deepEqual([a, b, c].map((id) => S().tabs[id].url), urls);
  assert.equal(S().live[a], live);
  assert.equal(activeTabId(S(), windowId), b);
  assert.equal(Object.keys(S().tabs).length, 4);
});

test("top and bottom drops build vertical and mixed splits and separating keeps every page", () => {
  const { windowId, a, b, c } = setup();
  const first = S().openSplitPane(windowId, { anchorTabId: a, tabId: b, side: "top" });
  assert.equal(first.ok, true);
  assert.equal(S().splits[first.splitId].orientation, "vertical");
  assert.deepEqual(S().splits[first.splitId].tabIds, [b, a]);
  S().openSplitPane(windowId, { anchorTabId: a, tabId: c, side: "right" });
  assert.deepEqual(slotsOf(S().splits[first.splitId]), [[b], [a, c]]);
  const tabs = S().tabs;
  const active = activeTabId(S(), windowId);
  S().separateSplit(first.splitId);
  assert.deepEqual(S().splits, {});
  assert.equal(S().tabs, tabs);
  assert.equal(activeTabId(S(), windowId), active);
});

test("moving a tab from another split leaves that split's other page alive", () => {
  const { windowId, a, b, c, d } = setup();
  const first = S().createSplit([a, b]);
  const second = S().createSplit([c, d]);
  S().openSplitPane(windowId, { anchorTabId: b, tabId: c, side: "bottom" });
  assert.deepEqual(slotsOf(S().splits[first]), [[a], [b, c]]);
  assert.equal(S().splits[second], undefined);
  assert.ok(S().tabs[d]);
  assert.deepEqual(S().windows[windowId].tabIds, [a, b, c, d]);
});

test("invalid or full split drops do not mutate tabs or cross window and profile boundaries", () => {
  const { windowId, a, b, c, d } = setup();
  const otherWindow = S().createWindow({ url: "https://other.example" });
  const other = S().windows[otherWindow].tabIds[0];
  const profile = S().createProfile({ name: "Other" });
  const different = S().newTab(windowId, { url: "https://profile.example", profileId: profile });
  for (const tabId of [a, "missing", other, different]) {
    const before = S();
    assert.deepEqual(S().openSplitPane(windowId, { anchorTabId: a, tabId }), { ok: false, reason: "invalid" });
    assert.equal(S(), before);
  }
  S().createSplit([a, b, c]);
  const before = S();
  assert.deepEqual(S().openSplitPane(windowId, { anchorTabId: a, tabId: d }), { ok: false, reason: "max" });
  assert.equal(S(), before);
});
