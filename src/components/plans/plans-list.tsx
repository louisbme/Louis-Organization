"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { ChevronRight, Copy, Plus } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import { createPlan, duplicatePlan, type PlanWithExercises } from "@/lib/services/plans";
import { friendlyError } from "@/lib/utils/errors";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Sheet } from "@/components/ui/sheet";
import { Input } from "@/components/ui/input";
import { Field } from "@/components/ui/field";
import { EmptyState } from "@/components/ui/states";

export function PlansList({ plans }: { plans: PlanWithExercises[] }) {
  const router = useRouter();
  const { userId } = useUser();
  const [open, setOpen] = React.useState(false);
  const [name, setName] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [dup, setDup] = React.useState<string | null>(null);

  const create = async (e: React.FormEvent) => {
    e.preventDefault();
    if (name.trim().length === 0) return;
    setBusy(true);
    try {
      const id = await createPlan(createClient(), userId, name);
      setOpen(false);
      setName("");
      router.push(`/plans/${id}`);
      router.refresh();
    } catch (err) {
      toast.error(friendlyError(err));
    } finally {
      setBusy(false);
    }
  };

  const duplicate = async (planId: string) => {
    setDup(planId);
    try {
      await duplicatePlan(createClient(), userId, planId);
      toast.success("Training dupliziert");
      router.refresh();
    } catch (err) {
      toast.error(friendlyError(err));
    } finally {
      setDup(null);
    }
  };

  return (
    <div className="space-y-4">
      {plans.length === 0 ? (
        <EmptyState
          title="Noch kein Trainingsplan"
          description="Erstelle ein Training und füge Übungen hinzu."
          action={
            <Button onClick={() => setOpen(true)}>
              <Plus className="h-4 w-4" /> Neues Training
            </Button>
          }
        />
      ) : (
        <Card className="overflow-hidden">
          {plans.map((p, index) => (
            <div
              key={p.id}
              className="relative flex items-center gap-1 pr-2 after:absolute after:bottom-0 after:left-[68px] after:right-0 after:h-px after:bg-border after:content-[''] last:after:hidden"
            >
              <Link href={`/plans/${p.id}`} className="press flex min-h-[60px] min-w-0 flex-1 items-center gap-3 px-4 py-2 hover:bg-subtle">
                <span className="display tnum flex h-10 w-10 shrink-0 items-center justify-center rounded-[10px] bg-subtle text-base text-fg">
                  {String.fromCharCode(65 + (index % 26))}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-base text-fg">{p.name}</p>
                  <p className="truncate text-sm text-muted">
                    {p.exercises.length} Übungen · {p.exercises.reduce((s, e) => s + e.target_sets, 0)} Sätze
                  </p>
                </div>
                <ChevronRight className="h-4 w-4 shrink-0 text-faint" strokeWidth={2.4} />
              </Link>
              <Button variant="ghost" size="icon-sm" aria-label="Duplizieren" title="Duplizieren" loading={dup === p.id} onClick={() => duplicate(p.id)}>
                {dup === p.id ? null : <Copy className="h-4 w-4" />}
              </Button>
            </div>
          ))}
        </Card>
      )}

      {plans.length > 0 ? (
        <Button variant="secondary" fullWidth onClick={() => setOpen(true)}>
          <Plus className="h-4 w-4" /> Neues Training
        </Button>
      ) : null}

      <Sheet open={open} onClose={() => setOpen(false)} title="Neues Training">
        <form onSubmit={create} className="space-y-4">
          <Field label="Name" htmlFor="planName">
            <Input id="planName" value={name} onChange={(e) => setName(e.target.value)} maxLength={60} autoFocus placeholder="z. B. Ganzkörper" />
          </Field>
          <Button type="submit" fullWidth loading={busy} disabled={name.trim().length === 0}>
            Erstellen
          </Button>
        </form>
      </Sheet>
    </div>
  );
}
