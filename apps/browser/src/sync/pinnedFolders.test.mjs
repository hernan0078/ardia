import assert from "node:assert/strict";
import { test } from "node:test";
const { useBrowser } = await import("../store/browser.ts");
const { sidebarEntries } = await import("../components/sidebar/entries.ts");
const { Clock, emptyScope, syncScope } = await import("@ardia/sync");
const adapters = await import("./adapters.ts");
const stub = await import("../test-native-stub.mjs");

const S = () => useBrowser.getState();
let wall = 1_900_000_000_000;
const now = () => ++wall;

class Folder {
  files = new Map(); counter = 0;
  transport() {
    return {
      write: async (scope, payload) => { const id = `f${++this.counter}`; this.files.set(id, { scope, payload }); return id; },
      read: async (scope, known) => {
        const shown = [...this.files].filter(([, f]) => f.scope === scope);
        return { files: shown.filter(([id]) => !known.includes(id)).map(([id, f]) => ({ id, payload: f.payload })), pending: [], damaged: [], present: shown.map(([id]) => id) };
      },
      remove: async (_s, ids) => ids.forEach((id) => this.files.delete(id)),
    };
  }
}
class Mac {
  constructor(id, folder, browser) { this.id = id; this.folder = folder; this.browser = browser; this.scopes = {}; this.clock = new Clock(id, null, now); }
  with(fn) { stub.current.device = this.id; useBrowser.setState(this.browser, true); try { return fn(); } finally { this.browser = S(); } }
  async sync() {
    stub.current.device = this.id; useBrowser.setState(this.browser, true);
    try {
      await syncScope({ scope: "p:default", state: (this.scopes.default ??= emptyScope()), transport: this.folder.transport(),
        adapters: [adapters.pinnedRowsAdapter("default"), adapters.pinnedAdapter("default")], clock: this.clock, device: this.id, now: () => wall });
    } finally { this.browser = S(); }
  }
}
function freshMac(id, folder) {
  S().hydrate({});
  const mac = new Mac(id, folder, S());
  mac.with(() => S().createWindow({ url: `https://${id}-home.example/` }));
  return mac;
}
const label = () => {
  const w = Object.values(S().windows)[0].id;
  return sidebarEntries(S(), w).pinned.map((e) => (e.startsWith("g:") ? S().groups[e.slice(2)].name : new URL(S().tabs[e.slice(2)].pinnedUrl).hostname));
};

test("a folder reorder on a Mac without anchors survives a sync with a Mac that has them", async () => {
  const folder = new Folder();
  const a = freshMac("devA", folder);
  const b = freshMac("devB", folder);
  a.with(() => {
    const w = Object.values(S().windows)[0].id;
    const ids = ["ra", "rb", "m1", "m2"].map((h) => S().newTab(w, { url: `https://${h}.example/` }));
    S().pinTabs([ids[0], ids[1]], true, true);
    S().groupTabs([ids[2]], { pinned: true, name: "F" });
    S().groupTabs([ids[3]], { pinned: true, name: "G" });
  });
  for (let i = 0; i < 3; i++) for (const m of [a, b]) await m.sync();
  a.with(() => {
    const F = Object.values(S().groups).find((g) => g.name === "F");
    const rb = Object.values(S().tabs).find((t) => t.pinned && t.pinnedUrl?.includes("rb"));
    S().moveGroup(F.id, { pinned: true, beforeId: rb.id });
  });
  for (let i = 0; i < 2; i++) for (const m of [a, b]) await m.sync();
  b.with(() => {
    const F = Object.values(S().groups).find((g) => g.name === "F");
    const G = Object.values(S().groups).find((g) => g.name === "G");
    S().moveGroup(G.id, { pinned: true, beforeId: F.tabIds[0] });
  });
  for (let i = 0; i < 3; i++) for (const m of [b, a]) await m.sync();
  const bl = b.with(label);
  assert.ok(bl.indexOf("G") < bl.indexOf("F"), "B keeps G above F");
});
