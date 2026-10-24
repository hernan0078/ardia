import assert from "node:assert/strict";
import { test } from "node:test";
const { useBrowser } = await import("../store/browser.ts");
const { downloadDay, downloadGroups, downloadKind, downloadSource, downloadsProgress, downloadsShownInSidebar, downloadSubtitle, recentDownloadsIn, stampDownload, timeAgo } = await import("../store/ui.ts");
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

test("downloads are stamped when they start and when they finish, never when first seen already finished", () => {
  const live = download("x", { state: "downloading", received: 1 });
  const started = stampDownload(undefined, live, 1000);
  assert.equal(started.startedAt, 1000);
  assert.equal(started.finishedAt, undefined);
  const finished = stampDownload(started, download("x"), 5000);
  assert.deepEqual([finished.startedAt, finished.finishedAt], [1000, 5000]);
  assert.equal(stampDownload(finished, download("x"), 9000).finishedAt, 5000, "a later update keeps the finish time");
  const restored = stampDownload(undefined, download("old"), 9000);
  assert.deepEqual([restored.startedAt, restored.finishedAt], [undefined, undefined], "a download from before has no time to show");
  S().hydrate({ profiles: { default: PERSONAL }, profileOrder: ["default"] });
  S().upsertDownload(live);
  S().upsertDownload(download("x"));
  assert.ok(S().downloads[0].finishedAt >= S().downloads[0].startedAt, "the store stamps them");
});

test("time ago reads like Arc's", () => {
  assert.equal(timeAgo(0, 400), "1 second ago");
  assert.equal(timeAgo(0, 38_000), "38 seconds ago");
  assert.equal(timeAgo(0, 61_000), "1 minute ago");
  assert.equal(timeAgo(0, 3 * 60_000 + 5_000), "3 minutes ago");
  assert.equal(timeAgo(0, 2 * 3_600_000), "2 hours ago");
  assert.equal(timeAgo(0, 86_400_000), "1 day ago");
});

test("a download that finishes puts its thumbnail on the button until the button is hovered or clicked", () => {
  peek.clearFreshDownload();
  peek.noteFinishedDownloads([download("old")], [download("old")]);
  assert.equal(peek.useFreshDownload.getState().id, null, "nothing new finished");
  peek.noteFinishedDownloads([], [download("restored")]);
  assert.equal(peek.useFreshDownload.getState().id, null, "first seen already finished: not fresh");
  peek.noteFinishedDownloads([download("new", { state: "downloading" })], [download("new")]);
  assert.equal(peek.useFreshDownload.getState().id, "new");
  peek.enterDownloadsPeek("w", "button");
  assert.equal(peek.useFreshDownload.getState().id, null);
  peek.leaveDownloadsPeek("w", "button");
  peek.dismissDownloadsPeek();
});

test("the sidebar library groups by day like Arc and labels each file by kind and site", () => {
  const now = new Date(2026, 9, 24, 9, 30).getTime();
  const day = (n, hour = 12) => new Date(2026, 9, 24 - n, hour).getTime();
  assert.equal(downloadDay(day(0, 1), now), "Today");
  assert.equal(downloadDay(day(1, 23), now), "Yesterday");
  assert.equal(downloadDay(day(3), now), "3 days ago");
  assert.equal(downloadDay(undefined, now), "Earlier");

  assert.equal(downloadKind({ mimeType: "image/jpeg", filename: "a.jpg" }), "Image");
  assert.equal(downloadKind({ mimeType: "", filename: "plan.PDF" }), "PDF");
  assert.equal(downloadKind({ mimeType: "application/zip", filename: "bipbop.zip" }), "Zip Archive");
  assert.equal(downloadKind({ mimeType: "application/vnd.openxmlformats", filename: "quiz.docx" }), "Download");
  assert.equal(downloadSource("https://upload.wikimedia.org/x.jpg"), "wikimedia.org");
  assert.equal(downloadSource("https://www.fpl.com/bill.pdf"), "fpl.com");
  assert.equal(downloadSource("https://release-assets.githubusercontent.com/a.zip"), "release-assets.githubusercontent.com");
  assert.equal(downloadSource("blob:https://chatgpt.com/123"), "");
  assert.equal(downloadSubtitle({ mimeType: "image/jpeg", filename: "a.jpg", url: "https://upload.wikimedia.org/a.jpg" }), "Image from wikimedia.org");
  assert.equal(downloadSubtitle({ mimeType: "application/pdf", filename: "a.pdf", url: "data:application/pdf;base64,AA" }), "PDF");

  const list = [
    { ...download("photo.jpg", { url: "https://upload.wikimedia.org/photo.jpg" }), finishedAt: day(0) },
    { ...download("quiz.docx", { url: "https://chatgpt.com/f" }), finishedAt: day(2) },
    { ...download("old.zip") },
  ];
  assert.deepEqual(downloadGroups(list, "", now), [
    { day: "Today", ids: ["photo.jpg"] },
    { day: "2 days ago", ids: ["quiz.docx"] },
    { day: "Earlier", ids: ["old.zip"] },
  ]);
  assert.deepEqual(downloadGroups(list, "  QUIZ ", now), [{ day: "2 days ago", ids: ["quiz.docx"] }], "search matches names");
  assert.deepEqual(downloadGroups(list, "wikimedia", now), [{ day: "Today", ids: ["photo.jpg"] }], "and sites");
});

test("with downloads in the sidebar, the button opens the library and a new download doesn't open anything", () => {
  const w = windowWithDownloads();
  assert.equal(downloadsShownInSidebar(S(), w), false, "off by default: the popover, as in Dia");
  S().updateSettings({ downloadsInSidebar: true });
  assert.equal(downloadsShownInSidebar(S(), w), true);
  S().upsertDownload(download("fresh", { state: "downloading" }));
  assert.equal(S().windowUi[w]?.downloadsOpen ?? false, false, "no full-height view pops up on its own");
  S().updateSettings({ tabLayout: "top" });
  assert.equal(downloadsShownInSidebar(S(), w), false, "tabs on top keep the popover");
  S().updateSettings({ tabLayout: "sidebar", downloadsInSidebar: false });
  S().upsertDownload(download("another", { state: "downloading" }));
  assert.equal(S().windowUi[w].downloadsOpen, true, "the popover still opens on a new download, as before");
});
