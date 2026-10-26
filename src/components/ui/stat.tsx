import * as React from "react";
import { cn } from "@/lib/utils/cn";
import { AnimatedNumber } from "@/components/ui/animated-number";

/** Kennzahl-Kachel: Beschriftung oben, Wert groß (Montserrat), optionaler Hinweis */
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
    <div className={cn("rounded-[var(--radius-card)] bg-card px-4 py-4", className)}>
      <p className="text-[13px] font-medium text-muted">{label}</p>
      <p className="display tnum mt-1 text-xl text-fg sm:text-2xl">
        {typeof value === "number" ? <AnimatedNumber value={value} /> : value}
      </p>
      {hint ? <p className="mt-0.5 text-xs text-faint">{hint}</p> : null}
    </div>
  );
}
