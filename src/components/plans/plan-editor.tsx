"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { ArrowDown, ArrowUp, Check, Copy, MoreHorizontal, Pencil, Play, Plus, Repeat, Trash2, X } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import type { ExerciseListItem } from "@/lib/services/exercises";
import {
  addPlanExercise,
  deletePlan,
  duplicatePlan,
  removePlanExercise,
  renamePlan,
  reorderPlanExercises,
  updatePlanExercise,
  type PlanExerciseWithExercise,
  type PlanWithExercises,
} from "@/lib/services/plans";
import { startSession } from "@/lib/services/sessions";
import { friendlyError } from "@/lib/utils/errors";
import { CATEGORY_LABELS, EQUIPMENT_LABELS } from "@/lib/utils/labels";
import { cn } from "@/lib/utils/cn";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Sheet } from "@/components/ui/sheet";
import { Input } from "@/components/ui/input";
import { EmptyState } from "@/components/ui/states";
import { EquipmentIcon } from "@/components/exercise/equipment-icon";
import { ExercisePickerSheet } from "@/components/exercise/exercise-picker-sheet";

export function PlanEditor({ plan: initial }: { plan: PlanWithExercises }) {
  const router = useRouter();
  const { userId } = useUser();
  const db = React.useMemo(() => createClient(), []);
  const [plan, setPlan] = React.useState(initial);
  const [editingName, setEditingName] = React.useState(false);
  const [name, setName] = React.useState(initial.name);
  const [picker, setPicker] = React.useState<{ mode: "add" } | { mode: "replace"; id: string } | null>(null);
  const [menu, setMenu] = React.useState(false);
  const [confirmDelete, setConfirmDelete] = React.useState(false);
  const [busy, setBusy] = React.useState<string | null>(null);

  React.useEffect(() => setPlan(initial), [initial]);

  const saveName = async () => {
    const next = name.trim();
    if (!next || next === plan.name) {
      setName(plan.name);
      setEditingName(false);
      return;
    }
    try {
      await renamePlan(db, plan.id, next);
      setPlan((p) => ({ ...p, name: next }));
      setEditingName(false);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    }
  };

  const move = async (index: number, dir: -1 | 1) => {
    const target = index + dir;
    if (target < 0 || target >= plan.exercises.length) return;
    const list = [...plan.exercises];
    [list[index], list[target]] = [list[target], list[index]];
    const reordered = list.map((e, i) => ({ ...e, sort_order: i + 1 }));
    setPlan((p) => ({ ...p, exercises: reordered }));
    try {
      await reorderPlanExercises(db, reordered.map((e) => e.id));
    } catch (e) {
      toast.error(friendlyError(e));
      setPlan(initial);
    }
  };

  const updateTargets = async (pe: PlanExerciseWithExercise, patch: Partial<Pick<PlanExerciseWithExercise, "target_sets" | "rep_min" | "rep_max">>) => {
    const next = { ...pe, ...patch };
    if (next.rep_min > next.rep_max) {
      if (patch.rep_min !== undefined) next.rep_max = next.rep_min;
      else next.rep_min = next.rep_max;
    }
    next.target_sets = clamp(next.target_sets, 1, 10);
    next.rep_min = clamp(next.rep_min, 1, 100);
    next.rep_max = clamp(next.rep_max, 1, 100);
    setPlan((p) => ({ ...p, exercises: p.exercises.map((e) => (e.id === pe.id ? next : e)) }));
    try {
      await updatePlanExercise(db, pe.id, { target_sets: next.target_sets, rep_min: next.rep_min, rep_max: next.rep_max });
    } catch (e) {
      toast.error(friendlyError(e));
    }
  };

  const remove = async (pe: PlanExerciseWithExercise) => {
    setPlan((p) => ({ ...p, exercises: p.exercises.filter((e) => e.id !== pe.id) }));
    try {
      await removePlanExercise(db, pe.id);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
      setPlan(initial);
    }
  };

  const onPick = async (item: ExerciseListItem) => {
    const current = picker;
    setPicker(null);
    if (!current) return;
    try {
      if (current.mode === "add") {
        const order = (plan.exercises[plan.exercises.length - 1]?.sort_order ?? 0) + 1;
        const row = await addPlanExercise(db, plan.id, item.id, { target_sets: 3, rep_min: 8, rep_max: 12 }, order);
        setPlan((p) => ({
          ...p,
          exercises: [...p.exercises, { ...row, exercise: { id: item.id, slug: item.slug, name: item.name, category: item.category, equipment: item.equipment, image_url: item.image_url, is_custom: item.is_custom } }],
        }));
        toast.success(`${item.name} hinzugefügt`);
      } else {
        await updatePlanExercise(db, current.id, { exercise_id: item.id });
        setPlan((p) => ({
          ...p,
          exercises: p.exercises.map((e) =>
            e.id === current.id
              ? { ...e, exercise_id: item.id, exercise: { id: item.id, slug: item.slug, name: item.name, category: item.category, equipment: item.equipment, image_url: item.image_url, is_custom: item.is_custom } }
              : e
          ),
        }));
        toast.success(`Ersetzt durch ${item.name}`);
      }
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    }
  };

  const duplicate = async () => {
    setBusy("dup");
    try {
      const id = await duplicatePlan(db, userId, plan.id);
      toast.success("Training dupliziert");
      router.push(`/plans/${id}`);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
      setBusy(null);
    }
  };

  const destroy = async () => {
    setBusy("delete");
    try {
      await deletePlan(db, plan.id);
      toast.success("Training gelöscht");
      router.push("/plans");
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
      setBusy(null);
    }
  };

  const start = async () => {
    setBusy("start");
    try {
      const id = await startSession(db, plan.id);
      router.push(`/workout/${id}`);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
      setBusy(null);
    }
  };

  return (
    <div className="space-y-4">
      {/* Name */}
      <div className="flex items-center gap-2">
        {editingName ? (
          <>
            <Input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} autoFocus onKeyDown={(e) => e.key === "Enter" && saveName()} />
            <Button size="icon" variant="secondary" onClick={saveName} aria-label="Speichern">
              <Check className="h-4 w-4" />
            </Button>
            <Button size="icon" variant="ghost" onClick={() => { setName(plan.name); setEditingName(false); }} aria-label="Abbrechen">
              <X className="h-4 w-4" />
            </Button>
          </>
        ) : (
          <>
            <h1 className="min-w-0 flex-1 truncate text-2xl font-semibold tracking-tight sm:text-3xl">{plan.name}</h1>
            <Button size="icon" variant="ghost" onClick={() => setEditingName(true)} aria-label="Umbenennen">
              <Pencil className="h-4 w-4" />
            </Button>
            <Button size="icon" variant="ghost" onClick={() => setMenu(true)} aria-label="Mehr">
              <MoreHorizontal className="h-5 w-5" />
            </Button>
          </>
        )}
      </div>
      <p className="-mt-2 text-sm text-muted">
        {plan.exercises.length} Übungen · {plan.exercises.reduce((s, e) => s + e.target_sets, 0)} Sätze
      </p>

      {/* Übungen */}
      {plan.exercises.length === 0 ? (
        <EmptyState title="Noch keine Übungen" description="Füge Übungen aus der Datenbank hinzu." action={<Button onClick={() => setPicker({ mode: "add" })}><Plus className="h-4 w-4" /> Übung hinzufügen</Button>} />
      ) : (
        <div className="space-y-3">
          {plan.exercises.map((pe, index) => (
            <Card key={pe.id} className="overflow-hidden">
              <div className="flex items-start gap-3 px-4 pt-4">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-subtle text-muted">
                  <EquipmentIcon equipment={pe.exercise.equipment} className="h-5 w-5" strokeWidth={1.7} />
                </div>
                <div className="min-w-0 flex-1">
                  <Link href={`/exercises/${pe.exercise.slug}`} className="block truncate text-sm font-medium hover:text-accent">
                    {pe.exercise.name}
                  </Link>
                  <p className="truncate text-xs text-muted">
                    {CATEGORY_LABELS[pe.exercise.category]} · {EQUIPMENT_LABELS[pe.exercise.equipment]}
                  </p>
                </div>
                <div className="flex shrink-0 items-center">
                  <IconBtn label="Nach oben" disabled={index === 0} onClick={() => move(index, -1)}><ArrowUp className="h-4 w-4" /></IconBtn>
                  <IconBtn label="Nach unten" disabled={index === plan.exercises.length - 1} onClick={() => move(index, 1)}><ArrowDown className="h-4 w-4" /></IconBtn>
                  <IconBtn label="Übung austauschen" onClick={() => setPicker({ mode: "replace", id: pe.id })}><Repeat className="h-4 w-4" /></IconBtn>
                  <IconBtn label="Entfernen" onClick={() => remove(pe)} tone="danger"><Trash2 className="h-4 w-4" /></IconBtn>
                </div>
              </div>
              <div className="mt-3 grid grid-cols-3 divide-x divide-border border-t border-border">
                <NumberCell label="Sätze" value={pe.target_sets} onChange={(v) => updateTargets(pe, { target_sets: v })} min={1} max={10} />
                <NumberCell label="Wdh min" value={pe.rep_min} onChange={(v) => updateTargets(pe, { rep_min: v })} min={1} max={100} />
                <NumberCell label="Wdh max" value={pe.rep_max} onChange={(v) => updateTargets(pe, { rep_max: v })} min={1} max={100} />
              </div>
            </Card>
          ))}
          <Button variant="secondary" fullWidth onClick={() => setPicker({ mode: "add" })}>
            <Plus className="h-4 w-4" /> Übung hinzufügen
          </Button>
        </div>
      )}

      {plan.exercises.length > 0 ? (
        <div className="pt-2">
          <Button size="lg" fullWidth onClick={start} loading={busy === "start"}>
            <Play className="h-4 w-4" /> Training starten
          </Button>
        </div>
      ) : null}

      <ExercisePickerSheet
        open={picker !== null}
        onClose={() => setPicker(null)}
        onPick={onPick}
        title={picker?.mode === "replace" ? "Übung austauschen" : "Übung hinzufügen"}
      />

      <Sheet open={menu} onClose={() => setMenu(false)} title={plan.name}>
        <div className="space-y-2">
          <Button variant="secondary" fullWidth onClick={() => { setMenu(false); duplicate(); }} loading={busy === "dup"}>
            <Copy className="h-4 w-4" /> Training duplizieren
          </Button>
          <Button variant="danger" fullWidth onClick={() => { setMenu(false); setConfirmDelete(true); }}>
            <Trash2 className="h-4 w-4" /> Training löschen
          </Button>
        </div>
      </Sheet>

      <Sheet
        open={confirmDelete}
        onClose={() => setConfirmDelete(false)}
        title="Training löschen?"
        description="Abgeschlossene Trainings in der Historie bleiben erhalten."
        footer={
          <div className="flex gap-2">
            <Button variant="secondary" fullWidth onClick={() => setConfirmDelete(false)}>Abbrechen</Button>
            <Button variant="danger" fullWidth onClick={destroy} loading={busy === "delete"}>Löschen</Button>
          </div>
        }
      >
        <div />
      </Sheet>
    </div>
  );
}

function clamp(v: number, min: number, max: number) {
  return Math.min(max, Math.max(min, Math.round(v)));
}

function IconBtn({ label, onClick, disabled, children, tone }: { label: string; onClick: () => void; disabled?: boolean; children: React.ReactNode; tone?: "danger" }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={onClick}
      className={cn(
        "flex h-9 w-9 items-center justify-center rounded-lg transition-colors disabled:opacity-30 touch-manipulation",
        tone === "danger" ? "text-faint hover:bg-danger-soft hover:text-danger" : "text-faint hover:bg-subtle hover:text-fg"
      )}
    >
      {children}
    </button>
  );
}

function NumberCell({ label, value, onChange, min, max }: { label: string; value: number; onChange: (v: number) => void; min: number; max: number }) {
  return (
    <div className="flex flex-col items-center py-2">
      <span className="text-[10px] font-medium uppercase tracking-wider text-faint">{label}</span>
      <div className="mt-1 flex items-center gap-1">
        <button type="button" aria-label={`${label} verringern`} disabled={value <= min} onClick={() => onChange(value - 1)} className="flex h-9 w-9 items-center justify-center rounded-lg text-muted hover:bg-subtle disabled:opacity-30 touch-manipulation">
          –
        </button>
        <span className="tnum w-8 text-center text-lg font-semibold">{value}</span>
        <button type="button" aria-label={`${label} erhöhen`} disabled={value >= max} onClick={() => onChange(value + 1)} className="flex h-9 w-9 items-center justify-center rounded-lg text-muted hover:bg-subtle disabled:opacity-30 touch-manipulation">
          +
        </button>
      </div>
    </div>
  );
}
