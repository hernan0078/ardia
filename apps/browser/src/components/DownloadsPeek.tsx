import { fileExists } from "@ardia/shell";
import { useEffect, useRef, useState } from "react";
import { Animated, Easing, View } from "react-native";
import { useShallow } from "zustand/react/shallow";
import { useTheme } from "../lib/theme";
import { useBrowser } from "../store/browser";
import { useWindowId, useWindowUi } from "../store/hooks";
import { downloadsIn, downloadsProgress, downloadVisibleIn, recentDownloadsIn } from "../store/ui";
import { DownloadRowItem, FileThumbnail, progressTrack } from "./Downloads";
import {
  clearFreshDownload,
  dismissDownloadsPeek,
  enterDownloadsPeek,
  holdDownloadsPeek,
  leaveDownloadsPeek,
  releaseDownloadsPeek,
  useDownloadsPeek,
  useFreshDownload,
} from "./downloadsHover";
import { usePopoverPresence } from "./layout/controls";
import { useAddressBarInSidebar, useTabLayout } from "./layout/windowLayout";
import { PROFILE_DOTS_HEIGHT } from "./profiles/ProfileDots";
import { IconButton } from "./primitives";
import { dismissHover, setRowsCovered } from "./sidebar/hover";
import { useSidebarWidth } from "./sidebar/tokens";

const BOX = 34;
const RING = 17;
const RING_STROKE = 2;
const FRESH = 28;

export function SidebarDownloadsButton({ windowId }: { windowId: string }) {
  const theme = useTheme();
  const progress = useBrowser(useShallow((s) => downloadsProgress(downloadsIn(s, windowId))));
  const peeks = useBrowser((s) => s.settings.peekRecentDownloads && downloadsIn(s, windowId).length > 0);
  const freshId = useFreshDownload((f) => f.id);
  const fresh = useBrowser((s) => {
    const d = freshId ? s.downloads.find((x) => x.id === freshId) : undefined;
    return d && d.state === "finished" && downloadVisibleIn(d, s.windows[windowId]) ? d.path : null;
  });
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
          clearFreshDownload();
          dismissDownloadsPeek(windowId);
          const s = useBrowser.getState();
          s.setDownloadsOpen(windowId, !s.windowUi[windowId]?.downloadsOpen);
        }}
      />
      {progress ? (
        <View pointerEvents="none" style={{ position: "absolute", left: (BOX - RING) / 2, top: (BOX - RING) / 2 }}>
          <ProgressRing fraction={Math.max(progress.fraction, 0.03)} color={progress.paused ? theme.textTertiary : theme.accent} track={progressTrack(theme.dark)} />
        </View>
      ) : fresh && fileExists(fresh) ? (
        <View pointerEvents="none" style={{ position: "absolute", left: (BOX - FRESH) / 2, top: (BOX - FRESH) / 2 }}>
          <FileThumbnail path={fresh} size={FRESH} radius={6} />
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

const PEEK_GAP = 8;
const PEEK_FADE = [0.25, 0.5, 0.75];
const PEEK_FADE_BAND = 4;
const PEEK_RISE = 8;

function PeekPanel({ windowId, closing, held, onClosed }: { windowId: string; closing: boolean; held: boolean; onClosed: () => void }) {
  const theme = useTheme();
  const footer = useAddressBarInSidebar();
  const width = useSidebarWidth(windowId);
  const liveIds = useBrowser(useShallow((s) => recentDownloadsIn(s, windowId).map((d) => d.id)));
  const shownIds = useRef(liveIds);
  if (!closing && !held) shownIds.current = liveIds;
  const ids = footer ? [...shownIds.current].reverse() : shownIds.current;
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    if (closing) return;
    setNow(Date.now());
    const tick = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(tick);
  }, [closing]);
  const appear = useRef(new Animated.Value(0)).current;
  const closed = useRef(onClosed);
  closed.current = onClosed;
  useEffect(() => {
    Animated.timing(appear, { toValue: closing ? 0 : 1, duration: closing ? 100 : 150, easing: Easing.out(Easing.quad), useNativeDriver: true }).start(
      ({ finished }) => finished && closing && closed.current(),
    );
  }, [closing]);
  const [press] = useState(() => ({
    onHold: () => holdDownloadsPeek(windowId),
    onRelease: releaseDownloadsPeek,
    onOpened: () => dismissDownloadsPeek(windowId),
  }));
  const [hover] = useState(() => ({
    onMouseEnter: () => enterDownloadsPeek(windowId, "peek"),
    onMouseLeave: () => leaveDownloadsPeek(windowId, "peek"),
  }));
  const tint = theme.windowTint[footer ? 1 : 0];
  const fade = PEEK_FADE.map((opacity) => <View key={opacity} style={{ height: PEEK_FADE_BAND, backgroundColor: tint, opacity }} />);
  return (
    <Animated.View
      {...(closing ? null : hover)}
      pointerEvents={closing ? "none" : "auto"}
      style={{
        position: "absolute",
        left: 0,
        width,
        ...(footer ? { bottom: PROFILE_DOTS_HEIGHT + 4 } : { top: 44 }),
        opacity: appear,
        transform: [{ translateY: appear.interpolate({ inputRange: [0, 1], outputRange: [footer ? PEEK_RISE : -PEEK_RISE, 0] }) }],
      }}
    >
      <View pointerEvents="none" style={{ position: "absolute", left: 0, right: 0, top: footer ? -PEEK_FADE_BAND * PEEK_FADE.length : 0, bottom: footer ? 0 : -PEEK_FADE_BAND * PEEK_FADE.length }}>
        {footer ? fade : null}
        <View style={{ flex: 1, backgroundColor: tint }} />
        {footer ? null : [...fade].reverse()}
      </View>
      <View style={{ gap: PEEK_GAP, paddingVertical: 4 }}>
        {ids.map((id) => (
          <DownloadRowItem key={id} id={id} windowId={windowId} variant="peek" now={now} {...press} />
        ))}
      </View>
    </Animated.View>
  );
}
