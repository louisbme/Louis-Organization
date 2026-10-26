import * as React from "react";
import { cn } from "@/lib/utils/cn";

type Tone = "neutral" | "accent" | "info" | "warning" | "danger" | "success";

const tones: Record<Tone, string> = {
  neutral: "bg-subtle text-muted",
  accent: "bg-accent-soft text-accent",
  info: "bg-info-soft text-info",
  warning: "bg-warning-soft text-warning",
  danger: "bg-danger-soft text-danger",
  success: "bg-success-soft text-success",
};

export function Badge({ tone = "neutral", className, ...props }: React.HTMLAttributes<HTMLSpanElement> & { tone?: Tone }) {
  return <span className={cn("inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold leading-5", tones[tone], className)} {...props} />;
}
