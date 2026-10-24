import { Symbol, WindowDragRegion } from "@ardia/shell";
import { useEffect, useRef, useState } from "react";
import { Animated, Easing, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";
import { useShallow } from "zustand/react/shallow";
import { useTheme } from "../lib/theme";
import { useBrowser } from "../store/browser";
import { useWindowUi } from "../store/hooks";
import { downloadGroups, downloadsIn, downloadsShownInSidebar } from "../store/ui";
import { DownloadRowItem } from "./Downloads";
import { usePopoverPresence } from "./layout/controls";
import { IconButton } from "./primitives";

const TOP = 44;
const FIELD = 34;
const FOOTER = 44;
const INSET = 10;

export function DownloadsLibrary({ windowId }: { windowId: string }) {
  const inSidebar = useBrowser((s) => downloadsShownInSidebar(s, windowId));
  const { shown, closing, onClosed } = usePopoverPresence(useWindowUi().downloadsOpen && inSidebar);
  return shown ? <Library windowId={windowId} closing={closing} onClosed={onClosed} /> : null;
}

function Library({ windowId, closing, onClosed }: { windowId: string; closing: boolean; onClosed: () => void }) {
  const theme = useTheme();
  const [query, setQuery] = useState("");
  const [now, setNow] = useState(Date.now);
  const downloads = useBrowser(useShallow((s) => downloadsIn(s, windowId)));
  const groups = downloadGroups(downloads, query, now);
  const close = () => useBrowser.getState().setDownloadsOpen(windowId, false);
  useEffect(() => {
    const tick = setInterval(() => setNow(Date.now()), 60_000);
    return () => clearInterval(tick);
  }, []);
  const appear = useRef(new Animated.Value(0)).current;
  const closed = useRef(onClosed);
  closed.current = onClosed;
  useEffect(() => {
    Animated.timing(appear, { toValue: closing ? 0 : 1, duration: closing ? 120 : 160, easing: Easing.out(Easing.quad), useNativeDriver: true }).start(
      ({ finished }) => finished && closing && closed.current(),
    );
  }, [closing]);

  return (
    <Animated.View
      pointerEvents={closing ? "none" : "auto"}
      style={[StyleSheet.absoluteFill, { backgroundColor: theme.windowTint[0], opacity: appear, transform: [{ translateX: appear.interpolate({ inputRange: [0, 1], outputRange: [-12, 0] }) }] }]}
    >
      <WindowDragRegion style={{ height: TOP }} />
      <View
        style={{
          marginHorizontal: INSET,
          height: FIELD,
          borderRadius: 10,
          flexDirection: "row",
          alignItems: "center",
          gap: 8,
          paddingHorizontal: 10,
          backgroundColor: theme.dark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.06)",
        }}
      >
        <Symbol name="magnifyingglass" size={13} weight="medium" color={theme.textSecondary} style={{ width: 16, height: 16 }} />
        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder="Search Downloads…"
          placeholderTextColor={theme.placeholder}
          selectionColor={theme.selection}
          enableFocusRing={false}
          keyDownEvents={[{ key: "Escape" }]}
          onKeyDown={(e) => {
            if (e.nativeEvent.key !== "Escape") return;
            if (query) setQuery("");
            else close();
          }}
          style={{ flex: 1, fontSize: 14, color: theme.textPrimary, paddingVertical: 0 }}
        />
      </View>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: INSET - 4, paddingTop: 6, paddingBottom: 12 }}>
        {groups.length === 0 ? (
          <Text style={{ marginTop: 16, marginLeft: 8, fontSize: 13, color: theme.textSecondary }}>{query ? "No matching downloads" : "No downloads yet"}</Text>
        ) : (
          groups.map((group) => (
            <View key={group.day}>
              <Text style={{ marginTop: 14, marginBottom: 4, marginLeft: 8, fontSize: 13, fontWeight: "600", color: theme.textSecondary }}>{group.day}</Text>
              {group.ids.map((id) => (
                <DownloadRowItem key={id} id={id} windowId={windowId} variant="library" />
              ))}
            </View>
          ))
        )}
      </ScrollView>
      <View style={{ height: FOOTER, flexDirection: "row", alignItems: "center", paddingHorizontal: INSET - 4 }}>
        <IconButton icon="arrow.left" size={14} box={30} radius={8} onPress={close} tooltip="Back to Tabs (⇧⌘J)" />
      </View>
    </Animated.View>
  );
}
