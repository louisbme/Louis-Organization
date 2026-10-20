"use client";

import * as React from "react";
import type { ThemePreference } from "@/lib/supabase/types";

export function applyTheme(theme: ThemePreference) {
  const root = document.documentElement;
  const light = theme === "light" || (theme === "system" && window.matchMedia("(prefers-color-scheme: light)").matches);
  if (light) root.setAttribute("data-theme", "light");
  else root.setAttribute("data-theme", "dark");
  try {
    localStorage.setItem("theme", theme);
  } catch {
    // Speicher nicht verfügbar
  }
}

/** Hält das Theme mit den Benutzereinstellungen synchron. */
export function ThemeSync({ theme }: { theme: ThemePreference }) {
  React.useEffect(() => {
    applyTheme(theme);
    if (theme !== "system") return;
    const mq = window.matchMedia("(prefers-color-scheme: light)");
    const onChange = () => applyTheme("system");
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, [theme]);
  return null;
}
