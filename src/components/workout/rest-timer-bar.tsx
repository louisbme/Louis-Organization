"use client";

import * as React from "react";
import { createPortal } from "react-dom";
import { Timer, X, Plus } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { formatClock } from "@/lib/utils/format";
import { REST_PRESETS, type useRestTimer } from "@/components/workout/use-rest-timer";
import { Sheet } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

type Timer = ReturnType<typeof useRestTimer>;

export function RestTimerBar({ timer }: { timer: Timer }) {
  const [open, setOpen] = React.useState(false);
  const [custom, setCustom] = React.useState(String(timer.duration));
  const [mounted, setMounted] = React.useState(false);
  React.useEffect(() => setMounted(true), []);

  const progress = timer.running && timer.duration > 0 ? 1 - timer.remaining / timer.duration : 0;

  const bar = (
      <div className="fixed inset-x-0 bottom-0 z-30 px-4 pb-[calc(0.5rem+env(safe-area-inset-bottom,0px))] pt-2 lg:left-64 lg:px-8">
        <div className="glass mx-auto flex max-w-md items-center gap-2 rounded-full p-1.5 shadow-[var(--shadow-float)] lg:max-w-5xl lg:rounded-[20px]">
          {timer.running ? (
            <>
              <div className="relative flex h-11 flex-1 items-center overflow-hidden rounded-full bg-subtle px-4">
                <div className="absolute inset-y-0 left-0 bg-accent-soft transition-[width] duration-200" style={{ width: `${progress * 100}%` }} />
                <span className="relative flex items-center gap-2 text-sm font-semibold">
                  <Timer className="h-4 w-4 text-accent" /> Pause
                </span>
                <span className="display tnum relative ml-auto text-xl">{formatClock(timer.remaining)}</span>
              </div>
              <Button variant="secondary" size="md" onClick={() => timer.add(30)} aria-label="30 Sekunden hinzufügen">
                <Plus className="h-4 w-4" strokeWidth={2.6} /> 30s
              </Button>
              <Button variant="ghost" size="icon" onClick={timer.stop} aria-label="Pause beenden">
                <X className="h-5 w-5" />
              </Button>
            </>
          ) : (
            <>
              <button
                type="button"
                onClick={() => setOpen(true)}
                className={cn(
                  "press flex h-11 flex-1 items-center justify-between rounded-full bg-subtle px-4 text-sm font-semibold hover:bg-hover touch-manipulation",
                  timer.justFinished && "bg-accent-soft text-accent"
                )}
              >
                <span className="flex items-center gap-2">
                  <Timer className="h-4 w-4 text-muted" /> {timer.justFinished ? "Pause vorbei" : "Rest Timer"}
                </span>
                <span className="tnum text-muted">{formatClock(timer.duration)}</span>
              </button>
              <Button onClick={() => timer.start()}>Start</Button>
            </>
          )}
        </div>
      </div>
  );

  return (
    <>
      {mounted ? createPortal(bar, document.body) : null}

      <Sheet open={open} onClose={() => setOpen(false)} title="Rest Timer" description="Preset wählen oder eigene Zeit in Sekunden.">
        <div className="grid grid-cols-4 gap-2">
          {REST_PRESETS.map((p) => (
            <button
              key={p}
              type="button"
              onClick={() => {
                timer.setDuration(p);
                setCustom(String(p));
                timer.start(p);
                setOpen(false);
              }}
              className={cn(
                "press h-14 rounded-[var(--radius-control)] text-base font-semibold touch-manipulation",
                timer.duration === p ? "bg-accent-fill text-accent-fg" : "bg-subtle hover:bg-hover"
              )}
            >
              {p}s
            </button>
          ))}
        </div>
        <form
          className="mt-4 flex gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            const v = Math.min(600, Math.max(10, parseInt(custom, 10) || 0));
            timer.setDuration(v);
            timer.start(v);
            setOpen(false);
          }}
        >
          <Input inputMode="numeric" value={custom} onChange={(e) => setCustom(e.target.value)} aria-label="Eigene Zeit in Sekunden" />
          <Button type="submit">Starten</Button>
        </form>
      </Sheet>
    </>
  );
}
