import type { Download } from "@ardia/ardiacore";
import type { StateCreator } from "zustand";
import type { BrowserState } from "./browser";
import { engineProfile, isIncognitoProfile, privateSession } from "./model";
import { originalProfile } from "./small";
import type { FindState, NewTabTarget, WindowUi } from "./types";
import { commandBarFocus, expectFocus } from "../lib/focusClaims";

export type StoredDownload = Download & { startedAt?: number; finishedAt?: number };

export type UiSlice = {
  ui: {
    focusedWindowId: string | null;
    focusOrder: string[];
    appDark: boolean;
    lastProfileId: string | null;
  };
  windowUi: Record<string, WindowUi>;
  find: Record<string, FindState>;
  downloads: StoredDownload[];

  setFocusedWindow(id: string): void;
  setAppDark(dark: boolean): void;
  openPanel(windowId: string, initialText?: string, newTab?: NewTabTarget): void;
  closePanel(windowId: string): void;
  setDownloadsOpen(windowId: string, open: boolean): void;
  setFind(tabId: string, patch: Partial<FindState>): void;
  upsertDownload(d: Download): void;
  removeDownload(id: string): void;
  clearDownloads(windowId?: string): void;
  forgetDownloads(profile: string): void;
};

export function downloadSession(d: Pick<Download, "profile" | "offTheRecord">): string | null {
  if (d.offTheRecord) return d.profile ?? "";
  return d.profile && isIncognitoProfile(d.profile) ? privateSession(d.profile) : null;
}

export function downloadVisibleIn(d: Pick<Download, "profile" | "offTheRecord">, window: { incognito: boolean; profileId: string } | undefined): boolean {
  if (!window) return false;
  const session = downloadSession(d);
  if (window.incognito) return session !== null && session === privateSession(window.profileId);
  return session === null && (d.profile ?? "") === engineProfile(window.profileId);
}

const sessionOpen = (s: Pick<BrowserState, "windows">, session: string) =>
  Object.values(s.windows).some((w) => w.incognito && privateSession(w.profileId) === session);
const endedPrivateDownloads = new Set<string>();

export const downloadsIn = (s: Pick<BrowserState, "downloads" | "windows">, windowId: string) =>
  s.downloads.filter((d) => downloadVisibleIn(d, s.windows[windowId]));

export const RECENT_DOWNLOADS = 3;

export const recentDownloadsIn = (s: Pick<BrowserState, "downloads" | "windows">, windowId: string, count = RECENT_DOWNLOADS) =>
  downloadsIn(s, windowId).slice(0, count);

export type DownloadsProgress = { fraction: number; paused: boolean };

export function stampDownload(prev: StoredDownload | undefined, d: Download, now: number): StoredDownload {
  const startedAt = prev ? prev.startedAt : d.state === "downloading" ? now : undefined;
  const finishedAt = d.state !== "finished" ? undefined : (prev?.finishedAt ?? (prev?.state === "downloading" ? now : undefined));
  return { ...d, ...(startedAt !== undefined ? { startedAt } : {}), ...(finishedAt !== undefined ? { finishedAt } : {}) };
}

export function downloadsShownInSidebar(s: Pick<BrowserState, "settings" | "windows">, windowId: string): boolean {
  const w = s.windows[windowId];
  return !!w && s.settings.downloadsInSidebar && w.kind !== "small" && w.sidebarOpen && (w.tabLayout ?? s.settings.tabLayout) !== "top";
}

const DAY_MS = 86_400_000;
const startOfDay = (at: number) => new Date(at).setHours(0, 0, 0, 0);

export function downloadDay(at: number | undefined, now: number): string {
  if (at === undefined) return "Earlier";
  const days = Math.round((startOfDay(now) - startOfDay(at)) / DAY_MS);
  return days <= 0 ? "Today" : days === 1 ? "Yesterday" : `${days} days ago`;
}

const KINDS: [RegExp, string][] = [
  [/^image\/|\.(png|jpe?g|gif|webp|heic|avif|svg|bmp|tiff?)$/i, "Image"],
  [/^application\/pdf$|\.pdf$/i, "PDF"],
  [/zip|\.zip$/i, "Zip Archive"],
  [/^video\/|\.(mp4|mov|m4v|webm|mkv)$/i, "Video"],
  [/^audio\/|\.(mp3|m4a|wav|aac|flac)$/i, "Audio"],
];

export function downloadKind(d: Pick<Download, "mimeType" | "filename">): string {
  return KINDS.find(([pattern]) => pattern.test(d.mimeType) || pattern.test(d.filename))?.[1] ?? "Download";
}

const GENERIC_HOST_PARTS = new Set(["www", "upload", "cdn", "static", "files", "download", "downloads", "dl", "media", "images", "img"]);

export function downloadSource(url: string): string {
  const host = /^https?:\/\/([^/:?#]+)/i.exec(url)?.[1]?.toLowerCase() ?? "";
  const parts = host.split(".");
  while (parts.length > 2 && GENERIC_HOST_PARTS.has(parts[0]!)) parts.shift();
  return parts.join(".");
}

export function downloadSubtitle(d: Pick<Download, "mimeType" | "filename" | "url">): string {
  const source = downloadSource(d.url);
  return source ? `${downloadKind(d)} from ${source}` : downloadKind(d);
}

export function downloadGroups(downloads: readonly StoredDownload[], query: string, now: number): { day: string; ids: string[] }[] {
  const needle = query.trim().toLowerCase();
  const groups: { day: string; ids: string[] }[] = [];
  for (const d of downloads) {
    if (needle && !d.filename.toLowerCase().includes(needle) && !downloadSource(d.url).includes(needle)) continue;
    const day = downloadDay(d.finishedAt ?? d.startedAt, now);
    const group = groups.find((g) => g.day === day);
    if (group) group.ids.push(d.id);
    else groups.push({ day, ids: [d.id] });
  }
  return groups;
}

export function timeAgo(at: number, now: number): string {
  const seconds = Math.max(1, Math.floor((now - at) / 1000));
  const unit = (n: number, name: string) => `${n} ${name}${n === 1 ? "" : "s"} ago`;
  if (seconds < 60) return unit(seconds, "second");
  if (seconds < 3600) return unit(Math.floor(seconds / 60), "minute");
  if (seconds < 86400) return unit(Math.floor(seconds / 3600), "hour");
  return unit(Math.floor(seconds / 86400), "day");
}

export function downloadsProgress(downloads: readonly Download[]): DownloadsProgress | null {
  const active = downloads.filter((d) => d.state === "downloading");
  if (!active.length) return null;
  let received = 0;
  let total = 0;
  for (const d of active) {
    if (d.total <= 0) continue;
    received += Math.min(Math.max(d.received, 0), d.total);
    total += d.total;
  }
  return { fraction: total > 0 ? received / total : 0, paused: active.every((d) => d.paused) };
}

export const DEFAULT_WINDOW_UI: WindowUi = { panel: { open: false, initialText: "" }, downloadsOpen: false };
export const CLOSED_FIND: FindState = { open: false, query: "", count: null, active: 0 };
const MAX_DOWNLOADS = 100;

function patchWindowUi(s: BrowserState, windowId: string, patch: Partial<WindowUi>): Partial<BrowserState> {
  if (!s.windows[windowId]) return {};
  return { windowUi: { ...s.windowUi, [windowId]: { ...(s.windowUi[windowId] ?? DEFAULT_WINDOW_UI), ...patch } } };
}

export const createUiSlice: StateCreator<BrowserState, [], [], UiSlice> = (set, get) => ({
  ui: { focusedWindowId: null, focusOrder: [], appDark: true, lastProfileId: null },
  windowUi: {},
  find: {},
  downloads: [],

  setFocusedWindow(id) {
    const s = get();
    const { ui, windows } = s;
    if (!windows[id]) return;
    const lastProfileId = originalProfile(s, windows[id]) ?? ui.lastProfileId;
    if (ui.focusedWindowId === id && ui.lastProfileId === lastProfileId) return;
    set({ ui: { ...ui, focusedWindowId: id, focusOrder: [id, ...ui.focusOrder.filter((w) => w !== id)], lastProfileId } });
  },

  setAppDark(appDark) {
    if (get().ui.appDark !== appDark) set((s) => ({ ui: { ...s.ui, appDark } }));
  },

  openPanel(windowId, initialText = "", newTab) {
    expectFocus(windowId, commandBarFocus);
    set((s) => patchWindowUi(s, windowId, { panel: newTab ? { open: true, initialText, newTab } : { open: true, initialText } }));
  },

  closePanel(windowId) {
    set((s) => patchWindowUi(s, windowId, { panel: { open: false, initialText: "" } }));
  },

  setDownloadsOpen(windowId, downloadsOpen) {
    set((s) => patchWindowUi(s, windowId, { downloadsOpen }));
  },

  setFind(tabId, patch) {
    set((s) => (s.tabs[tabId] ? { find: { ...s.find, [tabId]: { ...(s.find[tabId] ?? CLOSED_FIND), ...patch } } } : {}));
  },

  upsertDownload(d) {
    set((s) => {
      const exists = s.downloads.some((x) => x.id === d.id);
      const session = downloadSession(d);
      if (!exists && session !== null && (!sessionOpen(s, session) || endedPrivateDownloads.has(d.id))) {
        endedPrivateDownloads.add(d.id);
        return {};
      }
      const stamped = stampDownload(s.downloads.find((x) => x.id === d.id), d, Date.now());
      const downloads = exists ? s.downloads.map((x) => (x.id === d.id ? stamped : x)) : [stamped, ...s.downloads].slice(0, MAX_DOWNLOADS);
      const focused = s.ui.focusedWindowId;
      const open = !exists && focused && downloadVisibleIn(d, s.windows[focused]) && !downloadsShownInSidebar(s, focused);
      return { downloads, ...(open ? patchWindowUi(s, focused, { downloadsOpen: true }) : {}) };
    });
  },

  removeDownload(id) {
    set((s) => ({ downloads: s.downloads.filter((d) => d.id !== id) }));
  },

  clearDownloads(windowId) {
    set((s) => ({
      downloads: s.downloads.filter((d) => d.state === "downloading" || (windowId !== undefined && !downloadVisibleIn(d, s.windows[windowId]))),
    }));
  },

  forgetDownloads(profile) {
    const session = privateSession(profile);
    const gone = (d: Download) => (session !== null ? downloadSession(d) === session : d.profile === profile);
    if (session !== null) for (const d of get().downloads) if (gone(d)) endedPrivateDownloads.add(d.id);
    set((s) => (s.downloads.some(gone) ? { downloads: s.downloads.filter((d) => !gone(d)) } : {}));
  },
});
