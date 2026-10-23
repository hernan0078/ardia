import assert from "node:assert/strict";
import { test } from "node:test";
const { useBrowser } = await import("../../store/browser.ts");
const { DEFAULT_SETTINGS } = await import("../../store/settings.ts");
const { layout, themeFor } = await import("../../lib/theme.ts");
const { ARC_ROWS, ARC_TEXT, ARDIA_ROWS, rowMetrics, rowMetricsFor } = await import("./rowMetrics.ts");
await import("../../test-native-stub.mjs");

const alpha = (hex) => parseInt(hex.slice(7, 9), 16) / 255;

test("off by default: the sidebar keeps Ardia's 34 pt rows, 3 pt gaps and 13 pt titles", () => {
  assert.equal(DEFAULT_SETTINGS.arcSidebarText, false);
  assert.equal(rowMetricsFor(DEFAULT_SETTINGS), ARDIA_ROWS);
  assert.equal(rowMetricsFor({}), ARDIA_ROWS);
  assert.equal(ARDIA_ROWS.rowHeight, layout.rowHeight);
  assert.equal(ARDIA_ROWS.rowGap, layout.rowGap);
  assert.equal(ARDIA_ROWS.pitch, 37);
  assert.equal(ARDIA_ROWS.titleSize, 13);
});

test("on: Arc's 41 pt row pitch and 14 pt titles, read from the store", () => {
  useBrowser.getState().updateSettings({ arcSidebarText: true });
  assert.equal(rowMetrics(useBrowser.getState()), ARC_ROWS);
  assert.equal(ARC_ROWS.pitch, ARC_ROWS.rowHeight + ARC_ROWS.rowGap);
  assert.equal(ARC_ROWS.pitch, 41);
  assert.equal(ARC_ROWS.titleSize, 14);
  useBrowser.getState().updateSettings({ arcSidebarText: false });
  assert.equal(rowMetrics(useBrowser.getState()), ARDIA_ROWS);
});

test("Arc's titles are brighter than Ardia's in both themes, and the New Tab label stays dimmer than a title", () => {
  for (const mode of ["dark", "light"]) {
    const theme = themeFor(`plum:${mode}`);
    const text = ARC_TEXT[mode];
    assert.equal(text.tabTitle.slice(0, 7), theme.textTab.slice(0, 7));
    assert.ok(alpha(text.tabTitle) > alpha(theme.textTab), mode);
    assert.ok(Math.abs(alpha(text.tabTitle) - 0.83) < 0.005, mode);
    assert.equal(text.groupTitle, text.tabTitle);
    assert.ok(alpha(text.newTabLabel) < alpha(text.tabTitle), mode);
  }
});
