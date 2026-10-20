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
        <Card className="divide-y divide-border overflow-hidden">
          {plans.map((p, index) => (
            <div key={p.id} className="flex items-center gap-2 pr-2">
              <Link href={`/plans/${p.id}`} className="flex min-w-0 flex-1 items-center gap-4 px-5 py-4 hover:bg-subtle">
                <span className="tnum flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-subtle text-sm font-semibold text-muted">
                  {String.fromCharCode(65 + (index % 26))}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">{p.name}</p>
                  <p className="truncate text-xs text-muted">
                    {p.exercises.length} Übungen · {p.exercises.reduce((s, e) => s + e.target_sets, 0)} Sätze
                  </p>
                </div>
                <ChevronRight className="h-4 w-4 shrink-0 text-faint" />
              </Link>
              <Button
                variant="ghost"
                size="icon"
                aria-label="Duplizieren"
                title="Duplizieren"
                loading={dup === p.id}
                onClick={() => duplicate(p.id)}
              >
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
