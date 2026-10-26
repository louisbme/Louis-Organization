"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Check, Flame, MoreHorizontal, Pencil, Plus, Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import type { WorkoutSetRow } from "@/lib/supabase/types";
import type { ExerciseListItem } from "@/lib/services/exercises";
import {
  addSessionExercise,
  deleteSet,
  removeSessionExercise,
  saveSet,
  updateSet,
  type SessionDetail,
  type SessionExerciseDetail,
} from "@/lib/services/sessions";
import { upsertBodyWeight } from "@/lib/services/stats";
import { formatVolume, toDateKey } from "@/lib/utils/format";
import { bodyweightLoad, describeBodyweight, describeSet, formatTarget, setHasValues, setVolume } from "@/lib/utils/tracking";
import { friendlyError } from "@/lib/utils/errors";
import { cn } from "@/lib/utils/cn";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Sheet } from "@/components/ui/sheet";
import { Badge } from "@/components/ui/badge";
import { ExercisePickerSheet } from "@/components/exercise/exercise-picker-sheet";
import { SetEditor, type EditableSet } from "@/components/workout/set-editor";

interface Props {
  session: SessionDetail;
  bodyWeight: number | null;
}

type Draft = EditableSet & { is_warmup: boolean };

interface EditorState {
  exercise: SessionExerciseDetail;
  /** Bestehender Satz oder null für einen neuen */
  set: WorkoutSetRow | null;
  draft: Draft;
}

/**
 * Abgeschlossenes Training nachträglich bearbeiten: Sätze ändern, hinzufügen, löschen,
 * Übungen hinzufügen oder entfernen. Summen berechnet die Datenbank neu.
 */
export function SessionEditor({ session: initial, bodyWeight: initialBodyWeight }: Props) {
  const router = useRouter();
  const { userId, settings } = useUser();
  const unit = settings.weight_unit;
  const weightStep = Number(settings.weight_step) || 2.5;
  const db = React.useMemo(() => createClient(), []);
  const [exercises, setExercises] = React.useState(initial.exercises);
  const [bodyWeight, setBodyWeight] = React.useState(initialBodyWeight);
  const [editor, setEditor] = React.useState<EditorState | null>(null);
  const [exerciseMenu, setExerciseMenu] = React.useState<SessionExerciseDetail | null>(null);
  const [confirmRemove, setConfirmRemove] = React.useState<SessionExerciseDetail | null>(null);
  const [picker, setPicker] = React.useState(false);
  const [busy, setBusy] = React.useState(false);

  React.useEffect(() => setExercises(initial.exercises), [initial.exercises]);

  const openExisting = (exercise: SessionExerciseDetail, set: WorkoutSetRow) => {
    setEditor({
      exercise,
      set,
      draft: {
        weight: set.weight,
        reps: set.reps,
        rir: set.rir,
        is_warmup: set.is_warmup,
        duration_seconds: set.duration_seconds,
        distance_m: set.distance_m,
        body_weight: set.body_weight,
        extra_weight: set.extra_weight,
      },
    });
  };

  const openNew = (exercise: SessionExerciseDetail) => {
    const mode = exercise.exercise.tracking_mode;
    const last = exercise.sets.filter((s) => s.completed).at(-1);
    const bw = last?.body_weight ?? bodyWeight;
    const extra = last?.extra_weight ?? 0;
    setEditor({
      exercise,
      set: null,
      draft: {
        weight: mode === "bodyweight" ? bodyweightLoad(bw, exercise.exercise.bodyweight_factor, extra) : (last?.weight ?? 0),
        reps: mode === "cardio" ? 0 : (last?.reps ?? exercise.rep_min),
        rir: last?.rir ?? null,
        is_warmup: false,
        duration_seconds: last?.duration_seconds ?? null,
        distance_m: last?.distance_m ?? null,
        body_weight: mode === "bodyweight" ? bw : null,
        extra_weight: mode === "bodyweight" ? extra : null,
      },
    });
  };

  const patchDraft = (patch: Partial<Draft>) => setEditor((e) => (e ? { ...e, draft: { ...e.draft, ...patch } } : e));

  const onBodyWeightChange = async (value: number) => {
    await upsertBodyWeight(db, userId, toDateKey(new Date()), value);
    setBodyWeight(value);
  };

  const save = async () => {
    if (!editor) return;
    const { exercise, set, draft } = editor;
    const mode = exercise.exercise.tracking_mode;
    const values = {
      weight: mode === "cardio" ? 0 : draft.weight,
      reps: mode === "cardio" ? 0 : draft.reps,
      rir: mode === "cardio" ? null : draft.rir,
      is_warmup: mode === "cardio" ? false : draft.is_warmup,
      duration_seconds: mode === "cardio" ? draft.duration_seconds : null,
      distance_m: mode === "cardio" ? draft.distance_m : null,
      body_weight: mode === "bodyweight" ? draft.body_weight : null,
      extra_weight: mode === "bodyweight" ? draft.extra_weight : null,
    };
    setBusy(true);
    try {
      let saved: WorkoutSetRow;
      if (set) {
        saved = await updateSet(db, set.id, values);
      } else {
        const nextNumber = (exercise.sets.at(-1)?.set_number ?? 0) + 1;
        saved = await saveSet(db, { ...values, session_exercise_id: exercise.id, user_id: userId, set_number: nextNumber, completed: true });
      }
      setExercises((list) =>
        list.map((e) =>
          e.id === exercise.id
            ? { ...e, sets: [...e.sets.filter((s) => s.id !== saved.id), saved].sort((a, b) => a.set_number - b.set_number) }
            : e
        )
      );
      setEditor(null);
      toast.success(set ? "Satz geändert" : "Satz hinzugefügt");
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    if (!editor?.set) return;
    const { exercise, set } = editor;
    setBusy(true);
    try {
      await deleteSet(db, set.id);
      setExercises((list) => list.map((e) => (e.id === exercise.id ? { ...e, sets: e.sets.filter((s) => s.id !== set.id) } : e)));
      setEditor(null);
      toast.success("Satz gelöscht");
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setBusy(false);
    }
  };

  const removeExercise = async () => {
    if (!confirmRemove) return;
    setBusy(true);
    try {
      await removeSessionExercise(db, confirmRemove.id);
      setExercises((list) => list.filter((e) => e.id !== confirmRemove.id));
      setConfirmRemove(null);
      toast.success("Übung entfernt");
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setBusy(false);
    }
  };

  const onPickExercise = async (item: ExerciseListItem) => {
    setPicker(false);
    try {
      const order = (exercises.at(-1)?.sort_order ?? 0) + 1;
      const row = await addSessionExercise(db, {
        session_id: initial.id,
        user_id: userId,
        exercise_id: item.id,
        sort_order: order,
        target_sets: item.tracking_mode === "cardio" ? 1 : 3,
        rep_min: 8,
        rep_max: 12,
      });
      const detail: SessionExerciseDetail = { ...row, exercise: item, sets: [] };
      setExercises((list) => [...list, detail]);
      openNew(detail);
    } catch (e) {
      toast.error(friendlyError(e));
    }
  };

  const draftValid = editor ? setHasValues(editor.exercise.exercise.tracking_mode, editor.draft) && (editor.exercise.exercise.tracking_mode !== "bodyweight" || editor.draft.body_weight !== null) : false;

  return (
    <div className="space-y-3">
      {exercises.map((se) => {
        const mode = se.exercise.tracking_mode;
        const completed = se.sets.filter((s) => s.completed);
        const working = completed.filter((s) => !s.is_warmup);
        const volume = working.reduce((v, s) => v + setVolume(mode, s), 0);
        return (
          <Card key={se.id} className="overflow-hidden">
            <div className="flex items-start justify-between gap-3 px-5 pt-4">
              <div className="min-w-0">
                <Link href={`/exercises/${se.exercise.slug}`} className="block truncate text-base font-semibold text-fg hover:text-accent">
                  {se.exercise.name}
                </Link>
                <p className="tnum text-sm text-muted">
                  Ziel {formatTarget(mode, se.target_sets, se.rep_min, se.rep_max)} · {working.length} {mode === "cardio" ? (working.length === 1 ? "Einheit" : "Einheiten") : "Arbeitssätze"}
                </p>
              </div>
              <div className="flex shrink-0 items-center gap-1">
                {mode !== "cardio" ? <span className="tnum text-sm text-muted">{formatVolume(volume, unit)}</span> : null}
                <Button variant="ghost" size="icon-sm" aria-label="Übung bearbeiten" onClick={() => setExerciseMenu(se)}>
                  <MoreHorizontal className="h-5 w-5" />
                </Button>
              </div>
            </div>
            <div className="mt-3 border-t border-border">
              {completed.length === 0 ? <p className="px-5 py-3 text-sm text-faint">Noch keine Sätze.</p> : null}
              {completed.map((s) => {
                const bwInfo = mode === "bodyweight" ? describeBodyweight(s, se.exercise.bodyweight_factor, unit) : null;
                return (
                  <button
                    key={s.id}
                    type="button"
                    onClick={() => openExisting(se, s)}
                    className="press relative flex min-h-[52px] w-full items-center gap-3 px-5 py-2 text-left hover:bg-subtle touch-manipulation after:absolute after:bottom-0 after:left-[68px] after:right-0 after:h-px after:bg-border after:content-['']"
                    aria-label={`Satz ${s.set_number} bearbeiten`}
                  >
                    <span className="tnum flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-subtle text-sm font-semibold text-muted">{s.set_number}</span>
                    <span className="min-w-0 flex-1">
                      <span className="tnum block text-base text-fg">
                        {describeSet(mode, s, unit)}
                        {settings.show_rir && s.rir !== null && mode !== "cardio" ? <span className="ml-2 text-sm text-muted">RIR {s.rir}</span> : null}
                      </span>
                      {bwInfo ? <span className="tnum block truncate text-xs text-faint">{bwInfo}</span> : null}
                    </span>
                    {s.is_warmup ? (
                      <Badge tone="warning">
                        <Flame className="mr-1 h-3 w-3" /> Aufwärmen
                      </Badge>
                    ) : null}
                    <Pencil className="h-4 w-4 shrink-0 text-faint" />
                  </button>
                );
              })}
            </div>
            <div className="border-t border-border px-4 py-2.5">
              <Button variant="plain" size="sm" onClick={() => openNew(se)}>
                <Plus className="h-4 w-4" strokeWidth={2.6} /> Satz hinzufügen
              </Button>
            </div>
          </Card>
        );
      })}

      <Button variant="secondary" fullWidth onClick={() => setPicker(true)}>
        <Plus className="h-4 w-4" strokeWidth={2.6} /> Übung hinzufügen
      </Button>

      <ExercisePickerSheet open={picker} onClose={() => setPicker(false)} onPick={onPickExercise} excludeIds={exercises.map((e) => e.exercise_id)} />

      {/* Satz bearbeiten / hinzufügen */}
      <Sheet
        open={editor !== null}
        onClose={() => setEditor(null)}
        title={editor ? (editor.set ? `Satz ${editor.set.set_number}` : "Neuer Satz") : ""}
        description={editor?.exercise.exercise.name}
        footer={
          editor ? (
            <div className="flex gap-2">
              {editor.set ? (
                <Button variant="danger" onClick={remove} loading={busy} aria-label="Satz löschen">
                  <Trash2 className="h-4 w-4" />
                </Button>
              ) : null}
              <Button fullWidth onClick={save} loading={busy} disabled={!draftValid}>
                <Check className="h-4 w-4" strokeWidth={3} /> Speichern
              </Button>
            </div>
          ) : null
        }
      >
        {editor ? (
          <div className="space-y-3">
            {editor.exercise.exercise.tracking_mode !== "cardio" ? (
              <button
                type="button"
                onClick={() => patchDraft({ is_warmup: !editor.draft.is_warmup })}
                className={cn(
                  "press inline-flex h-8 items-center gap-1.5 rounded-full px-3 text-xs font-semibold touch-manipulation",
                  editor.draft.is_warmup ? "bg-warning-soft text-warning" : "bg-subtle text-muted"
                )}
                aria-pressed={editor.draft.is_warmup}
              >
                <Flame className="h-3.5 w-3.5" /> Aufwärmsatz
              </button>
            ) : null}
            <SetEditor
              mode={editor.exercise.exercise.tracking_mode}
              factor={editor.exercise.exercise.bodyweight_factor}
              set={editor.draft}
              unit={unit}
              weightStep={weightStep}
              showRir={settings.show_rir}
              bodyWeight={bodyWeight}
              onChange={patchDraft}
              onBodyWeightChange={onBodyWeightChange}
              idPrefix="edit"
            />
          </div>
        ) : (
          <div />
        )}
      </Sheet>

      {/* Übungsmenü */}
      <Sheet open={exerciseMenu !== null} onClose={() => setExerciseMenu(null)} title={exerciseMenu?.exercise.name}>
        <div className="space-y-2">
          <Button
            variant="secondary"
            fullWidth
            onClick={() => {
              const se = exerciseMenu;
              setExerciseMenu(null);
              if (se) openNew(se);
            }}
          >
            <Plus className="h-4 w-4" /> Satz hinzufügen
          </Button>
          <Button
            variant="danger"
            fullWidth
            onClick={() => {
              const se = exerciseMenu;
              setExerciseMenu(null);
              setConfirmRemove(se);
            }}
          >
            <Trash2 className="h-4 w-4" /> Übung aus Training entfernen
          </Button>
        </div>
      </Sheet>

      <Sheet
        open={confirmRemove !== null}
        onClose={() => setConfirmRemove(null)}
        title="Übung entfernen?"
        description={confirmRemove ? `${confirmRemove.exercise.name} und alle ${confirmRemove.sets.length} Sätze werden aus diesem Training entfernt.` : undefined}
        footer={
          <div className="flex gap-2">
            <Button variant="secondary" fullWidth onClick={() => setConfirmRemove(null)}>
              Abbrechen
            </Button>
            <Button variant="danger" fullWidth onClick={removeExercise} loading={busy}>
              Entfernen
            </Button>
          </div>
        }
      >
        <div />
      </Sheet>
    </div>
  );
}
