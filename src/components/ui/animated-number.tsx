"use client";

import * as React from "react";

interface AnimatedNumberProps {
  value: number;
  /** Formatierung des Zwischenwerts (z. B. formatVolume) */
  format?: (v: number) => string;
  duration?: number;
  className?: string;
}

/** Zählt beim Erscheinen von 0 zum Zielwert hoch (respektiert prefers-reduced-motion). */
export function AnimatedNumber({ value, format = (v) => String(Math.round(v)), duration = 700, className }: AnimatedNumberProps) {
  const [display, setDisplay] = React.useState(() => value);
  const fromRef = React.useRef(0);

  React.useEffect(() => {
    const reduce = typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce || value === 0) {
      setDisplay(value);
      fromRef.current = value;
      return;
    }
    const from = fromRef.current;
    const start = performance.now();
    let frame = 0;
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - t, 3);
      setDisplay(from + (value - from) * eased);
      if (t < 1) frame = requestAnimationFrame(tick);
      else fromRef.current = value;
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [value, duration]);

  return <span className={className}>{format(display)}</span>;
}
