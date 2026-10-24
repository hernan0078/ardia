import assert from "node:assert/strict";
import { test } from "node:test";
const { useBrowser } = await import("../store/browser.ts");
const { downloadsProgress, recentDownloadsIn } = await import("../store/ui.ts");
const peek = await import("./downloadsHover.ts");

const S = () => useBrowser.getState();
const PERSONAL = { id: "default", name: "Personal", color: "plum", icon: null, createdAt: 0 };
const download = (id, patch = {}) => ({
  id, url: `https://dl.example/${id}`, filename: id, path: `/tmp/${id}`, state: "finished", paused: false, received: 10, total: 10,
  speed: 0, mimeType: "", profile: "", ...patch,
});

function windowWithDownloads(...ids) {
  S().hydrate({ profiles: { default: PERSONAL }, profileOrder: ["default"] });
  const w = S().createWindow({ url: "https://a.example/" });
  for (const id of ids) S().upsertDownload(download(id));
  S().setDownloadsOpen(w, false);
  return w;
}

const shown = () => peek.useDownloadsPeek.getState().windowId;
const held = () => peek.useDownloadsPeek.getState().heldIn;

test("the peek lists the window's 3 newest downloads, newest first", () => {
  const w = windowWithDownloads("a", "b", "c", "d");
  const work = S().createProfile({ name: "Work" });
  S().upsertDownload(download("theirs", { profile: work }));
  assert.deepEqual(recentDownloadsIn(S(), w).map((d) => d.id), ["d", "c", "b"]);
  assert.deepEqual(recentDownloadsIn(S(), w, 10).map((d) => d.id), ["d", "c", "b", "a"], "another profile's download stays out");
});

test("the button's progress sums the active downloads and ignores finished ones", () => {
  assert.equal(downloadsProgress([download("done")]), null);
  assert.deepEqual(
    downloadsProgress([download("a", { state: "downloading", received: 25, total: 100 }), download("b", { state: "downloading", received: 75, total: 100 }), download("c")]),
    { fraction: 0.5, paused: false },
  );
  assert.deepEqual(downloadsProgress([download("u", { state: "downloading", received: 5, total: -1 })]), { fraction: 0, paused: false }, "an unknown size counts as no progress");
  assert.equal(downloadsProgress([download("p", { state: "downloading", paused: true, received: 1, total: 4 })]).paused, true);
  assert.equal(
    downloadsProgress([download("p", { state: "downloading", paused: true, received: 1, total: 4 }), download("q", { state: "downloading", received: 1, total: 4 })]).paused,
    false,
    "paused only when every active download is",
  );
});

test("hovering the button peeks after the delay; leaving both closes after the grace period", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const w = windowWithDownloads("a");
  peek.dismissDownloadsPeek();
  peek.enterDownloadsPeek(w, "button");
  t.mock.timers.tick(peek.PEEK_DELAY_MS - 1);
  assert.equal(shown(), null, "not before the hover-intent delay");
  t.mock.timers.tick(1);
  assert.equal(shown(), w);

  peek.leaveDownloadsPeek(w, "button");
  t.mock.timers.tick(peek.PEEK_GRACE_MS - 1);
  peek.enterDownloadsPeek(w, "peek");
  t.mock.timers.tick(peek.PEEK_GRACE_MS * 2);
  assert.equal(shown(), w, "moving from the button into the peek keeps it");

  peek.enterDownloadsPeek(w, "button");
  peek.leaveDownloadsPeek(w, "peek");
  t.mock.timers.tick(peek.PEEK_GRACE_MS * 2);
  assert.equal(shown(), w, "a late leave from the peek after entering the button changes nothing");

  peek.leaveDownloadsPeek(w, "button");
  t.mock.timers.tick(peek.PEEK_GRACE_MS);
  assert.equal(shown(), null);
});

test("moving from one window's peek to another window's button still closes the first", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  S().hydrate({ profiles: { default: PERSONAL }, profileOrder: ["default"] });
  const first = S().createWindow({ url: "https://a.example/" });
  const second = S().createWindow({ url: "https://b.example/" });
  S().upsertDownload(download("a"));
  for (const w of [first, second]) S().setDownloadsOpen(w, false);
  peek.dismissDownloadsPeek();
  peek.enterDownloadsPeek(first, "button");
  t.mock.timers.tick(peek.PEEK_DELAY_MS);
  assert.equal(shown(), first);
  peek.leaveDownloadsPeek(first, "button");
  peek.enterDownloadsPeek(second, "button");
  t.mock.timers.tick(peek.PEEK_GRACE_MS);
  assert.notEqual(shown(), first, "the first window's peek closes after the grace period");
  peek.leaveDownloadsPeek(second, "button");
  peek.dismissDownloadsPeek();
});

test("a quick pass over the button, a click, an open list or the setting off never peeks", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const w = windowWithDownloads("a");
  peek.dismissDownloadsPeek();
  peek.enterDownloadsPeek(w, "button");
  peek.leaveDownloadsPeek(w, "button");
  t.mock.timers.tick(peek.PEEK_DELAY_MS * 2);
  assert.equal(shown(), null, "passing over");

  peek.enterDownloadsPeek(w, "button");
  peek.dismissDownloadsPeek(w);
  t.mock.timers.tick(peek.PEEK_DELAY_MS * 2);
  assert.equal(shown(), null, "clicked before the delay");

  S().setDownloadsOpen(w, true);
  peek.enterDownloadsPeek(w, "button");
  t.mock.timers.tick(peek.PEEK_DELAY_MS);
  assert.equal(shown(), null, "the full list is open");
  S().setDownloadsOpen(w, false);

  S().updateSettings({ peekRecentDownloads: false });
  peek.leaveDownloadsPeek(w, "button");
  peek.enterDownloadsPeek(w, "button");
  t.mock.timers.tick(peek.PEEK_DELAY_MS);
  assert.equal(shown(), null, "the setting is off");
  S().updateSettings({ peekRecentDownloads: true });

  S().clearDownloads(w);
  peek.leaveDownloadsPeek(w, "button");
  peek.enterDownloadsPeek(w, "button");
  t.mock.timers.tick(peek.PEEK_DELAY_MS);
  assert.equal(shown(), null, "nothing to show");
});

test("a press on a row holds the peek until it's released, the pointer comes back, or the ceiling passes", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const w = windowWithDownloads("a");
  peek.holdDownloadsPeek(w);
  assert.equal(held(), w);
  peek.releaseDownloadsPeek();
  assert.equal(held(), null);

  peek.holdDownloadsPeek(w);
  peek.leaveDownloadsPeek(w, "peek");
  assert.equal(held(), w, "a leave can come mid-drag, so it doesn't release");
  peek.enterDownloadsPeek(w, "button");
  assert.equal(held(), null, "an enter only comes once the mouse is up");

  peek.holdDownloadsPeek(w);
  t.mock.timers.tick(peek.PEEK_DRAG_HOLD_MS);
  assert.equal(held(), null);
  peek.leaveDownloadsPeek(w, "button");
});
