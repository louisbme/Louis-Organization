"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Copy } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import type { MemberPlan } from "@/lib/supabase/types";
import { copyMemberPlan } from "@/lib/services/stats";
import { friendlyError } from "@/lib/utils/errors";
import { formatTarget } from "@/lib/utils/tracking";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/states";

/** Trainingspläne eines Mitglieds mit der Möglichkeit, sie in die eigenen Pläne zu kopieren. */
export function MemberPlans({ plans, ownerName }: { plans: MemberPlan[]; ownerName: string }) {
  const router = useRouter();
  const [busy, setBusy] = React.useState<string | null>(null);

  const copy = async (plan: MemberPlan) => {
    setBusy(plan.id);
    try {
      const id = await copyMemberPlan(createClient(), plan.id);
      toast.success(`„${plan.name}“ in deine Pläne kopiert`);
      router.push(`/plans/${id}`);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
      setBusy(null);
    }
  };

  if (plans.length === 0) {
    return <EmptyState title="Keine Trainingspläne" description={`${ownerName} hat noch keinen Plan angelegt.`} />;
  }

  return (
    <div className="space-y-3">
      {plans.map((p) => (
        <Card key={p.id} className="px-5 py-4">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="truncate text-base font-semibold">{p.name}</p>
              <p className="text-sm text-muted">
                {p.exercises.length} Übungen · {p.exercises.reduce((s, e) => s + e.target_sets, 0)} Sätze
              </p>
            </div>
            <Button size="sm" variant="secondary" onClick={() => copy(p)} loading={busy === p.id} disabled={busy !== null && busy !== p.id}>
              <Copy className="h-4 w-4" /> Kopieren
            </Button>
          </div>
          {p.exercises.length > 0 ? (
            <ul className="mt-3 space-y-1 text-sm text-muted">
              {p.exercises.slice(0, 5).map((e) => (
                <li key={e.exercise_id} className="flex justify-between gap-3">
                  <span className="truncate">{e.name}</span>
                  <span className="tnum shrink-0 text-faint">
                    {formatTarget(e.tracking_mode ?? "weight_reps", e.target_sets, e.rep_min, e.rep_max, e.target_duration_seconds, e.target_distance_m)}
                  </span>
                </li>
              ))}
              {p.exercises.length > 5 ? <li className="text-xs text-faint">+ {p.exercises.length - 5} weitere</li> : null}
            </ul>
          ) : null}
        </Card>
      ))}
    </div>
  );
}
