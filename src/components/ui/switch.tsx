"use client";

import { cn } from "@/lib/utils/cn";

/** Schalter nach iOS (51 × 31 pt, grün im eingeschalteten Zustand) */
export function Switch({
  checked,
  onChange,
  label,
  description,
  disabled,
}: {
  checked: boolean;
  onChange: (next: boolean) => void;
  label: string;
  description?: string;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className="flex min-h-[52px] w-full items-center justify-between gap-4 py-2 text-left disabled:opacity-50 touch-manipulation"
    >
      <span className="min-w-0">
        <span className="block text-base text-fg">{label}</span>
        {description ? <span className="block text-sm text-muted">{description}</span> : null}
      </span>
      <span
        className={cn(
          "relative inline-flex h-[31px] w-[51px] shrink-0 items-center rounded-full transition-colors duration-200",
          checked ? "bg-success" : "bg-hover"
        )}
      >
        <span
          className={cn(
            "inline-block h-[27px] w-[27px] rounded-full bg-white shadow-[0_3px_8px_rgba(0,0,0,0.25)] transition-transform duration-200",
            checked ? "translate-x-[22px]" : "translate-x-[2px]"
          )}
        />
      </span>
    </button>
  );
}
