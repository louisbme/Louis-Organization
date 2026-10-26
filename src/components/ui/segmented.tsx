"use client";

import * as React from "react";
import { cn } from "@/lib/utils/cn";

interface SegmentedProps<T extends string> {
  value: T;
  onChange: (value: T) => void;
  options: Array<{ value: T; label: string }>;
  className?: string;
  size?: "sm" | "md";
}

/** Segmentierte Steuerung nach iOS: graue Fläche, aktives Segment hell mit Schatten */
export function Segmented<T extends string>({ value, onChange, options, className, size = "md" }: SegmentedProps<T>) {
  return (
    <div role="tablist" className={cn("inline-flex w-full rounded-[10px] bg-subtle p-0.5", className)}>
      {options.map((o) => {
        const active = o.value === value;
        return (
          <button
            key={o.value}
            role="tab"
            type="button"
            aria-selected={active}
            onClick={() => onChange(o.value)}
            className={cn(
              "flex-1 rounded-[8px] font-medium transition-colors touch-manipulation",
              size === "sm" ? "h-8 px-2 text-xs" : "h-9 px-3 text-sm",
              active ? "bg-[var(--segment-active)] text-fg shadow-[0_1px_3px_rgba(0,0,0,0.25)]" : "text-muted hover:text-fg"
            )}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}
