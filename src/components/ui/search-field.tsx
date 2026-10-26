"use client";

import * as React from "react";
import { Search, X } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface SearchFieldProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  className?: string;
  autoFocus?: boolean;
}

/** Suchfeld nach iOS: Lupe links, Löschen-Taste rechts, graue Fläche ohne Rahmen */
export function SearchField({ value, onChange, placeholder = "Suchen", className, autoFocus }: SearchFieldProps) {
  return (
    <div className={cn("relative", className)}>
      <Search className="pointer-events-none absolute left-3.5 top-1/2 h-[18px] w-[18px] -translate-y-1/2 text-faint" strokeWidth={2.2} />
      <input
        type="search"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        autoComplete="off"
        autoFocus={autoFocus}
        enterKeyHint="search"
        className="h-11 w-full rounded-[12px] bg-subtle pl-10 pr-10 text-base text-fg placeholder:text-faint focus:outline-none focus:ring-2 focus:ring-[var(--ring)]"
        aria-label={placeholder}
      />
      {value ? (
        <button
          type="button"
          onClick={() => onChange("")}
          aria-label="Suche löschen"
          className="absolute right-2 top-1/2 flex h-7 w-7 -translate-y-1/2 items-center justify-center rounded-full bg-hover text-muted hover:text-fg"
        >
          <X className="h-3.5 w-3.5" strokeWidth={2.6} />
        </button>
      ) : null}
    </div>
  );
}
