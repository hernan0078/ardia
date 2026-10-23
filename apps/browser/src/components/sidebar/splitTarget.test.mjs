import assert from "node:assert/strict";
import { test } from "node:test";
const { overSplitTarget, splitDropSide } = await import("./splitTarget.ts");

const tab = (id, windowId = "w", profileId = "default") => ({ id, windowId, profileId });
const state = () => ({ tabs: { a: tab("a"), b: tab("b"), c: tab("c"), d: tab("d"), otherWindow: tab("otherWindow", "other"), otherProfile: tab("otherProfile", "w", "other") }, splits: {} });

test("split drops occupy only the right middle of a row, leaving its centre and edges to existing gestures", () => {
  const frame = { x: 20, y: 100, w: 200, h: 40 };
  assert.equal(overSplitTarget(frame, 200, 120), true);
  for (const [x, y] of [[140, 120], [225, 120], [200, 105], [200, 135]]) assert.equal(overSplitTarget(frame, x, y), false);
  assert.equal(overSplitTarget({ ...frame, w: 100 }, 80, 120), true);
  assert.equal(overSplitTarget({ ...frame, w: 100 }, 75, 120), false);
});

test("only another tab of the same window and profile offers a split target", () => {
  const s = state();
  assert.equal(splitDropSide(s, "a", "b"), "right");
  for (const source of [null, "gone", "b", "otherWindow", "otherProfile"]) assert.equal(splitDropSide(s, source, "b"), null);
  assert.equal(splitDropSide(s, "a", "gone"), null);
});

test("a split accepts a third tab along its existing direction, but never a fourth or its own member", () => {
  const s = state();
  s.splits.split = { id: "split", tabIds: ["a", "b"], orientation: "vertical" };
  assert.equal(splitDropSide(s, "c", "b"), "bottom");
  assert.equal(splitDropSide(s, "a", "b"), null);
  s.splits.split.tabIds.push("c");
  assert.equal(splitDropSide(s, "d", "b"), null);
});
