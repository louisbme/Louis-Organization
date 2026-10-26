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
import { upsertBodyWeight } from "@/lib/services/stats";
import type { ExerciseListItem } from "@/lib/services/exercises";
import type { ExerciseLastPerformance } from "@/lib/utils/progression";
import { suggestProgression } from "@/lib/utils/progression";
import { formatClock, formatDate, formatVolume, toDateKey } from "@/lib/utils/format";
import { describeBodyweight, describeSet, formatTarget } from "@/lib/utils/tracking";
import { friendlyError } from "@/lib/utils/errors";
import { cn } from "@/lib/utils/cn";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Sheet } from "@/components/ui/sheet";
import { Textarea } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { ExercisePickerSheet } from "@/components/exercise/exercise-picker-sheet";
import { RestTimerBar } from "@/components/workout/rest-timer-bar";
import { useRestTimer } from "@/components/workout/use-rest-timer";
import { SetEditor } from "@/components/workout/set-editor";
import { useWorkoutStore, clearSnapshot, type LocalExercise, type LocalSet } from "@/components/workout/use-workout-store";

interface Props {
  session: SessionDetail;
  lastPerformance: Record<string, ExerciseLastPerformance>;
  /** Zuletzt eingetragenes Körpergewicht (für Körpergewichtsübungen) */
  bodyWeight: number | null;
}

export function ActiveWorkout({ session, lastPerformance: lastPerformanceRecord, bodyWeight: initialBodyWeight }: Props) {
  const lastPerformance = React.useMemo(() => new Map(Object.entries(lastPerformanceRecord)), [lastPerformanceRecord]);
  const router = useRouter();
  const { userId, settings } = useUser();
  const unit = settings.weight_unit;
  const weightStep = Number(settings.weight_step) || 2.5;
  const store = useWorkoutStore(session, lastPerformance, weightStep, userId, initialBodyWeight);
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

  const onBodyWeightChange = async (value: number) => {
    try {
      await upsertBodyWeight(createClient(), userId, toDateKey(new Date()), value);
      store.setBodyWeight(value);
      toast.success("Körpergewicht gespeichert");
    } catch (e) {
      toast.error(friendlyError(e));
    }
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
  const progression = ex && ex.exercise.tracking_mode !== "cardio" ? suggestProgression(last, ex.target_sets, ex.rep_max) : null;

  return (
    <div className="pb-24">
      {/* Kopfzeile */}
      <div className="safe-top sticky top-0 z-20 -mx-4 mb-4 bg-bg/85 px-4 pb-3 pt-3 backdrop-blur-xl sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8">
        <div className="mx-auto flex max-w-5xl items-center gap-2">
          <Link href="/workout" className="press flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-accent hover:bg-subtle" aria-label="Zur Übersicht">
            <ChevronLeft className="h-6 w-6" strokeWidth={2.4} />
          </Link>
          <div className="min-w-0 flex-1">
            <p className="truncate text-base font-semibold">{session.name}</p>
            <p className="tnum text-[13px] text-muted">
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
          <Button size="icon-sm" variant="ghost" onClick={() => setMenu(true)} aria-label="Mehr">
            <MoreHorizontal className="h-5 w-5" />
          </Button>
        </div>
      </div>

      {/* Übungsnavigation */}
      <div className="no-scrollbar -mx-4 mb-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
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
                  "press flex h-10 shrink-0 items-center gap-2 rounded-full px-3.5 text-sm font-medium touch-manipulation",
                  i === safeIndex ? "bg-fg text-bg" : all ? "bg-card text-faint" : "bg-card text-muted"
                )}
              >
                {all ? <Check className="h-3.5 w-3.5" strokeWidth={3} /> : <span className="tnum text-xs">{i + 1}</span>}
                <span className="max-w-[9rem] truncate">{e.exercise.name}</span>
                <span className="tnum text-xs opacity-70">
                  {done}/{e.sets.length}
                </span>
              </button>
            );
          })}
          <button
            type="button"
            onClick={() => setPicker(true)}
            className="press flex h-10 shrink-0 items-center gap-1.5 rounded-full border border-dashed border-border-strong px-3.5 text-sm font-medium text-muted hover:text-fg touch-manipulation"
          >
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
          weightStep={weightStep}
          showRir={settings.show_rir}
          bodyWeight={store.bodyWeight}
          onBodyWeightChange={onBodyWeightChange}
          last={last}
          progression={progression}
          editingKey={editingKey}
          onEdit={setEditingKey}
          onPatch={(key, patch) => store.patchSet(ex.sessionExerciseId, key, patch)}
          onSave={onSave}
          onAddSet={() => store.addSet(ex.sessionExerciseId)}
          onRemoveLast={() => store.removeLastSet(ex.sessionExerciseId)}
          onRemoveExercise={() => store.removeExercise(ex.sessionExerciseId)}
          onPrev={() => {
            setCurrent((i) => Math.max(0, i - 1));
            setEditingKey(null);
          }}
          onNext={() => {
            setCurrent((i) => Math.min(exercises.length - 1, i + 1));
            setEditingKey(null);
          }}
        />
      ) : (
        <Card className="p-6 text-center text-sm text-muted">
          Keine Übungen im Training.{" "}
          <button type="button" className="font-semibold text-accent" onClick={() => setPicker(true)}>
            Übung hinzufügen
          </button>
        </Card>
      )}

      <RestTimerBar timer={timer} />

      <ExercisePickerSheet open={picker} onClose={() => setPicker(false)} onPick={onPickExercise} excludeIds={exercises.map((e) => e.exercise.id)} />

      <Sheet open={menu} onClose={() => setMenu(false)} title="Training">
        <div className="space-y-2">
          <Button
            variant="secondary"
            fullWidth
            onClick={() => {
              setMenu(false);
              setPicker(true);
            }}
          >
            <Plus className="h-4 w-4" /> Übung hinzufügen
          </Button>
          <Button
            variant="danger"
            fullWidth
            onClick={() => {
              setMenu(false);
              setCancelOpen(true);
            }}
          >
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
            <Button variant="secondary" fullWidth onClick={() => setCancelOpen(false)}>
              Weiter trainieren
            </Button>
            <Button variant="danger" fullWidth onClick={cancel} loading={busy}>
              Verwerfen
            </Button>
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
            <Check className="h-4 w-4" strokeWidth={3} /> Training speichern
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
          <label htmlFor="notes" className="mb-1.5 block text-[13px] font-medium text-muted">
            Notiz (optional)
          </label>
          <Textarea id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} maxLength={500} rows={3} placeholder="Wie lief es?" />
        </div>
      </Sheet>
    </div>
  );
}

function Summary({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-[var(--radius-control)] bg-subtle px-2 py-3">
      <p className="text-[13px] font-medium text-muted">{label}</p>
      <p className="display tnum mt-0.5 text-lg">{value}</p>
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
  bodyWeight: number | null;
  onBodyWeightChange: (v: number) => Promise<void>;
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

function ExerciseCard({
  ex,
  index,
  total,
  unit,
  weightStep,
  showRir,
  bodyWeight,
  onBodyWeightChange,
  last,
  progression,
  editingKey,
  onEdit,
  onPatch,
  onSave,
  onAddSet,
  onRemoveLast,
  onRemoveExercise,
  onPrev,
  onNext,
}: ExerciseCardProps) {
  const mode = ex.exercise.tracking_mode;
  const lastWorking = (last?.sets ?? []).filter((s) => !s.isWarmup);
  return (
    <Card className="overflow-hidden">
      <div className="px-5 pt-5">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="text-[13px] font-semibold uppercase tracking-[0.06em] text-muted">
              Übung {index + 1} von {total}
            </p>
            <Link href={`/exercises/${ex.exercise.slug}`} className="block text-xl font-semibold text-fg hover:text-accent">
              {ex.exercise.name}
            </Link>
            <p className="tnum mt-0.5 text-sm text-muted">
              Ziel: {formatTarget(mode, ex.target_sets, ex.rep_min, ex.rep_max, ex.target_duration_seconds, ex.target_distance_m)}
            </p>
          </div>
          {progression && progression.suggestion !== "none" ? (
            <Badge tone={progression.suggestion === "increase" ? "accent" : "neutral"} className="shrink-0">
              {progression.suggestion === "increase" ? (
                <>
                  <ArrowUp className="mr-1 h-3 w-3" strokeWidth={3} /> {mode === "bodyweight" ? "Zusatz erhöhen" : "Gewicht erhöhen"}
                </>
              ) : (
                <>
                  <Minus className="mr-1 h-3 w-3" strokeWidth={3} /> Halten
                </>
              )}
            </Badge>
          ) : null}
        </div>

        {lastWorking.length > 0 && last ? (
          <div className="mt-3 rounded-[var(--radius-control)] bg-subtle px-3.5 py-2.5">
            <p className="text-[13px] font-medium text-muted">Vorher · {formatDate(last.startedAt, "d. MMM")}</p>
            <p className="tnum mt-0.5 text-sm text-fg">
              {lastWorking
                .map((s) =>
                  describeSet(
                    mode,
                    { weight: s.weight, reps: s.reps, duration_seconds: s.durationSeconds, distance_m: s.distanceM, body_weight: s.bodyWeight, extra_weight: s.extraWeight },
                    unit
                  )
                )
                .join("  ·  ")}
            </p>
          </div>
        ) : (
          <p className="mt-3 text-sm text-faint">Noch keine vorherigen Werte für diese Übung.</p>
        )}
      </div>

      <div className="mt-4 border-t border-border">
        {ex.sets.map((set) => (
          <SetRow
            key={set.key}
            ex={ex}
            set={set}
            unit={unit}
            weightStep={weightStep}
            showRir={showRir}
            bodyWeight={bodyWeight}
            onBodyWeightChange={onBodyWeightChange}
            editing={editingKey === set.key}
            onEdit={() => onEdit(set.key)}
            onPatch={(patch) => onPatch(set.key, patch)}
            onSave={() => onSave(set)}
          />
        ))}
      </div>

      <div className="flex items-center gap-2 border-t border-border px-4 py-3">
        <Button variant="secondary" size="sm" onClick={onAddSet}>
          <Plus className="h-4 w-4" strokeWidth={2.6} /> Satz
        </Button>
        <Button variant="ghost" size="sm" onClick={onRemoveLast} disabled={ex.sets.length <= 1} aria-label="Letzten Satz entfernen">
          <Trash2 className="h-4 w-4" /> Letzter
        </Button>
        <div className="ml-auto flex gap-1">
          <Button variant="ghost" size="icon-sm" onClick={onPrev} disabled={index === 0} aria-label="Vorherige Übung">
            <ChevronLeft className="h-5 w-5" strokeWidth={2.4} />
          </Button>
          <Button variant="ghost" size="icon-sm" onClick={onNext} disabled={index >= total - 1} aria-label="Nächste Übung">
            <ChevronRight className="h-5 w-5" strokeWidth={2.4} />
          </Button>
        </div>
      </div>
      {ex.sets.every((s) => !s.completed) ? (
        <div className="border-t border-border px-4 py-2.5">
          <button type="button" onClick={onRemoveExercise} className="text-sm text-faint hover:text-danger">
            Übung aus diesem Training entfernen
          </button>
        </div>
      ) : null}
    </Card>
  );
}

function SetRow({
  ex,
  set,
  unit,
  weightStep,
  showRir,
  bodyWeight,
  onBodyWeightChange,
  editing,
  onEdit,
  onPatch,
  onSave,
}: {
  ex: LocalExercise;
  set: LocalSet;
  unit: "kg" | "lb";
  weightStep: number;
  showRir: boolean;
  bodyWeight: number | null;
  onBodyWeightChange: (v: number) => Promise<void>;
  editing: boolean;
  onEdit: () => void;
  onPatch: (p: Partial<LocalSet>) => void;
  onSave: () => void;
}) {
  const mode = ex.exercise.tracking_mode;
  const canSave = mode === "cardio" ? (set.duration_seconds ?? 0) > 0 || (set.distance_m ?? 0) > 0 : set.reps > 0 && (mode !== "bodyweight" || set.body_weight !== null);

  if (!editing) {
    const bwInfo = mode === "bodyweight" ? describeBodyweight(set, ex.exercise.bodyweight_factor, unit) : null;
    return (
      <button
        type="button"
        onClick={onEdit}
        className="relative flex min-h-[56px] w-full items-center gap-3 px-5 py-2 text-left hover:bg-subtle touch-manipulation after:absolute after:bottom-0 after:left-[68px] after:right-0 after:h-px after:bg-border after:content-['']"
      >
        <span className={cn("tnum flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm font-semibold", set.completed ? "bg-accent text-accent-fg" : "bg-subtle text-faint")}>
          {set.completed ? <Check className="h-4 w-4" strokeWidth={3} /> : set.set_number}
        </span>
        <div className="min-w-0 flex-1">
          <p className={cn("tnum text-base", set.completed ? "font-medium text-fg" : "text-muted")}>
            {describeSet(mode, set, unit)}
            {showRir && set.rir !== null && mode !== "cardio" ? <span className="ml-2 text-sm text-muted">RIR {set.rir}</span> : null}
            {!set.completed ? <span className="text-faint"> · offen</span> : null}
          </p>
          {bwInfo ? <p className="tnum truncate text-xs text-faint">{bwInfo}</p> : null}
        </div>
        {set.is_warmup ? (
          <Badge tone="warning">
            <Flame className="mr-1 h-3 w-3" /> Aufwärmen
          </Badge>
        ) : null}
        {set.pending ? <CloudOff className="h-4 w-4 text-warning" aria-label="Noch nicht synchronisiert" /> : null}
      </button>
    );
  }

  return (
    <div className="space-y-3 bg-subtle/40 px-4 py-4">
      <div className="flex items-center justify-between">
        <p className="text-base font-semibold">Satz {set.set_number}</p>
        <button
          type="button"
          onClick={() => onPatch({ is_warmup: !set.is_warmup })}
          className={cn(
            "press inline-flex h-8 items-center gap-1.5 rounded-full px-3 text-xs font-semibold touch-manipulation",
            set.is_warmup ? "bg-warning-soft text-warning" : "bg-subtle text-muted"
          )}
          aria-pressed={set.is_warmup}
        >
          <Flame className="h-3.5 w-3.5" /> Aufwärmsatz
        </button>
      </div>
      <SetEditor
        mode={mode}
        factor={ex.exercise.bodyweight_factor}
        set={set}
        unit={unit}
        weightStep={weightStep}
        showRir={showRir}
        bodyWeight={bodyWeight}
        onChange={onPatch}
        onBodyWeightChange={onBodyWeightChange}
        idPrefix={`set-${set.key}`}
      />
      <Button size="lg" fullWidth onClick={onSave} disabled={!canSave}>
        <Check className="h-4 w-4" strokeWidth={3} /> Satz speichern
      </Button>
    </div>
  );
}
