import * as React from "react";
import { cn } from "@/lib/utils/cn";

type Tone = "neutral" | "accent" | "info" | "warning" | "danger";

const tones: Record<Tone, string> = {
  neutral: "bg-subtle text-muted border-border",
  accent: "bg-accent-soft text-accent border-transparent",
  info: "bg-info-soft text-info border-transparent",
  warning: "bg-warning-soft text-warning border-transparent",
  danger: "bg-danger-soft text-danger border-transparent",
};

export function Badge({
  tone = "neutral",
  className,
  ...props
}: React.HTMLAttributes<HTMLSpanElement> & { tone?: Tone }) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-md border px-2 py-0.5 text-xs font-medium leading-5",
        tones[tone],
        className
      )}
      {...props}
    />
  );
}
