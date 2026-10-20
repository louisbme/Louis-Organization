"use client";

import * as React from "react";

export const REST_PRESETS = [60, 90, 120, 180] as const;

interface RestTimerState {
  endsAt: number | null;
  duration: number;
}

function beep() {
  try {
    const Ctx = window.AudioContext || (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Ctx) return;
    const ctx = new Ctx();
    const play = (at: number) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "sine";
      osc.frequency.value = 880;
      gain.gain.setValueAtTime(0.0001, at);
      gain.gain.exponentialRampToValueAtTime(0.25, at + 0.01);
      gain.gain.exponentialRampToValueAtTime(0.0001, at + 0.18);
      osc.connect(gain).connect(ctx.destination);
      osc.start(at);
      osc.stop(at + 0.2);
    };
    play(ctx.currentTime);
    play(ctx.currentTime + 0.25);
    setTimeout(() => ctx.close().catch(() => undefined), 800);
  } catch {
    // Audio nicht verfügbar
  }
  try {
    navigator.vibrate?.([120, 60, 120]);
  } catch {
    // Vibration nicht verfügbar
  }
}

/** Einfacher Rest Timer auf Basis von Zeitstempeln (robust gegen Tab-Wechsel). */
export function useRestTimer(defaultSeconds: number) {
  const [state, setState] = React.useState<RestTimerState>({ endsAt: null, duration: defaultSeconds });
  const [remaining, setRemaining] = React.useState(0);
  const [justFinished, setJustFinished] = React.useState(false);

  React.useEffect(() => {
    if (!state.endsAt) return;
    const tick = () => {
      const left = Math.max(0, Math.ceil((state.endsAt! - Date.now()) / 1000));
      setRemaining(left);
      if (left <= 0) {
        setState((s) => ({ ...s, endsAt: null }));
        setJustFinished(true);
        beep();
        setTimeout(() => setJustFinished(false), 4000);
      }
    };
    tick();
    const id = window.setInterval(tick, 250);
    return () => window.clearInterval(id);
  }, [state.endsAt]);

  const start = React.useCallback((seconds?: number) => {
    const d = seconds ?? state.duration;
    setJustFinished(false);
    setState({ endsAt: Date.now() + d * 1000, duration: d });
  }, [state.duration]);

  const stop = React.useCallback(() => {
    setState((s) => ({ ...s, endsAt: null }));
    setRemaining(0);
  }, []);

  const add = React.useCallback((seconds: number) => {
    setState((s) => (s.endsAt ? { ...s, endsAt: s.endsAt + seconds * 1000 } : s));
  }, []);

  const setDuration = React.useCallback((seconds: number) => {
    setState((s) => ({ ...s, duration: seconds }));
  }, []);

  return {
    running: state.endsAt !== null,
    remaining,
    duration: state.duration,
    justFinished,
    start,
    stop,
    add,
    setDuration,
  };
}
