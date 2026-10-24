import { useMemo } from "react";
import { layout, useTheme } from "../../lib/theme";
import { useBrowser, type BrowserState } from "../../store/browser";
import type { Settings } from "../../store/settings";
import { useSidebarTokens } from "./tokens";

export type RowMetrics = { rowHeight: number; rowGap: number; pitch: number; titleSize: number; titleHeight: number; splitTitleSize: number; splitTitleHeight: number };
export type RowText = { tabTitle: string; groupTitle: string; newTabLabel: string };
export type SidebarRows = RowMetrics & RowText;

const metrics = (rowHeight: number, rowGap: number, titleSize: number, titleHeight: number, splitTitleSize: number, splitTitleHeight: number): RowMetrics => ({
  rowHeight,
  rowGap,
  pitch: rowHeight + rowGap,
  titleSize,
  titleHeight,
  splitTitleSize,
  splitTitleHeight,
});

export const ARDIA_ROWS = metrics(layout.rowHeight, layout.rowGap, 13, 18, 12, 16);
export const ARC_ROWS = metrics(36, 5, 14, 19, 13, 17);

export const ARC_TEXT: Record<"dark" | "light", Omit<RowText, "groupTitle">> = {
  dark: { tabTitle: "#FFFFFFD4", newTabLabel: "#FFFFFF95" },
  light: { tabTitle: "#000000D4", newTabLabel: "#0000009D" },
};

export const rowMetricsFor = (settings: Partial<Pick<Settings, "arcSidebarText">>): RowMetrics => (settings.arcSidebarText ? ARC_ROWS : ARDIA_ROWS);

export const rowMetrics = (s: BrowserState): RowMetrics => rowMetricsFor(s.settings);

export function useSidebarRowMetrics(): SidebarRows {
  const theme = useTheme();
  const tokens = useSidebarTokens();
  const arc = useBrowser((s) => !!s.settings.arcSidebarText);
  return useMemo(
    () =>
      arc
        ? { ...ARC_ROWS, ...ARC_TEXT[theme.dark ? "dark" : "light"], groupTitle: tokens.groupTitle }
        : { ...ARDIA_ROWS, tabTitle: theme.textTab, groupTitle: tokens.groupTitle, newTabLabel: tokens.newTabLabel },
    [arc, theme.dark, theme.textTab, tokens],
  );
}
