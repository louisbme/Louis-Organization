"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Check, ChevronLeft, ChevronRight, Flame, MoreHorizontal, Plus, Trash2, X, CloudOff, ArrowUp, Minus } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import type { SessionDetail } from "@/lib/services/sessions";
import { cancelSession, completeSession } from "@/lib/services/sessions";
import type { ExerciseListItem } from "@/lib/services/exercises";
import type { ExerciseLastPerformance } from "@/lib/utils/progression";
import { suggestProgression } from "@/lib/utils/progression";
import { formatClock, formatDate, formatVolume, formatWeight, toDateKey } from "@/lib/utils/format";
import { friendlyError } from "@/lib/utils/errors";
import { cn } from "@/lib/utils/cn";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Sheet } from "@/components/ui/sheet";
import { Stepper } from "@/components/ui/stepper";
import { Textarea } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { ExercisePickerSheet } from "@/components/exercise/exercise-picker-sheet";
import { RestTimerBar } from "@/components/workout/rest-timer-bar";
import { useRestTimer } from "@/components/workout/use-rest-timer";
import { useWorkoutStore, clearSnapshot, type LocalExercise, type LocalSet } from "@/components/workout/use-workout-store";

interface Props {
  session: SessionDetail;
  lastPerformance: Record<string, ExerciseLastPerformance>;
}

export function ActiveWorkout({ session, lastPerformance: lastPerformanceRecord }: Props) {
  const lastPerformance = React.useMemo(() => new Map(Object.entries(lastPerformanceRecord)), [lastPerformanceRecord]);
  const router = useRouter();
  const { userId, settings } = useUser();
  const unit = settings.weight_unit;
  const store = useWorkoutStore(session, lastPerformance, Number(settings.weight_step) || 2.5, userId);
  const timer = useRestTimer(settings.rest_timer_default);
  const [current, setCurrent] = React.useState(0);
  const [editingKey, setEditingKey] = React.useState<string | null>(null);
  const [picker, setPicker] = React.useState(false);
  const [menu, setMenu] = React.useState(false);
  const [finishOpen, setFinishOpen] = React.useState(false);
  const [cancelOpen, setCancelOpen] = React.useState(false);
  const [notes, setNotes] = React.useState(session.notes ?? "");
  const [busy, setBusy] = React.useState(false);
  const [elapsed, setElapsed] = React.useState(0);

  React.useEffect(() => {
    const started = new Date(session.started_at).getTime();
    const tick = () => setElapsed(Math.floor((Date.now() - started) / 1000));
    tick();
    const id = window.setInterval(tick, 1000);
    return () => window.clearInterval(id);
  }, [session.started_at]);

  const exercises = store.exercises;
  const safeIndex = Math.min(current, Math.max(0, exercises.length - 1));
  const ex = exercises[safeIndex];

  // Automatisch den ersten offenen Satz zur Bearbeitung auswählen
  React.useEffect(() => {
    if (!ex) return;
    if (editingKey && ex.sets.some((s) => s.key === editingKey)) return;
    const firstOpen = ex.sets.find((s) => !s.completed);
    setEditingKey(firstOpen?.key ?? null);
  }, [ex, editingKey]);

  const onSave = async (set: LocalSet) => {
    if (!ex) return;
    await store.saveSet(ex.sessionExerciseId, set.key);
    const nextOpen = ex.sets.find((s) => !s.completed && s.key !== set.key);
    setEditingKey(nextOpen?.key ?? null);
    timer.start();
  };

  const finish = async () => {
    setBusy(true);
    try {
      if (store.pendingCount > 0) {
        const ok = await store.flushPending();
        if (!ok) {
          toast.error("Einige Sätze sind noch nicht synchronisiert. Bitte Verbindung prüfen.");
          setBusy(false);
          return;
        }
      }
      await completeSession(createClient(), session.id, notes.trim() || null, toDateKey(new Date()));
      clearSnapshot(session.id);
      toast.success("Training gespeichert");
      router.replace(`/history/${session.id}?done=1`);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
      setBusy(false);
    }
  };

  const cancel = async () => {
    setBusy(true);
    try {
      await cancelSession(createClient(), session.id);
      clearSnapshot(session.id);
      router.replace("/workout");
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
      setBusy(false);
    }
  };

  const onPickExercise = async (item: ExerciseListItem) => {
    setPicker(false);
    const ok = await store.addExercise(item);
    if (ok) setCurrent(exercises.length);
  };

  const last = ex ? lastPerformance.get(ex.exercise.id) : undefined;
  const progression = ex ? suggestProgression(last, ex.target_sets, ex.rep_max) : null;

  return (
    <div className="pb-24">
      {/* Kopfzeile */}
      <div className="safe-top sticky top-0 z-20 -mx-4 mb-4 border-b border-border bg-bg/95 px-4 pb-3 pt-3 backdrop-blur sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8">
        <div className="mx-auto flex max-w-5xl items-center gap-2">
          <Link href="/workout" className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg text-muted hover:bg-subtle" aria-label="Zur Übersicht">
            <ChevronLeft className="h-5 w-5" />
          </Link>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold">{session.name}</p>
            <p className="tnum text-xs text-muted">
              {formatClock(elapsed)} · {store.workingSetCount} Sätze · {formatVolume(store.volume, unit)}
              {store.pendingCount > 0 ? (
                <span className="ml-2 inline-flex items-center gap-1 text-warning">
                  <CloudOff className="h-3 w-3" /> {store.pendingCount} offen
                </span>
              ) : null}
            </p>
          </div>
          <Button size="sm" onClick={() => setFinishOpen(true)}>
            Beenden
          </Button>
          <Button size="icon" variant="ghost" onClick={() => setMenu(true)} aria-label="Mehr">
            <MoreHorizontal className="h-5 w-5" />
          </Button>
        </div>
      </div>

      {/* Übungsnavigation */}
      <div className="-mx-4 mb-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
        <div className="flex w-max gap-2 pb-1">
          {exercises.map((e, i) => {
            const done = e.sets.filter((s) => s.completed).length;
            const all = done >= e.sets.length;
            return (
              <button
                key={e.sessionExerciseId}
                type="button"
                onClick={() => {
                  setCurrent(i);
                  setEditingKey(null);
                }}
                className={cn(
                  "flex h-10 shrink-0 items-center gap-2 rounded-full border px-3.5 text-sm font-medium touch-manipulation",
                  i === safeIndex ? "border-accent bg-accent-soft text-accent" : all ? "border-border bg-subtle text-muted" : "border-border bg-card text-muted"
                )}
              >
                {all ? <Check className="h-3.5 w-3.5" /> : <span className="tnum text-xs">{i + 1}</span>}
                <span className="max-w-[9rem] truncate">{e.exercise.name}</span>
                <span className="tnum text-xs opacity-70">
                  {done}/{e.sets.length}
                </span>
              </button>
            );
          })}
          <button type="button" onClick={() => setPicker(true)} className="flex h-10 shrink-0 items-center gap-1.5 rounded-full border border-dashed border-border-strong px-3.5 text-sm font-medium text-muted hover:text-fg touch-manipulation">
            <Plus className="h-4 w-4" /> Übung
          </button>
        </div>
      </div>

      {ex ? (
        <ExerciseCard
          ex={ex}
          index={safeIndex}
          total={exercises.length}
          unit={unit}
          weightStep={Number(settings.weight_step) || 2.5}
          showRir={settings.show_rir}
          last={last}
          progression={progression}
          editingKey={editingKey}
          onEdit={setEditingKey}
          onPatch={(key, patch) => store.patchSet(ex.sessionExerciseId, key, patch)}
          onSave={onSave}
          onAddSet={() => store.addSet(ex.sessionExerciseId)}
          onRemoveLast={() => store.removeLastSet(ex.sessionExerciseId)}
          onRemoveExercise={() => store.removeExercise(ex.sessionExerciseId)}
          onPrev={() => { setCurrent((i) => Math.max(0, i - 1)); setEditingKey(null); }}
          onNext={() => { setCurrent((i) => Math.min(exercises.length - 1, i + 1)); setEditingKey(null); }}
        />
      ) : (
        <Card className="p-6 text-center text-sm text-muted">
          Keine Übungen im Training.{" "}
          <button type="button" className="text-accent" onClick={() => setPicker(true)}>
            Übung hinzufügen
          </button>
        </Card>
      )}

      <RestTimerBar timer={timer} />

      <ExercisePickerSheet open={picker} onClose={() => setPicker(false)} onPick={onPickExercise} excludeIds={exercises.map((e) => e.exercise.id)} />

      <Sheet open={menu} onClose={() => setMenu(false)} title="Training">
        <div className="space-y-2">
          <Button variant="secondary" fullWidth onClick={() => { setMenu(false); setPicker(true); }}>
            <Plus className="h-4 w-4" /> Übung hinzufügen
          </Button>
          <Button variant="danger" fullWidth onClick={() => { setMenu(false); setCancelOpen(true); }}>
            <X className="h-4 w-4" /> Training abbrechen
          </Button>
        </div>
      </Sheet>

      <Sheet
        open={cancelOpen}
        onClose={() => setCancelOpen(false)}
        title="Training abbrechen?"
        description="Alle Sätze dieses Trainings werden verworfen."
        footer={
          <div className="flex gap-2">
            <Button variant="secondary" fullWidth onClick={() => setCancelOpen(false)}>Weiter trainieren</Button>
            <Button variant="danger" fullWidth onClick={cancel} loading={busy}>Verwerfen</Button>
          </div>
        }
      >
        <div />
      </Sheet>

      <Sheet
        open={finishOpen}
        onClose={() => setFinishOpen(false)}
        title="Training abschließen"
        footer={
          <Button size="lg" fullWidth onClick={finish} loading={busy} disabled={store.completedSetCount === 0}>
            <Check className="h-4 w-4" /> Training speichern
          </Button>
        }
      >
        <div className="grid grid-cols-3 gap-2 text-center">
          <Summary label="Dauer" value={formatClock(elapsed)} />
          <Summary label="Sätze" value={String(store.workingSetCount)} />
          <Summary label="Volumen" value={formatVolume(store.volume, unit)} />
        </div>
        {store.completedSetCount === 0 ? (
          <p className="mt-4 text-sm text-warning">Noch kein Satz gespeichert. Speichere mindestens einen Satz oder brich das Training ab.</p>
        ) : null}
        <div className="mt-4">
          <label htmlFor="notes" className="mb-1.5 block text-sm font-medium text-muted">Notiz (optional)</label>
          <Textarea id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} maxLength={500} rows={3} placeholder="Wie lief es?" />
        </div>
      </Sheet>
    </div>
  );
}

function Summary({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl bg-subtle px-2 py-3">
      <p className="text-[10px] font-medium uppercase tracking-wider text-faint">{label}</p>
      <p className="tnum mt-0.5 text-base font-semibold">{value}</p>
    </div>
  );
}

interface ExerciseCardProps {
  ex: LocalExercise;
  index: number;
  total: number;
  unit: "kg" | "lb";
  weightStep: number;
  showRir: boolean;
  last: ExerciseLastPerformance | undefined;
  progression: ReturnType<typeof suggestProgression> | null;
  editingKey: string | null;
  onEdit: (key: string | null) => void;
  onPatch: (key: string, patch: Partial<LocalSet>) => void;
  onSave: (set: LocalSet) => void;
  onAddSet: () => void;
  onRemoveLast: () => void;
  onRemoveExercise: () => void;
  onPrev: () => void;
  onNext: () => void;
}

function ExerciseCard({ ex, index, total, unit, weightStep, showRir, last, progression, editingKey, onEdit, onPatch, onSave, onAddSet, onRemoveLast, onRemoveExercise, onPrev, onNext }: ExerciseCardProps) {
  const lastWorking = (last?.sets ?? []).filter((s) => !s.isWarmup);
  return (
    <Card className="overflow-hidden">
      <div className="px-5 pt-5">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-faint">
              Übung {index + 1} von {total}
            </p>
            <Link href={`/exercises/${ex.exercise.slug}`} className="block text-xl font-semibold tracking-tight hover:text-accent">
              {ex.exercise.name}
            </Link>
            <p className="tnum mt-0.5 text-sm text-muted">
              Ziel: {ex.target_sets} × {ex.rep_min}–{ex.rep_max}
            </p>
          </div>
          {progression && progression.suggestion !== "none" ? (
            <Badge tone={progression.suggestion === "increase" ? "accent" : "neutral"} className="shrink-0">
              {progression.suggestion === "increase" ? (
                <>
                  <ArrowUp className="mr-1 h-3 w-3" /> Gewicht erhöhen
                </>
              ) : (
                <>
                  <Minus className="mr-1 h-3 w-3" /> Gewicht halten
                </>
              )}
            </Badge>
          ) : null}
        </div>

        {lastWorking.length > 0 && last ? (
          <div className="mt-3 rounded-lg bg-subtle px-3 py-2">
            <p className="text-[11px] font-medium uppercase tracking-wider text-faint">Vorher · {formatDate(last.startedAt, "d. MMM")}</p>
            <p className="tnum mt-0.5 text-sm text-muted">
              {lastWorking.map((s) => `${formatWeight(s.weight, unit)} × ${s.reps}`).join("  ·  ")}
            </p>
          </div>
        ) : (
          <p className="mt-3 text-xs text-faint">Noch keine vorherigen Werte für diese Übung.</p>
        )}
      </div>

      <div className="mt-4 divide-y divide-border border-t border-border">
        {ex.sets.map((set) => (
          <SetRow
            key={set.key}
            set={set}
            unit={unit}
            weightStep={weightStep}
            showRir={showRir}
            editing={editingKey === set.key}
            onEdit={() => onEdit(set.key)}
            onPatch={(patch) => onPatch(set.key, patch)}
            onSave={() => onSave(set)}
          />
        ))}
      </div>

      <div className="flex items-center gap-2 px-4 py-3">
        <Button variant="secondary" size="sm" onClick={onAddSet}>
          <Plus className="h-4 w-4" /> Satz
        </Button>
        <Button variant="ghost" size="sm" onClick={onRemoveLast} disabled={ex.sets.length <= 1} aria-label="Letzten Satz entfernen">
          <Trash2 className="h-4 w-4" /> Letzter Satz
        </Button>
        <div className="ml-auto flex gap-1">
          <Button variant="ghost" size="icon" onClick={onPrev} disabled={index === 0} aria-label="Vorherige Übung">
            <ChevronLeft className="h-5 w-5" />
          </Button>
          <Button variant="ghost" size="icon" onClick={onNext} disabled={index >= total - 1} aria-label="Nächste Übung">
            <ChevronRight className="h-5 w-5" />
          </Button>
        </div>
      </div>
      {ex.sets.every((s) => !s.completed) ? (
        <div className="border-t border-border px-4 py-2">
          <button type="button" onClick={onRemoveExercise} className="text-xs text-faint hover:text-danger">
            Übung aus diesem Training entfernen
          </button>
        </div>
      ) : null}
    </Card>
  );
}

function SetRow({ set, unit, weightStep, showRir, editing, onEdit, onPatch, onSave }: { set: LocalSet; unit: string; weightStep: number; showRir: boolean; editing: boolean; onEdit: () => void; onPatch: (p: Partial<LocalSet>) => void; onSave: () => void }) {
  if (!editing) {
    return (
      <button type="button" onClick={onEdit} className="flex min-h-14 w-full items-center gap-3 px-5 py-2 text-left hover:bg-subtle touch-manipulation">
        <span className={cn("tnum flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-sm font-semibold", set.completed ? "bg-accent-soft text-accent" : "bg-subtle text-faint")}>
          {set.completed ? <Check className="h-4 w-4" /> : set.set_number}
        </span>
        <div className="min-w-0 flex-1">
          {set.completed ? (
            <p className="tnum text-base font-medium">
              {formatWeight(set.weight, unit as "kg")} × {set.reps}
              {showRir && set.rir !== null ? <span className="ml-2 text-sm text-muted">RIR {set.rir}</span> : null}
            </p>
          ) : (
            <p className="tnum text-base text-muted">
              {formatWeight(set.weight, unit as "kg")} × {set.reps} <span className="text-faint">· offen</span>
            </p>
          )}
        </div>
        {set.is_warmup ? <Badge tone="warning"><Flame className="mr-1 h-3 w-3" /> Aufwärmen</Badge> : null}
        {set.pending ? <CloudOff className="h-4 w-4 text-warning" aria-label="Noch nicht synchronisiert" /> : null}
      </button>
    );
  }

  return (
    <div className="space-y-3 bg-subtle/40 px-4 py-4">
      <div className="flex items-center justify-between">
        <p className="text-sm font-semibold">Satz {set.set_number}</p>
        <button
          type="button"
          onClick={() => onPatch({ is_warmup: !set.is_warmup })}
          className={cn("inline-flex h-8 items-center gap-1.5 rounded-full border px-3 text-xs font-medium touch-manipulation", set.is_warmup ? "border-warning bg-warning-soft text-warning" : "border-border text-muted")}
          aria-pressed={set.is_warmup}
        >
          <Flame className="h-3.5 w-3.5" /> Aufwärmsatz
        </button>
      </div>
      <div className={cn("grid gap-3", showRir ? "grid-cols-1 sm:grid-cols-3" : "grid-cols-1 sm:grid-cols-2")}>
        <Stepper label="Gewicht" unit={unit} value={set.weight} step={weightStep} decimals={2} onChange={(v) => onPatch({ weight: v })} max={999} />
        <Stepper label="Wiederholungen" value={set.reps} step={1} onChange={(v) => onPatch({ reps: v })} max={500} />
        {showRir ? (
          <Stepper label="RIR" value={set.rir ?? 2} step={1} onChange={(v) => onPatch({ rir: v })} min={0} max={10} />
        ) : null}
      </div>
      <Button size="lg" fullWidth onClick={onSave}>
        <Check className="h-4 w-4" /> Satz speichern
      </Button>
    </div>
  );
}
