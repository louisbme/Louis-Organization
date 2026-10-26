"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Star, Plus, Pencil, Trash2, Check } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import { setFavorite, deleteCustomExercise } from "@/lib/services/exercises";
import { listPlans, addPlanExercise, type PlanWithExercises } from "@/lib/services/plans";
import { friendlyError } from "@/lib/utils/errors";
import { cn } from "@/lib/utils/cn";
import { Button } from "@/components/ui/button";
import { Sheet } from "@/components/ui/sheet";
import { LoadingBlock } from "@/components/ui/states";

export function FavoriteButton({ exerciseId, initial }: { exerciseId: string; initial: boolean }) {
  const { userId } = useUser();
  const [fav, setFav] = React.useState(initial);
  const [busy, setBusy] = React.useState(false);

  const toggle = async () => {
    const next = !fav;
    setFav(next);
    setBusy(true);
    try {
      await setFavorite(createClient(), userId, exerciseId, next);
    } catch (e) {
      setFav(!next);
      toast.error(friendlyError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Button variant="secondary" size="icon" onClick={toggle} disabled={busy} aria-pressed={fav} aria-label={fav ? "Favorit entfernen" : "Als Favorit markieren"}>
      <Star className={cn("h-5 w-5", fav ? "fill-current text-accent" : "")} />
    </Button>
  );
}

export function AddToPlanButton({ exerciseId, exerciseName }: { exerciseId: string; exerciseName: string }) {
  const { userId } = useUser();
  const [open, setOpen] = React.useState(false);
  const [plans, setPlans] = React.useState<PlanWithExercises[] | null>(null);
  const [adding, setAdding] = React.useState<string | null>(null);

  React.useEffect(() => {
    if (!open || plans) return;
    listPlans(createClient(), userId)
      .then(setPlans)
      .catch((e) => toast.error(friendlyError(e)));
  }, [open, plans, userId]);

  const add = async (plan: PlanWithExercises) => {
    setAdding(plan.id);
    try {
      const nextOrder = (plan.exercises[plan.exercises.length - 1]?.sort_order ?? 0) + 1;
      await addPlanExercise(createClient(), plan.id, exerciseId, { target_sets: 3, rep_min: 8, rep_max: 12 }, nextOrder);
      toast.success(`${exerciseName} zu „${plan.name}“ hinzugefügt`);
      setPlans(null);
      setOpen(false);
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setAdding(null);
    }
  };

  return (
    <>
      <Button size="lg" fullWidth onClick={() => setOpen(true)}>
        <Plus className="h-4 w-4" /> Zu Training hinzufügen
      </Button>
      <Sheet open={open} onClose={() => setOpen(false)} title="Zu welchem Training?" description="Die Übung wird mit 3 × 8–12 angelegt und kann im Plan angepasst werden.">
        {plans === null ? (
          <LoadingBlock />
        ) : plans.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted">
            Noch kein Trainingsplan vorhanden.{" "}
            <Link href="/plans" className="text-accent">
              Plan erstellen
            </Link>
          </p>
        ) : (
          <ul className="divide-y divide-border overflow-hidden rounded-[var(--radius-control)] bg-subtle">
            {plans.map((p) => {
              const contains = p.exercises.some((e) => e.exercise_id === exerciseId);
              return (
                <li key={p.id}>
                  <button
                    type="button"
                    disabled={!!adding}
                    onClick={() => add(p)}
                    className="flex min-h-14 w-full items-center justify-between gap-3 px-4 py-3 text-left hover:bg-subtle disabled:opacity-60"
                  >
                    <div>
                      <p className="text-sm font-medium">{p.name}</p>
                      <p className="text-xs text-muted">
                        {p.exercises.length} Übungen{contains ? " · bereits enthalten" : ""}
                      </p>
                    </div>
                    {contains ? <Check className="h-4 w-4 text-accent" /> : <Plus className="h-4 w-4 text-faint" />}
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </Sheet>
    </>
  );
}

export function CustomExerciseActions({ exerciseId, slug }: { exerciseId: string; slug: string }) {
  const router = useRouter();
  const [confirm, setConfirm] = React.useState(false);
  const [busy, setBusy] = React.useState(false);

  const remove = async () => {
    setBusy(true);
    try {
      await deleteCustomExercise(createClient(), exerciseId);
      toast.success("Übung gelöscht");
      router.push("/exercises");
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
      setBusy(false);
      setConfirm(false);
    }
  };

  return (
    <div className="flex gap-2">
      <Link href={`/exercises/${slug}/edit`} className="flex-1">
        <Button variant="secondary" fullWidth>
          <Pencil className="h-4 w-4" /> Bearbeiten
        </Button>
      </Link>
      <Button variant="danger" onClick={() => setConfirm(true)}>
        <Trash2 className="h-4 w-4" /> Löschen
      </Button>
      <Sheet
        open={confirm}
        onClose={() => setConfirm(false)}
        title="Übung löschen?"
        description="Die Übung wird aus deinen Plänen entfernt. Übungen, die bereits in Trainings verwendet wurden, können nicht gelöscht werden."
        footer={
          <div className="flex gap-2">
            <Button variant="secondary" fullWidth onClick={() => setConfirm(false)}>
              Abbrechen
            </Button>
            <Button variant="danger" fullWidth loading={busy} onClick={remove}>
              Löschen
            </Button>
          </div>
        }
      >
        <div />
      </Sheet>
    </div>
  );
}
