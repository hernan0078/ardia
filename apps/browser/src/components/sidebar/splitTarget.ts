import type { BrowserState } from "../../store/browser";
import { MAX_SPLIT_PANES, splitOf, type SplitSide } from "../../store/splits";

export const SPLIT_DROP_WIDTH = 72;
export const SPLIT_DROP_FRACTION = 0.4;

export function splitDropSide(s: Pick<BrowserState, "tabs" | "splits">, sourceId: string | null, targetId: string): SplitSide | null {
  const source = sourceId ? s.tabs[sourceId] : undefined;
  const target = s.tabs[targetId];
  if (!source || !target || source.id === target.id || source.windowId !== target.windowId || source.profileId !== target.profileId) return null;
  const split = splitOf(s, targetId);
  if (split && (split.tabIds.includes(source.id) || split.tabIds.length >= MAX_SPLIT_PANES)) return null;
  return split?.orientation === "vertical" ? "bottom" : "right";
}

export function overSplitTarget(frame: { x: number; y: number; w: number; h: number }, x: number, y: number): boolean {
  const width = Math.min(SPLIT_DROP_WIDTH, frame.w * SPLIT_DROP_FRACTION);
  return x >= frame.x + frame.w - width && x <= frame.x + frame.w && y > frame.y + frame.h * 0.25 && y < frame.y + frame.h * 0.75;
}
