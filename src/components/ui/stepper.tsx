"use client";

import * as React from "react";
import { Minus, Plus } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface StepperProps {
  label: string;
  value: number;
  onChange: (value: number) => void;
  step: number;
  min?: number;
  max?: number;
  unit?: string;
  decimals?: number;
  className?: string;
  inputId?: string;
}

/** Große, touch-freundliche Zahleneingabe mit +/- Buttons. */
export function Stepper({
  label,
  value,
  onChange,
  step,
  min = 0,
  max = 9999,
  unit,
  decimals = 0,
  className,
  inputId,
}: StepperProps) {
  const [text, setText] = React.useState<string>(formatValue(value, decimals));

  React.useEffect(() => {
    setText(formatValue(value, decimals));
  }, [value, decimals]);

  const clamp = (v: number) => Math.min(max, Math.max(min, v));
  const round = (v: number) => Math.round(v * 100) / 100;

  const commit = () => {
    const parsed = parseFloat(text.replace(",", "."));
    if (Number.isNaN(parsed)) {
      setText(formatValue(value, decimals));
      return;
    }
    const next = clamp(round(parsed));
    onChange(next);
    setText(formatValue(next, decimals));
  };

  return (
    <div className={cn("flex flex-col gap-1.5", className)}>
      <label htmlFor={inputId} className="text-xs font-medium uppercase tracking-wider text-faint">
        {label}
      </label>
      <div className="flex h-14 items-stretch overflow-hidden rounded-xl border border-border bg-subtle">
        <button
          type="button"
          aria-label={`${label} verringern`}
          onClick={() => onChange(clamp(round(value - step)))}
          className="flex w-14 shrink-0 items-center justify-center text-muted hover:bg-hover hover:text-fg active:bg-hover touch-manipulation"
        >
          <Minus className="h-5 w-5" />
        </button>
        <div className="relative flex flex-1 items-center justify-center">
          <input
            id={inputId}
            type="text"
            inputMode="decimal"
            value={text}
            onChange={(e) => setText(e.target.value)}
            onBlur={commit}
            onKeyDown={(e) => {
              if (e.key === "Enter") (e.target as HTMLInputElement).blur();
            }}
            className="tnum h-full w-full bg-transparent text-center text-2xl font-semibold text-fg outline-none"
          />
          {unit ? (
            <span className="pointer-events-none absolute right-2 bottom-1 text-[10px] font-medium uppercase text-faint">
              {unit}
            </span>
          ) : null}
        </div>
        <button
          type="button"
          aria-label={`${label} erhöhen`}
          onClick={() => onChange(clamp(round(value + step)))}
          className="flex w-14 shrink-0 items-center justify-center text-muted hover:bg-hover hover:text-fg active:bg-hover touch-manipulation"
        >
          <Plus className="h-5 w-5" />
        </button>
      </div>
    </div>
  );
}

function formatValue(v: number, decimals: number) {
  if (decimals === 0) return String(Math.round(v));
  const s = v.toFixed(decimals);
  return s.replace(/\.?0+$/, "").replace(".", ",");
}
