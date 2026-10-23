import type { SplitSide } from "../../store/splits";
import type { Rect } from "./geometry";

const STAGES = {
  rest: { width: 0.1324, height: 0.383, inset: 0.025 },
  grown: { width: 0.215, height: 0.611, inset: 0.02 },
  active: { width: 0.241, height: 0.69, inset: 0.02 },
} as const;
export type ZoneStage = keyof typeof STAGES;
const LEAN = 0.43;
const TARGET_HYSTERESIS = 0.04;

export const PREVIEW = { width: 209, height: 110 };
export const SPLIT_SIDES = ["left", "right", "top", "bottom"] as const;

export function zoneRect(pane: Rect, side: SplitSide, stage: ZoneStage, pointerX = 0, pointerY = 0): Rect {
  const s = STAGES[stage];
  const horizontal = side === "left" || side === "right";
  const before = side === "left" || side === "top";
  const width = pane.width * (horizontal ? s.width : s.height);
  const height = pane.height * (horizontal ? s.height : s.width);
  const inset = (horizontal ? pane.width : pane.height) * s.inset;
  const x = horizontal ? (before ? pane.x + inset : pane.x + pane.width - inset - width) : pane.x + (pane.width - width) / 2;
  const y = horizontal ? pane.y + (pane.height - height) / 2 : before ? pane.y + inset : pane.y + pane.height - inset - height;
  if (stage !== "active") return { x, y, width, height };
  const home = zoneRect(pane, side, "grown");
  const centre = horizontal ? home.x + home.width / 2 : home.y + home.height / 2;
  const lean = centre + ((horizontal ? pointerX : pointerY) - centre) * LEAN;
  const start = horizontal ? pane.x : pane.y;
  const length = horizontal ? pane.width : pane.height;
  const size = horizontal ? width : height;
  const at = Math.max(start + inset, Math.min(start + length - inset - size, lean - size / 2));
  return { x: horizontal ? at : x, y: horizontal ? y : at, width, height };
}

const overlaps = (a: Rect, b: Rect) => a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;

export function zoneHit(panes: [string, Rect][], px: number, py: number, current: { tabId: string; side: SplitSide } | null) {
  const card = { x: px - PREVIEW.width / 2, y: py - PREVIEW.height / 2, width: PREVIEW.width, height: PREVIEW.height };
  let best: { tabId: string; side: SplitSide; distance: number } | null = null;
  for (const [tabId, pane] of panes) {
    for (const side of SPLIT_SIDES) {
      const keep = current?.tabId === tabId && current.side === side;
      const r = zoneRect(pane, side, keep ? "active" : "grown", px, py);
      if (!overlaps(card, r)) continue;
      const home = keep ? zoneRect(pane, side, "grown") : r;
      const distance = Math.hypot((home.x + home.width / 2 - px) / pane.width, (home.y + home.height / 2 - py) / pane.height) - (keep ? TARGET_HYSTERESIS : 0);
      if (!best || distance < best.distance) best = { tabId, side, distance };
    }
  }
  return best && { tabId: best.tabId, side: best.side };
}
