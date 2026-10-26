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
  /** Eigene Darstellung des Werts (z. B. mm:ss) */
  format?: (value: number) => string;
  /** Eigenes Lesen der Eingabe; null = ungültig */
  parse?: (text: string) => number | null;
  /** Hinweis unter dem Feld */
  hint?: string;
}

/** Große, touch-freundliche Zahleneingabe mit +/- Tasten (44 pt Ziele). */
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
  format,
  parse,
  hint,
}: StepperProps) {
  const display = React.useCallback((v: number) => (format ? format(v) : formatValue(v, decimals)), [format, decimals]);
  const [text, setText] = React.useState<string>(() => display(value));
  const [focused, setFocused] = React.useState(false);

  React.useEffect(() => {
    if (!focused) setText(display(value));
  }, [value, display, focused]);

  const clamp = (v: number) => Math.min(max, Math.max(min, v));
  const round = (v: number) => Math.round(v * 100) / 100;

  const commit = () => {
    setFocused(false);
    const parsed = parse ? parse(text) : parseFloat(text.replace(",", "."));
    if (parsed === null || Number.isNaN(parsed)) {
      setText(display(value));
      return;
    }
    const next = clamp(round(parsed));
    onChange(next);
    setText(display(next));
  };

  return (
    <div className={cn("flex flex-col gap-1.5", className)}>
      <label htmlFor={inputId} className="text-[13px] font-medium text-muted">
        {label}
      </label>
      <div className="flex h-14 items-stretch overflow-hidden rounded-[var(--radius-control)] bg-subtle">
        <button
          type="button"
          aria-label={`${label} verringern`}
          onClick={() => onChange(clamp(round(value - step)))}
          disabled={value <= min}
          className="press flex w-14 shrink-0 items-center justify-center text-fg hover:bg-hover disabled:opacity-30 touch-manipulation"
        >
          <Minus className="h-5 w-5" strokeWidth={2.4} />
        </button>
        <div className="relative flex flex-1 items-center justify-center">
          <input
            id={inputId}
            inputMode="decimal"
            value={text}
            onFocus={(e) => {
              setFocused(true);
              e.currentTarget.select();
            }}
            onChange={(e) => setText(e.target.value)}
            onBlur={commit}
            onKeyDown={(e) => {
              if (e.key === "Enter") (e.target as HTMLInputElement).blur();
            }}
            className="tnum h-full w-full bg-transparent text-center text-xl font-semibold text-fg focus:outline-none"
            aria-label={label}
          />
          {unit ? <span className="pointer-events-none absolute right-2 text-xs text-faint">{unit}</span> : null}
        </div>
        <button
          type="button"
          aria-label={`${label} erhöhen`}
          onClick={() => onChange(clamp(round(value + step)))}
          disabled={value >= max}
          className="press flex w-14 shrink-0 items-center justify-center text-fg hover:bg-hover disabled:opacity-30 touch-manipulation"
        >
          <Plus className="h-5 w-5" strokeWidth={2.4} />
        </button>
      </div>
      {hint ? <p className="text-xs text-faint">{hint}</p> : null}
    </div>
  );
}

function formatValue(v: number, decimals: number): string {
  const rounded = Math.round(v * 100) / 100;
  if (decimals === 0) return String(Math.round(rounded));
  return Number.isInteger(rounded) ? String(rounded) : String(rounded).replace(".", ",");
}
