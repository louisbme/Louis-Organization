"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Segmented } from "@/components/ui/segmented";

type Tab = "list" | "calendar";

/** Umschalten zwischen Kalender (/calendar) und Liste (/history); beide sind eigene Seiten. */
export function HistoryTabs({ active }: { active: Tab }) {
  const router = useRouter();
  return (
    <Segmented
      value={active}
      onChange={(next) => router.push(next === "calendar" ? "/calendar" : "/history")}
      options={[
        { value: "calendar", label: "Kalender" },
        { value: "list", label: "Liste" },
      ]}
    />
  );
}
