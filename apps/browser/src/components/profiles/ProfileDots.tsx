import { Symbol } from "@ardia/shell";
import { useCallback, useEffect, useRef, useState } from "react";
import { Animated, Pressable, ScrollView, View } from "react-native";
import { useShallow } from "zustand/react/shallow";
import { createProfile, switchProfile } from "../../lib/actions";
import { useTheme } from "../../lib/theme";
import { useBrowser } from "../../store/browser";
import { useIsIncognito } from "../../store/hooks";
import { usePagerPages, type PagerPage } from "../layout/profilePager";
import { useHover } from "../primitives";

export const PROFILE_DOTS_HEIGHT = 41;
const CELL = 12;
const DOT = 6;
const BAND = 28;
const SELECTED = 0.85;
const HOVERED = 0.4;
const IDLE = 0.2;

export function useProfileDotsShown() {
  const incognito = useIsIncognito();
  return !incognito;
}

export function ProfileDots({ windowId, reserveLeading = false }: { windowId: string; reserveLeading?: boolean }) {
  const ids = useBrowser(useShallow((s) => s.profileOrder));
  const current = useBrowser((s) => s.windows[windowId]?.profileId ?? "");
  const { pages, pager } = usePagerPages(windowId);
  const scroll = useRef<ScrollView>(null);
  const [available, setAvailable] = useState(0);
  const reveal = useCallback(() => {
    const index = ids.indexOf(current);
    if (!available || index < 0) return;
    const x = Math.max(0, Math.min(ids.length * CELL - available, (index + 0.5) * CELL - available / 2));
    scroll.current?.scrollTo({ x, animated: false });
  }, [ids, current, available]);
  useEffect(reveal, [reveal]);
  return (
    <View style={{ height: PROFILE_DOTS_HEIGHT, paddingLeft: reserveLeading ? 40 : 8, paddingRight: 8 }}>
      <View style={{ marginTop: (PROFILE_DOTS_HEIGHT - 3 - BAND) / 2, height: BAND, flexDirection: "row" }}>
        <ScrollView
          ref={scroll}
          horizontal
          bounces={false}
          showsHorizontalScrollIndicator={false}
          scrollEnabled={ids.length * CELL > available}
          onLayout={(e) => setAvailable(e.nativeEvent.layout.width)}
          onContentSizeChange={reveal}
          style={{ flex: 1 }}
          contentContainerStyle={{ flexGrow: 1, justifyContent: "center", alignItems: "center" }}
        >
          {ids.map((id) => (
            <Dot key={id} id={id} windowId={windowId} page={pages.find((p) => p.id === id)} pos={pager.pos} />
          ))}
        </ScrollView>
        <CreateProfileButton windowId={windowId} />
      </View>
    </View>
  );
}

function Dot({ id, windowId, page, pos }: { id: string; windowId: string; page: PagerPage | undefined; pos: Animated.Value }) {
  const theme = useTheme();
  const name = useBrowser((s) => s.profiles[id]?.name ?? "");
  const { hovered, hoverProps } = useHover();
  const rest = hovered ? HOVERED : IDLE;
  const opacity = page
    ? pos.interpolate({ inputRange: [page.slot - 1, page.slot, page.slot + 1], outputRange: [rest, SELECTED, rest], extrapolate: "clamp" })
    : rest;
  return (
    <View {...hoverProps} tooltip={name}>
      <Pressable accessibilityRole="button" accessibilityLabel={name} onPress={() => switchProfile(windowId, id, true)}>
        <View style={{ width: CELL, height: BAND, alignItems: "center", justifyContent: "center" }}>
          <Animated.View style={{ width: DOT, height: DOT, borderRadius: DOT / 2, backgroundColor: theme.dark ? "#FFFFFF" : "#000000", opacity }} />
        </View>
      </Pressable>
    </View>
  );
}

function CreateProfileButton({ windowId }: { windowId: string }) {
  const theme = useTheme();
  const { hovered, hoverProps } = useHover();
  const add = async () => {
    const id = await createProfile(windowId);
    if (id) switchProfile(windowId, id);
  };
  return (
    <View {...hoverProps} tooltip="Create Profile" style={{ marginLeft: 6 }}>
      <Pressable accessibilityRole="button" accessibilityLabel="Create Profile" onPress={() => void add()}>
        {({ pressed }) => (
          <View style={{ width: BAND, height: BAND, borderRadius: 8, alignItems: "center", justifyContent: "center", backgroundColor: pressed ? theme.tabPressed : hovered ? theme.tabHover : undefined }}>
            <Symbol name="plus" size={12} weight="semibold" color={theme.textSecondary} style={{ width: 16, height: 16 }} />
          </View>
        )}
      </Pressable>
    </View>
  );
}
