"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Play, ChevronRight } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import type { PlanWithExercises } from "@/lib/services/plans";
import { startSession } from "@/lib/services/sessions";
import { friendlyError } from "@/lib/utils/errors";
import { cn } from "@/lib/utils/cn";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { EmptyState } from "@/components/ui/states";

interface Props {
  plans: PlanWithExercises[];
  nextPlanId: string | null;
  preselectPlanId: string | null;
}

export function WorkoutStartList({ plans, nextPlanId, preselectPlanId }: Props) {
  const router = useRouter();
  const [starting, setStarting] = React.useState<string | null>(null);

  const start = async (planId: string) => {
    setStarting(planId);
    try {
      const id = await startSession(createClient(), planId);
      router.push(`/workout/${id}`);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
      setStarting(null);
    }
  };

  if (plans.length === 0) {
    return (
      <EmptyState
        title="Noch kein Trainingsplan"
        description="Lege zuerst ein Training mit Übungen an."
        action={
          <Link href="/plans">
            <Button>Plan erstellen</Button>
          </Link>
        }
      />
    );
  }

  return (
    <div className="stagger space-y-3">
      {plans.map((p) => {
        const isNext = p.id === (preselectPlanId ?? nextPlanId);
        return (
          <Card key={p.id} className={cn("overflow-hidden", isNext && "border-accent/40")}>
            <div className="flex items-start justify-between gap-3 px-5 pt-5">
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <h2 className="truncate text-lg font-semibold">{p.name}</h2>
                  {isNext ? <Badge tone="accent">Als Nächstes</Badge> : null}
                </div>
                <p className="mt-0.5 text-sm text-muted">
                  {p.exercises.length} Übungen · {p.exercises.reduce((s, e) => s + e.target_sets, 0)} Sätze
                </p>
              </div>
              <Link href={`/plans/${p.id}`} className="shrink-0 text-xs font-medium text-muted hover:text-fg">
                Bearbeiten
              </Link>
            </div>
            {p.exercises.length > 0 ? (
              <ul className="mt-3 space-y-1 px-5 text-sm text-muted">
                {p.exercises.slice(0, 4).map((e) => (
                  <li key={e.id} className="flex justify-between gap-3">
                    <span className="truncate">{e.exercise.name}</span>
                    <span className="tnum shrink-0 text-faint">
                      {e.target_sets} × {e.rep_min}–{e.rep_max}
                    </span>
                  </li>
                ))}
                {p.exercises.length > 4 ? <li className="text-xs text-faint">+ {p.exercises.length - 4} weitere</li> : null}
              </ul>
            ) : null}
            <div className="px-5 pb-5 pt-4">
              <Button
                fullWidth
                size="lg"
                variant={isNext ? "primary" : "secondary"}
                onClick={() => start(p.id)}
                loading={starting === p.id}
                disabled={p.exercises.length === 0 || (starting !== null && starting !== p.id)}
              >
                <Play className="h-4 w-4" /> Starten
              </Button>
            </div>
          </Card>
        );
      })}
      <Link href="/plans" className="flex items-center justify-between rounded-[var(--radius-card)] border border-border bg-card px-5 py-4 text-sm font-medium hover:bg-subtle">
        Trainingspläne verwalten <ChevronRight className="h-4 w-4 text-faint" />
      </Link>
    </div>
  );
}
