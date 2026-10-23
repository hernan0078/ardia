import assert from "node:assert/strict";
import { test } from "node:test";
const { SPLIT_SIDES, zoneHit, zoneRect } = await import("./splitDrop.ts");

const pane = { x: 220, y: 44, width: 960, height: 700 };
const centre = (rect) => [rect.x + rect.width / 2, rect.y + rect.height / 2];

test("dragging to any page edge selects that split direction", () => {
  for (const side of SPLIT_SIDES) {
    const [x, y] = centre(zoneRect(pane, side, "grown"));
    assert.deepEqual(zoneHit([["a", pane]], x, y, null), { tabId: "a", side });
  }
  assert.equal(zoneHit([["a", pane]], ...centre(pane), null), null);
  assert.equal(zoneHit([["a", pane]], -1000, -1000, null), null);
});

test("a third pane can target either existing page, including its top and bottom", () => {
  const panes = [["a", { ...pane, width: 475 }], ["b", { ...pane, x: 705, width: 475 }]];
  for (const [tabId, rect] of panes) {
    for (const side of SPLIT_SIDES) {
      assert.deepEqual(zoneHit(panes, ...centre(zoneRect(rect, side, "grown")), null), { tabId, side });
    }
  }
});

test("one continuous drag can move between every pair of split targets", () => {
  const layouts = [[["a", pane]], [["a", { ...pane, width: 475 }], ["b", { ...pane, x: 705, width: 475 }]]];
  for (const panes of layouts) {
    const targets = panes.flatMap(([tabId, rect]) => SPLIT_SIDES.map((side) => ({ tabId, side, point: centre(zoneRect(rect, side, "grown")) })));
    for (const source of targets) {
      for (const target of targets) {
        let current = zoneHit(panes, ...source.point, null);
        for (let step = 1; step <= 20; step++) {
          const point = source.point.map((start, axis) => start + (target.point[axis] - start) * step / 20);
          current = zoneHit(panes, ...point, current);
        }
        assert.deepEqual(current, { tabId: target.tabId, side: target.side }, `${source.tabId}:${source.side} to ${target.tabId}:${target.side}`);
      }
    }
  }
});

test("near a shared target boundary a small pointer movement keeps the current target", () => {
  for (const side of ["left", "top"]) {
    const current = { tabId: "a", side };
    for (const delta of [-1, 0, 1]) assert.deepEqual(zoneHit([["a", pane]], 520 + delta, 262 + delta, current), current);
  }
});

test("active split previews lean toward the pointer while staying inside the page", () => {
  for (const side of SPLIT_SIDES) {
    for (const [x, y] of [[-1000, -1000], [3000, 3000]]) {
      const rect = zoneRect(pane, side, "active", x, y);
      assert.ok(rect.x >= pane.x && rect.y >= pane.y);
      assert.ok(rect.x + rect.width <= pane.x + pane.width);
      assert.ok(rect.y + rect.height <= pane.y + pane.height);
    }
  }
});
