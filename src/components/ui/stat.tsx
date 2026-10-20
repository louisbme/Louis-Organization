import * as React from "react";
import { cn } from "@/lib/utils/cn";

export function Stat({
  label,
  value,
  hint,
  className,
}: {
  label: string;
  value: React.ReactNode;
  hint?: string;
  className?: string;
}) {
  return (
    <div className={cn("rounded-[var(--radius-card)] border border-border bg-card px-4 py-4", className)}>
      <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-faint">{label}</p>
      <p className="tnum mt-1.5 text-2xl font-semibold tracking-tight text-fg">{value}</p>
      {hint ? <p className="mt-0.5 text-xs text-muted">{hint}</p> : null}
    </div>
  );
}
