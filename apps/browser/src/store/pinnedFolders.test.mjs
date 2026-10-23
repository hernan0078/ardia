import assert from "node:assert/strict";
import { test } from "node:test";
const { useBrowser } = await import("./browser.ts");
const { sidebarEntries, numberedTabs } = await import("../components/sidebar/entries.ts");
const { flushPersistence, loadSession, startPersistence } = await import("../lib/persist.ts");
const stub = await import("../test-native-stub.mjs");

const S = () => useBrowser.getState();
const reset = () => S().hydrate({});
const host = (id) => new URL(S().tabs[id].pinnedUrl || S().tabs[id].url).hostname.replace(".com", "");
const pinned = (w) => sidebarEntries(S(), w).pinned.map((e) => (e.startsWith("g:") ? S().groups[e.slice(2)].name : host(e.slice(2))));
const rowIn = (w, name) => sidebarEntries(S(), w).pinnedRows.find((id) => host(id) === name);
const folderIn = (w, name) => Object.values(S().groups).find((g) => g.windowId === w && g.name === name).id;

function windowWith(...hosts) {
  const w = S().createWindow({ url: `https://${hosts[0]}.com/` });
  const ids = [S().windows[w].tabIds[0]];
  for (const h of hosts.slice(1)) ids.push(S().newTab(w, { url: `https://${h}.com/` }));
  return { w, ids };
}

function rowsAndFolder() {
  reset();
  const { w, ids } = windowWith("a", "b", "c", "d", "e", "f");
  const [a, b, c, d] = ids;
  S().pinTabs([a, b], true, true);
  const folder = S().groupTabs([c, d], { pinned: true, name: "F" });
  return { w, ids, folder };
}

test("a pinned folder moves above, between and below the pinned rows", () => {
  const { w, ids: [a, b, c, d, e], folder } = rowsAndFolder();
  assert.deepEqual(pinned(w), ["a", "b", "F"], "a new pinned folder sits below the rows, as before");
  S().moveGroup(folder, { pinned: true, beforeId: a });
  assert.deepEqual(pinned(w), ["F", "a", "b"]);
  assert.deepEqual(numberedTabs(S(), w).map(host), ["c", "d", "a", "b", "e", "f"], "⌘1–9 follow the sidebar");
  S().moveGroup(folder, { pinned: true, beforeId: b });
  assert.deepEqual(pinned(w), ["a", "F", "b"]);
  S().moveGroup(folder, { pinned: true });
  assert.deepEqual(pinned(w), ["a", "b", "F"]);
  assert.equal(S().groups[folder].beforeRow, undefined);
  S().moveGroup(folder, { pinned: true, beforeId: b });
  S().placeTabs([e], { pinned: false, groupId: folder });
  assert.deepEqual(pinned(w), ["a", "F", "b"], "adding a tab to the folder keeps its place");
  assert.deepEqual(S().groups[folder].tabIds, [c, d, e]);
});

test("two folders keep their order above the same row", () => {
  const { w, ids: [a, , , , e, f], folder } = rowsAndFolder();
  const other = S().groupTabs([e, f], { pinned: true, name: "G" });
  assert.deepEqual(pinned(w), ["a", "b", "F", "G"]);
  S().moveGroup(other, { pinned: true, beforeId: a });
  S().moveGroup(folder, { pinned: true, beforeId: a });
  assert.deepEqual(pinned(w), ["G", "F", "a", "b"]);
  S().moveGroup(folder, { pinned: true, beforeId: S().groups[other].tabIds[0] });
  assert.deepEqual(pinned(w), ["F", "G", "a", "b"]);
  S().moveGroup(folder, { pinned: true, beforeId: S().groups[other].tabIds[0] });
  assert.deepEqual(pinned(w), ["F", "G", "a", "b"], "dropped on its own spot: nothing moves");
});

test("a row dropped below a folder stays below it; dropped at the end, below every folder", () => {
  const { w, ids: [a, b, , , e, f], folder } = rowsAndFolder();
  S().moveGroup(folder, { pinned: true, beforeId: b });
  assert.deepEqual(pinned(w), ["a", "F", "b"]);
  S().placeTabs([e], { pinned: true, row: true, beforeId: b });
  assert.deepEqual(pinned(w), ["a", "F", "e", "b"]);
  S().placeTabs([e], { pinned: true, row: true, beforeId: S().groups[folder].tabIds[0] });
  assert.deepEqual(pinned(w), ["a", "e", "F", "b"]);
  S().placeTabs([e], { pinned: true, row: true, beforeId: null, belowPinnedGroups: true });
  assert.deepEqual(pinned(w), ["a", "F", "b", "e"]);
  S().moveGroup(folder, { pinned: true });
  assert.deepEqual(pinned(w), ["a", "b", "e", "F"]);
  S().placeTabs([a], { pinned: true, row: true, beforeId: null, belowPinnedGroups: true });
  assert.deepEqual(pinned(w), ["b", "e", "F", "a"]);
  S().pinTabs([f], true, true);
  assert.deepEqual(pinned(w), ["b", "e", "F", "a", "f"], "Move to Pinned adds after the last row");
  S().moveGroup(folder, { pinned: true });
  S().pinTabs([a], false);
  S().pinTabs([a], true, true);
  assert.deepEqual(pinned(w), ["b", "e", "f", "a", "F"], "with the folders at the end, Move to Pinned stays above them");
});

test("reopening a closed tab or moving one in from another window keeps a folder's place", () => {
  const { w, ids: [, b, , , e, f], folder } = rowsAndFolder();
  S().moveGroup(folder, { pinned: true, beforeId: b });
  S().closeTab(f);
  S().reopenClosed();
  assert.deepEqual(pinned(w), ["a", "F", "b"]);
  const other = S().createWindow({ url: "https://y.com/" });
  S().moveTabsToWindow([e], other);
  assert.deepEqual(pinned(other), ["a", "F", "b"]);
});

test("moving a row up or down with the keyboard passes the folders, which keep their place", () => {
  const { w, ids: [a, b], folder } = rowsAndFolder();
  S().moveGroup(folder, { pinned: true, beforeId: b });
  S().moveTab(a, 1);
  assert.deepEqual(pinned(w), ["b", "F", "a"]);
  S().hydrate(JSON.parse(JSON.stringify({ ...S(), live: undefined })));
  assert.deepEqual(pinned(w), ["b", "F", "a"], "the window's order and the folder's place agree");
});

test("unpinning or closing the row a folder sits above keeps the folder in place", () => {
  const { w, ids: [a, b, , , e], folder } = rowsAndFolder();
  S().pinTabs([e], true, true);
  S().moveGroup(folder, { pinned: true, beforeId: b });
  assert.deepEqual(pinned(w), ["a", "F", "b", "e"]);
  S().pinTabs([b], false);
  assert.deepEqual(pinned(w), ["a", "F", "e"]);
  S().moveGroup(folder, { pinned: false });
  assert.equal(S().groups[folder].beforeRow, undefined, "an unpinned folder forgets its place among the rows");
  S().moveGroup(folder, { pinned: true });
  assert.deepEqual(pinned(w), ["a", "e", "F"], "pinned again: below the rows");
});

test("other windows mirror a folder's place among the rows", () => {
  const { w, ids: [, b], folder } = rowsAndFolder();
  const other = S().createWindow({ url: "https://x.com/" });
  assert.deepEqual(pinned(other), ["a", "b", "F"]);
  S().moveGroup(folder, { pinned: true, beforeId: b });
  assert.deepEqual(pinned(other), ["a", "F", "b"]);
  S().moveGroup(folderIn(other, "F"), { pinned: true, beforeId: rowIn(other, "a") });
  assert.deepEqual(pinned(w), ["F", "a", "b"]);
});

test("a folder's place among the rows survives a relaunch and parking with the last window", () => {
  stub.docs.clear();
  reset();
  const stop = startPersistence();
  const { w, ids: [a, b, c, d] } = windowWith("a", "b", "c", "d", "e");
  S().pinTabs([a, b], true, true);
  const folder = S().groupTabs([c, d], { pinned: true, name: "F" });
  S().moveGroup(folder, { pinned: true, beforeId: b });
  flushPersistence();
  stop();
  S().hydrate(loadSession());
  assert.deepEqual(pinned(w), ["a", "F", "b"]);
  S().closeWindow(w);
  const n = S().createWindow();
  assert.deepEqual(pinned(n), ["a", "F", "b"]);
});
