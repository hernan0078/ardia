import { create } from "zustand";
import { useBrowser } from "../store/browser";
import { downloadsIn } from "../store/ui";

export const PEEK_DELAY_MS = 300;
export const PEEK_GRACE_MS = 200;
export const PEEK_DRAG_HOLD_MS = 60_000;

export type PeekSpot = "button" | "peek";

type DownloadsPeek = { windowId: string | null; heldIn: string | null };

export const useDownloadsPeek = create<DownloadsPeek>()(() => ({ windowId: null, heldIn: null }));

let pointer: { windowId: string; spot: PeekSpot } | null = null;
let showTimer: ReturnType<typeof setTimeout> | undefined;
let hideTimer: ReturnType<typeof setTimeout> | undefined;
let holdTimer: ReturnType<typeof setTimeout> | undefined;

const pointerOn = (windowId: string, spot?: PeekSpot) => pointer?.windowId === windowId && (spot === undefined || pointer.spot === spot);

export function canPeekDownloads(windowId: string) {
  const s = useBrowser.getState();
  return !!s.windows[windowId] && s.settings.peekRecentDownloads && !s.windowUi[windowId]?.downloadsOpen && downloadsIn(s, windowId).length > 0;
}

function hideAfterGrace(windowId: string) {
  clearTimeout(hideTimer);
  hideTimer = setTimeout(() => !pointerOn(windowId) && dismissDownloadsPeek(windowId), PEEK_GRACE_MS);
}

export function enterDownloadsPeek(windowId: string, spot: PeekSpot) {
  pointer = { windowId, spot };
  releaseDownloadsPeek();
  const shown = useDownloadsPeek.getState().windowId;
  if (shown === windowId) return clearTimeout(hideTimer);
  if (shown !== null) hideAfterGrace(shown);
  if (spot !== "button") return;
  clearTimeout(showTimer);
  showTimer = setTimeout(() => {
    if (pointerOn(windowId, "button") && canPeekDownloads(windowId)) useDownloadsPeek.setState({ windowId });
  }, PEEK_DELAY_MS);
}

export function leaveDownloadsPeek(windowId: string, spot: PeekSpot) {
  if (!pointerOn(windowId, spot)) return;
  pointer = null;
  clearTimeout(showTimer);
  if (useDownloadsPeek.getState().windowId === windowId) hideAfterGrace(windowId);
}

export function dismissDownloadsPeek(windowId?: string) {
  const shown = useDownloadsPeek.getState().windowId;
  if (windowId === undefined || pointer?.windowId === windowId) clearTimeout(showTimer);
  if (shown === null || (windowId !== undefined && shown !== windowId)) return;
  clearTimeout(hideTimer);
  useDownloadsPeek.setState({ windowId: null });
}

export function holdDownloadsPeek(windowId: string) {
  clearTimeout(holdTimer);
  if (useDownloadsPeek.getState().heldIn !== windowId) useDownloadsPeek.setState({ heldIn: windowId });
  holdTimer = setTimeout(releaseDownloadsPeek, PEEK_DRAG_HOLD_MS);
}

export function releaseDownloadsPeek() {
  clearTimeout(holdTimer);
  if (useDownloadsPeek.getState().heldIn !== null) useDownloadsPeek.setState({ heldIn: null });
}
