"use client";

import * as React from "react";
import { Segmented } from "@/components/ui/segmented";

type Tab = "list" | "calendar";
const STORAGE_KEY = "history-tab";

interface Props {
  initialTab: Tab;
  list: React.ReactNode;
  calendar: React.ReactNode;
}

/** Verlauf als Liste oder Kalender; die Wahl wird je Gerät gemerkt. */
export function HistoryTabs({ initialTab, list, calendar }: Props) {
  const [tab, setTab] = React.useState<Tab>(initialTab);

  React.useEffect(() => {
    if (initialTab !== "list") return;
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved === "calendar") setTab("calendar");
    } catch {
      // Speicher nicht verfügbar
    }
  }, [initialTab]);

  const change = (next: Tab) => {
    setTab(next);
    try {
      localStorage.setItem(STORAGE_KEY, next);
    } catch {
      // ignore
    }
  };

  return (
    <div className="space-y-4">
      <Segmented
        value={tab}
        onChange={change}
        options={[
          { value: "list", label: "Liste" },
          { value: "calendar", label: "Kalender" },
        ]}
      />
      {tab === "list" ? list : calendar}
    </div>
  );
}
