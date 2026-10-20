"use client";

import * as React from "react";
import { usePathname } from "next/navigation";

/** Lässt den Seiteninhalt bei jedem Routenwechsel dezent einblenden. */
export function PageTransition({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  return (
    <div key={pathname} className="page-enter">
      {children}
    </div>
  );
}
