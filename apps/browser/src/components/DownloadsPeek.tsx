import { useEffect, useRef, useState } from "react";
import { View } from "react-native";
import { useShallow } from "zustand/react/shallow";
import { useTheme } from "../lib/theme";
import { useBrowser } from "../store/browser";
import { useWindowId, useWindowUi } from "../store/hooks";
import { downloadsIn, downloadsProgress, recentDownloadsIn } from "../store/ui";
import { DownloadRowItem, DownloadsFrame, DownloadsHeader, progressTrack, TextButton } from "./Downloads";
import {
  dismissDownloadsPeek,
  enterDownloadsPeek,
  holdDownloadsPeek,
  leaveDownloadsPeek,
  releaseDownloadsPeek,
  useDownloadsPeek,
} from "./downloadsHover";
import { PANEL, usePopoverPresence } from "./layout/controls";
import { useTabLayout } from "./layout/windowLayout";
import { IconButton } from "./primitives";
import { dismissHover, setRowsCovered } from "./sidebar/hover";

const BOX = 34;
const RING = 17;
const RING_STROKE = 2;

export function SidebarDownloadsButton({ windowId }: { windowId: string }) {
  const theme = useTheme();
  const progress = useBrowser(useShallow((s) => downloadsProgress(downloadsIn(s, windowId))));
  const peeks = useBrowser((s) => s.settings.peekRecentDownloads && downloadsIn(s, windowId).length > 0);
  useEffect(() => () => leaveDownloadsPeek(windowId, "button"), [windowId]);
  return (
    <View onMouseEnter={() => enterDownloadsPeek(windowId, "button")} onMouseLeave={() => leaveDownloadsPeek(windowId, "button")}>
      <IconButton
        icon={progress ? "arrow.down" : "arrow.down.circle"}
        size={progress ? 9 : 16}
        weight={progress ? "bold" : "regular"}
        box={BOX}
        radius={10}
        tooltip={peeks ? undefined : "Downloads (⇧⌘J)"}
        onPress={() => {
          dismissDownloadsPeek(windowId);
          const s = useBrowser.getState();
          s.setDownloadsOpen(windowId, !s.windowUi[windowId]?.downloadsOpen);
        }}
      />
      {progress ? (
        <View pointerEvents="none" style={{ position: "absolute", left: (BOX - RING) / 2, top: (BOX - RING) / 2 }}>
          <ProgressRing fraction={Math.max(progress.fraction, 0.03)} color={progress.paused ? theme.textTertiary : theme.accent} track={progressTrack(theme.dark)} />
        </View>
      ) : null}
    </View>
  );
}

function ProgressRing({ fraction, color, track }: { fraction: number; color: string; track: string }) {
  const half = RING / 2;
  const turn = Math.min(Math.max(fraction, 0), 1) * 360;
  const ring = { position: "absolute", top: 0, width: RING, height: RING, borderRadius: half, borderWidth: RING_STROKE } as const;
  const arc = (side: "left" | "right", degrees: number) => (
    <View style={{ position: "absolute", top: 0, left: side === "left" ? 0 : half, width: half, height: RING, overflow: "hidden" }}>
      <View
        style={[
          ring,
          {
            left: side === "left" ? 0 : -half,
            borderColor: "transparent",
            borderTopColor: color,
            borderRightColor: color,
            transform: [{ rotate: `${degrees - 135}deg` }],
          },
        ]}
      />
    </View>
  );
  return (
    <View style={{ width: RING, height: RING }}>
      <View style={[ring, { left: 0, borderColor: track }]} />
      {arc("right", Math.min(turn, 180))}
      {turn > 180 ? arc("left", turn) : null}
    </View>
  );
}

export function DownloadsPeek() {
  const windowId = useWindowId();
  const sidebarLayout = useTabLayout() !== "top";
  const downloadsOpen = useWindowUi().downloadsOpen;
  const allowed = useBrowser((s) => s.settings.peekRecentDownloads && downloadsIn(s, windowId).length > 0);
  const peeking = useDownloadsPeek((p) => p.windowId === windowId);
  const held = useDownloadsPeek((p) => p.heldIn === windowId);
  const open = peeking && allowed && sidebarLayout && !downloadsOpen;
  useEffect(() => {
    if (peeking && !open) dismissDownloadsPeek(windowId);
  }, [peeking, open, windowId]);
  useEffect(() => {
    if (!open) return;
    dismissHover();
    setRowsCovered(windowId, true);
    return () => setRowsCovered(windowId, false);
  }, [open, windowId]);
  const { shown, closing, onClosed } = usePopoverPresence(open);
  return shown || held ? <PeekPanel windowId={windowId} closing={closing} held={held} onClosed={onClosed} /> : null;
}

function PeekPanel({ windowId, closing, held, onClosed }: { windowId: string; closing: boolean; held: boolean; onClosed: () => void }) {
  const liveIds = useBrowser(useShallow((s) => recentDownloadsIn(s, windowId).map((d) => d.id)));
  const shownIds = useRef(liveIds);
  if (!closing && !held) shownIds.current = liveIds;
  const [press] = useState(() => ({
    onHold: () => holdDownloadsPeek(windowId),
    onRelease: releaseDownloadsPeek,
    onOpened: () => dismissDownloadsPeek(windowId),
  }));
  const [hover] = useState(() => ({
    onMouseEnter: () => enterDownloadsPeek(windowId, "peek"),
    onMouseLeave: () => leaveDownloadsPeek(windowId, "peek"),
  }));
  return (
    <DownloadsFrame closing={closing} onClosed={onClosed} footer={false} {...(closing ? null : hover)}>
      <DownloadsHeader>
        <TextButton
          title="Show all"
          onPress={() => {
            dismissDownloadsPeek(windowId);
            useBrowser.getState().setDownloadsOpen(windowId, true);
          }}
        />
      </DownloadsHeader>
      <View style={{ paddingHorizontal: PANEL.rowInset }}>
        {shownIds.current.map((id) => (
          <DownloadRowItem key={id} id={id} windowId={windowId} {...press} />
        ))}
      </View>
    </DownloadsFrame>
  );
}
