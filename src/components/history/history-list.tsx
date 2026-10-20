"use client";

import * as React from "react";
import Link from "next/link";
import { toast } from "sonner";
import { subMonths } from "date-fns";
import { ArrowRight, Filter } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import { listSessions, type SessionListItem } from "@/lib/services/sessions";
import type { TrainedExercise } from "@/lib/services/stats";
import { formatDuration, formatRelativeDay, formatVolume } from "@/lib/utils/format";
import { friendlyError } from "@/lib/utils/errors";
import { Card } from "@/components/ui/card";
import { Select } from "@/components/ui/input";
import { Segmented } from "@/components/ui/segmented";
import { EmptyState, LoadingBlock } from "@/components/ui/states";

type Period = "1m" | "3m" | "12m" | "all";

interface Props {
  initial: SessionListItem[];
  plans: Array<{ id: string; name: string }>;
  exercises: TrainedExercise[];
}

export function HistoryList({ initial, plans, exercises }: Props) {
  const { userId, settings } = useUser();
  const [period, setPeriod] = React.useState<Period>("all");
  const [planId, setPlanId] = React.useState("");
  const [exerciseId, setExerciseId] = React.useState("");
  const [items, setItems] = React.useState<SessionListItem[]>(initial);
  const [loading, setLoading] = React.useState(false);
  const first = React.useRef(true);

  React.useEffect(() => {
    if (first.current) {
      first.current = false;
      return;
    }
    let cancelled = false;
    setLoading(true);
    const from = period === "all" ? undefined : subMonths(new Date(), period === "1m" ? 1 : period === "3m" ? 3 : 12).toISOString();
    listSessions(createClient(), userId, { from, planId: planId || undefined, exerciseId: exerciseId || undefined, limit: 200 })
      .then((rows) => !cancelled && setItems(rows))
      .catch((e) => toast.error(friendlyError(e)))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [period, planId, exerciseId, userId]);

  const grouped = React.useMemo(() => {
    const map = new Map<string, SessionListItem[]>();
    for (const s of items) {
      const d = new Date(s.started_at);
      const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
      map.set(key, [...(map.get(key) ?? []), s]);
    }
    return Array.from(map.entries());
  }, [items]);

  return (
    <div className="space-y-4">
      <Segmented
        value={period}
        onChange={setPeriod}
        options={[
          { value: "1m", label: "1 Monat" },
          { value: "3m", label: "3 Monate" },
          { value: "12m", label: "12 Monate" },
          { value: "all", label: "Alle" },
        ]}
      />
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <Select value={planId} onChange={(e) => setPlanId(e.target.value)} aria-label="Nach Training filtern">
          <option value="">Alle Trainings</option>
          {plans.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </Select>
        <Select value={exerciseId} onChange={(e) => setExerciseId(e.target.value)} aria-label="Nach Übung filtern">
          <option value="">Alle Übungen</option>
          {exercises.map((e) => (
            <option key={e.id} value={e.id}>
              {e.name}
            </option>
          ))}
        </Select>
      </div>

      {loading ? (
        <LoadingBlock />
      ) : items.length === 0 ? (
        <EmptyState icon={<Filter className="h-6 w-6" />} title="Keine Trainings gefunden" description="Für diese Filter gibt es keine abgeschlossenen Trainings." />
      ) : (
        grouped.map(([month, sessions]) => (
          <section key={month}>
            <h2 className="mb-2 px-1 text-[11px] font-semibold uppercase tracking-[0.12em] text-faint">
              {new Date(`${month}-01T00:00:00`).toLocaleDateString("de-DE", { month: "long", year: "numeric" })}
              <span className="ml-2 normal-case tracking-normal">· {sessions.length}</span>
            </h2>
            <Card className="divide-y divide-border overflow-hidden">
              {sessions.map((s) => (
                <Link key={s.id} href={`/history/${s.id}`} className="flex items-center gap-3 px-5 py-3.5 hover:bg-subtle">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">{s.name}</p>
                    <p className="text-xs text-muted">
                      {formatRelativeDay(s.started_at)} · {formatDuration(s.duration_seconds)} · {s.total_sets} Sätze
                    </p>
                    <p className="mt-0.5 truncate text-xs text-faint">{s.exercise_names.join(" · ")}</p>
                  </div>
                  <span className="tnum shrink-0 text-sm text-muted">{formatVolume(s.total_volume, settings.weight_unit)}</span>
                  <ArrowRight className="h-4 w-4 shrink-0 text-faint" />
                </Link>
              ))}
            </Card>
          </section>
        ))
      )}
    </div>
  );
}
