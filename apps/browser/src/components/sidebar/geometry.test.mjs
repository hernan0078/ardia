import assert from "node:assert/strict";
import { test } from "node:test";
const { useBrowser } = await import("../../store/browser.ts");
const { sidebarEntries } = await import("./entries.ts");
const { entriesHeight, entriesWithin, entryHeight, firstPaintEntries, rowSpan, startsOffScreen, FIRST_PAINT_HEIGHT } = await import("./geometry.ts");
await import("../../test-native-stub.mjs");

const S = () => useBrowser.getState();
const profile = { id: "default", name: "Personal", color: "plum", icon: null, createdAt: 0 };
const tab = (i) => ({
  id: `t${i}`, windowId: "w", profileId: "default", url: `https://example.com/${i}`, title: `Tab ${i}`, favicon: null, pinned: false,
  muted: false, zoom: 1, customTitle: null, customIcon: null, pinnedUrl: null, openerId: null, createdAt: i, lastActiveAt: i,
});

function hydrate({ collapsed = false } = {}) {
  const tabs = Array.from({ length: 40 }, (_, i) => tab(i));
  S().hydrate({
    profiles: { default: profile },
    windows: { w: { id: "w", profileId: "default", incognito: false, tabIds: tabs.map((t) => t.id), activeTabIds: { default: "t0" }, sidebarOpen: true, frame: [0, 0, 1200, 800], createdAt: 0 } },
    tabs: Object.fromEntries(tabs.map((t) => [t.id, t])),
    groups: { g: { id: "g", windowId: "w", profileId: "default", name: "G", icon: null, color: "blue", collapsed, pinned: false, tabIds: ["t2", "t3", "t4", "t5", "t6"], createdAt: 0 } },
  });
  return sidebarEntries(S(), "w", "default").list;
}

test("entriesWithin counts the entries that start inside the height, a group as its whole block", () => {
  const list = hydrate();
  assert.deepEqual(list.slice(0, 4), ["t:t0", "t:t1", "g:g", "t:t7"]);
  const s = S();
  const pitch = entryHeight(s, "w", "default", "t:t0") + 3;
  assert.equal(entriesWithin(s, "w", "default", list, 0), 0);
  assert.equal(entriesWithin(s, "w", "default", list, 1), 1);
  assert.equal(entriesWithin(s, "w", "default", list, pitch), 1);
  assert.equal(entriesWithin(s, "w", "default", list, pitch + 1), 2);
  const group = entryHeight(s, "w", "default", "g:g");
  assert.ok(group > 5 * pitch);
  assert.equal(entriesWithin(s, "w", "default", list, 2 * pitch + 1), 3);
  assert.equal(entriesWithin(s, "w", "default", list, 2 * pitch + group + 3), 3);
  assert.equal(entriesWithin(s, "w", "default", list, 2 * pitch + group + 4), 4);
  assert.equal(entriesWithin(s, "w", "default", list, 1e6), list.length);
});

test("the entries within a height cover it: the rest start below it", () => {
  const list = hydrate({ collapsed: true });
  const s = S();
  for (const height of [10, 100, 333, 800, 1300]) {
    const n = entriesWithin(s, "w", "default", list, height);
    assert.ok(n === list.length || entriesHeight(s, "w", "default", list.slice(0, n)) + 3 >= height, `height ${height}`);
    assert.ok(n === 0 || entriesHeight(s, "w", "default", list.slice(0, n - 1)) + (n > 1 ? 3 : 0) < height, `height ${height}`);
  }
});

test("lazySidebarRows on: a page first mounts the entries its window's saved frame shows", () => {
  const list = hydrate();
  const s = S();
  const n = firstPaintEntries(s, "w", "default", list, true);
  assert.equal(n, entriesWithin(s, "w", "default", list, 800));
  assert.ok(n > 0 && n < list.length);
  S().hydrate({ ...s, windows: { w: { ...s.windows.w, frame: undefined } } });
  assert.equal(firstPaintEntries(S(), "w", "default", list, true), entriesWithin(S(), "w", "default", list, FIRST_PAINT_HEIGHT));
  assert.equal(startsOffScreen(true, false), true);
  assert.equal(startsOffScreen(true, true), false);
});

test("lazySidebarRows off: 64 entries at first, and no page waits", () => {
  const list = hydrate();
  assert.equal(firstPaintEntries(S(), "w", "default", list, false), 64);
  assert.equal(startsOffScreen(false, false), false);
  assert.equal(startsOffScreen(false, true), false);
});

test("Arc-style sidebar text: heights, first paint and reveal spans follow Arc's 36 pt rows and 5 pt gaps", () => {
  const list = hydrate();
  const ardia = S();
  assert.equal(entryHeight(ardia, "w", "default", "t:t0"), 34);
  S().updateSettings({ arcSidebarText: true });
  const s = S();
  assert.equal(entryHeight(s, "w", "default", "t:t0"), 36);
  const group = 0.5 * 2 + 36 + 5 * 36 + 4 * 5 + 2;
  assert.equal(entryHeight(s, "w", "default", "g:g"), group);
  assert.equal(entriesHeight(s, "w", "default", list.slice(0, 4)), 36 * 3 + group + 3 * 5);
  assert.equal(entriesWithin(s, "w", "default", list, 41), 1);
  assert.equal(entriesWithin(s, "w", "default", list, 42), 2);
  assert.deepEqual(rowSpan(s, "w", "default", "t1", false), { section: "list", top: 41, height: 36 });
  assert.deepEqual(rowSpan(s, "w", "default", "t1", true), { section: "list", top: 82, height: 36 });
  assert.deepEqual(rowSpan(s, "w", "default", "t4", false), { section: "list", top: 82 + 0.5 + 36 + 2 * 41, height: 36 });
  assert.deepEqual(rowSpan(s, "w", "default", "t7", false), { section: "list", top: 82 + group + 5, height: 36 });
  S().updateSettings({ arcSidebarText: false });
  assert.deepEqual(rowSpan(S(), "w", "default", "t1", false), { section: "list", top: 37, height: 34 });
});
