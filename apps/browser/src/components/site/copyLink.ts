import { useEffect, useRef, useState } from "react";
import { copyPageUrl } from "./selection";

const COPIED_MS = 1400;

export function useCopyLink(tabId: string | undefined) {
  const [copiedTabId, setCopiedTabId] = useState<string | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);
  const copy = () => {
    if (!tabId) return;
    void copyPageUrl(tabId);
    setCopiedTabId(tabId);
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setCopiedTabId(null), COPIED_MS);
  };
  return { copied: !!tabId && copiedTabId === tabId, copy };
}
