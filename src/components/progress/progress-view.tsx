"use client";

import * as React from "react";
import { toast } from "sonner";
import { subMonths, subWeeks, startOfWeek, format } from "date-fns";
import { de } from "date-fns/locale";
import { Plus, Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import type { ExerciseHistoryRow, ExerciseRecordsRow } from "@/lib/supabase/types";
import {
  deleteBodyWeight,
  getExerciseHistory,
  getExerciseRecords,
  getSessionPoints,
  listBodyWeight,
  upsertBodyWeight,
  type BodyWeightPoint,
  type SessionPoint,
  type TrainedExercise,
} from "@/lib/services/stats";
import { formatDate, formatDecimal, formatDuration, formatVolume, formatWeight, toDateKey } from "@/lib/utils/format";
import { friendlyError } from "@/lib/utils/errors";
import { Segmented } from "@/components/ui/segmented";
import { Card, CardContent, SectionLabel } from "@/components/ui/card";
import { Select, Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Sheet } from "@/components/ui/sheet";
import { Field } from "@/components/ui/field";
import { TrendChart, type TrendPoint } from "@/components/charts/trend-chart";

type Period = "1w" | "1m" | "6m" | "12m" | "all";

const PERIOD_OPTIONS: Array<{ value: Period; label: string }> = [
  { value: "1w", label: "1 W" },
  { value: "1m", label: "1 M" },
  { value: "6m", label: "6 M" },
  { value: "12m", label: "12 M" },
  { value: "all", label: "Gesamt" },
];

function periodStart(p: Period): string | null {
  const now = new Date();
  switch (p) {
    case "1w":
      return subWeeks(now, 1).toISOString();
    case "1m":
      return subMonths(now, 1).toISOString();
    case "6m":
      return subMonths(now, 6).toISOString();
    case "12m":
      return subMonths(now, 12).toISOString();
    default:
      return null;
  }
}

interface Props {
  exercises: TrainedExercise[];
  initialPoints: SessionPoint[];
  initialBodyWeight: BodyWeightPoint[];
}

export function ProgressView({ exercises, initialPoints, initialBodyWeight }: Props) {
  const { userId, settings } = useUser();
  const unit = settings.weight_unit;
  const db = React.useMemo(() => createClient(), []);
  const [period, setPeriod] = React.useState<Period>("12m");
  const [points, setPoints] = React.useState(initialPoints);
  const [bodyWeight, setBodyWeight] = React.useState(initialBodyWeight);
  const [exerciseId, setExerciseId] = React.useState(exercises[0]?.id ?? "");
  const [history, setHistory] = React.useState<ExerciseHistoryRow[]>([]);
  const [records, setRecords] = React.useState<ExerciseRecordsRow | null>(null);
  const [bwOpen, setBwOpen] = React.useState(false);
  const [bwValue, setBwValue] = React.useState("");
  const [bwDate, setBwDate] = React.useState(toDateKey(new Date()));
  const [busy, setBusy] = React.useState(false);
  const firstRun = React.useRef(true);

  React.useEffect(() => {
    if (firstRun.current) {
      firstRun.current = false;
      return;
    }
    const from = periodStart(period);
    Promise.all([getSessionPoints(db, userId, from), listBodyWeight(db, userId, from)])
      .then(([p, bw]) => {
        setPoints(p);
        setBodyWeight(bw);
      })
      .catch((e) => toast.error(friendlyError(e)));
  }, [period, db, userId]);

  React.useEffect(() => {
    if (!exerciseId) return;
    let cancelled = false;
    Promise.all([getExerciseHistory(db, exerciseId, periodStart(period)), getExerciseRecords(db, exerciseId)])
      .then(([h, r]) => {
        if (cancelled) return;
        setHistory(h);
        setRecords(r);
      })
      .catch((e) => toast.error(friendlyError(e)));
    return () => {
      cancelled = true;
    };
  }, [exerciseId, period, db]);

  const volumeData: TrendPoint[] = points.map((p) => ({
    x: formatDate(p.started_at, "d.M."),
    label: formatDate(p.started_at, "EEE, d. MMM yyyy"),
    y: p.total_volume,
    extra: `${p.total_sets} Sätze`,
  }));

  const weekly = React.useMemo(() => {
    const map = new Map<string, { count: number; duration: number; date: Date }>();
    for (const p of points) {
      const ws = startOfWeek(new Date(p.started_at), { weekStartsOn: 1 });
      const key = toDateKey(ws);
      const cur = map.get(key) ?? { count: 0, duration: 0, date: ws };
      cur.count += 1;
      cur.duration += p.duration_seconds;
      map.set(key, cur);
    }
    return Array.from(map.values()).sort((a, b) => a.date.getTime() - b.date.getTime());
  }, [points]);

  const countData: TrendPoint[] = weekly.map((w) => ({
    x: format(w.date, "d.M.", { locale: de }),
    label: `Woche ab ${format(w.date, "d. MMM", { locale: de })}`,
    y: w.count,
  }));

  const durationData: TrendPoint[] = points.map((p) => ({
    x: formatDate(p.started_at, "d.M."),
    label: formatDate(p.started_at, "EEE, d. MMM yyyy"),
    y: Math.round(p.duration_seconds / 60),
  }));

  const bwData: TrendPoint[] = bodyWeight.map((b) => ({
    x: formatDate(b.entry_date, "d.M."),
    label: formatDate(b.entry_date, "d. MMM yyyy"),
    y: b.weight,
  }));

  const exWeight: TrendPoint[] = history.map((h) => ({
    x: formatDate(h.started_at, "d.M."),
    label: formatDate(h.started_at, "EEE, d. MMM yyyy"),
    y: h.top_set_weight,
    extra: `Top-Satz ${formatWeight(h.top_set_weight, unit)} × ${h.top_set_reps} · ${h.sets} Sätze`,
  }));
  const exReps: TrendPoint[] = history.map((h) => ({
    x: formatDate(h.started_at, "d.M."),
    label: formatDate(h.started_at, "EEE, d. MMM yyyy"),
    y: h.max_reps,
    extra: `bei max. ${formatWeight(h.max_weight, unit)}`,
  }));
  const ex1rm: TrendPoint[] = history.map((h) => ({
    x: formatDate(h.started_at, "d.M."),
    label: formatDate(h.started_at, "EEE, d. MMM yyyy"),
    y: h.est_1rm,
  }));
  const exVolume: TrendPoint[] = history.map((h) => ({
    x: formatDate(h.started_at, "d.M."),
    label: formatDate(h.started_at, "EEE, d. MMM yyyy"),
    y: h.volume,
  }));

  const totalVolume = points.reduce((s, p) => s + p.total_volume, 0);
  const totalDuration = points.reduce((s, p) => s + p.duration_seconds, 0);

  const saveBw = async (e: React.FormEvent) => {
    e.preventDefault();
    const v = parseFloat(bwValue.replace(",", "."));
    if (!v || v <= 0 || v >= 500) {
      toast.error("Bitte ein gültiges Gewicht eingeben.");
      return;
    }
    setBusy(true);
    try {
      await upsertBodyWeight(db, userId, bwDate, v);
      setBodyWeight(await listBodyWeight(db, userId, periodStart(period)));
      setBwOpen(false);
      setBwValue("");
      toast.success("Körpergewicht gespeichert");
    } catch (err) {
      toast.error(friendlyError(err));
    } finally {
      setBusy(false);
    }
  };

  const removeBw = async (id: string) => {
    try {
      await deleteBodyWeight(db, id);
      setBodyWeight((list) => list.filter((b) => b.id !== id));
    } catch (err) {
      toast.error(friendlyError(err));
    }
  };

  return (
    <div className="space-y-5">
      <Segmented value={period} onChange={setPeriod} options={PERIOD_OPTIONS} />

      <div className="grid grid-cols-3 gap-3">
        <Mini label="Trainings" value={String(points.length)} />
        <Mini label="Zeit" value={formatDuration(totalDuration)} />
        <Mini label="Volumen" value={formatVolume(totalVolume, unit)} />
      </div>

      <ChartCard title="Trainingsvolumen" subtitle="Summe Gewicht × Wiederholungen je Training">
        <TrendChart data={volumeData} type="bar" formatValue={(v) => formatVolume(v, unit)} />
      </ChartCard>

      <ChartCard title="Trainingsanzahl" subtitle="Trainings pro Woche">
        <TrendChart data={countData} type="bar" color="var(--chart-2)" formatValue={(v) => `${v} Training${v === 1 ? "" : "s"}`} />
      </ChartCard>

      <ChartCard title="Trainingsdauer" subtitle="Minuten je Training">
        <TrendChart data={durationData} type="line" color="var(--chart-3)" formatValue={(v) => `${v} min`} />
      </ChartCard>

      <ChartCard
        title="Körpergewicht"
        subtitle="Optional, manuell eingetragen"
        action={
          <Button size="sm" variant="secondary" onClick={() => setBwOpen(true)}>
            <Plus className="h-4 w-4" /> Eintrag
          </Button>
        }
      >
        <TrendChart data={bwData} type="line" color="var(--chart-4)" formatValue={(v) => `${formatDecimal(v)} ${unit}`} emptyLabel="Noch kein Körpergewicht eingetragen" />
        {bodyWeight.length > 0 ? (
          <ul className="mt-3 divide-y divide-border text-sm">
            {[...bodyWeight].reverse().slice(0, 5).map((b) => (
              <li key={b.id} className="flex items-center justify-between py-2">
                <span className="text-muted">{formatDate(b.entry_date)}</span>
                <span className="tnum flex items-center gap-3 font-medium">
                  {formatDecimal(b.weight)} {unit}
                  <button type="button" onClick={() => removeBw(b.id)} className="text-faint hover:text-danger" aria-label="Eintrag löschen">
                    <Trash2 className="h-4 w-4" />
                  </button>
                </span>
              </li>
            ))}
          </ul>
        ) : null}
      </ChartCard>

      {/* Einzelne Übung */}
      <Card>
        <CardContent className="pt-5">
          <SectionLabel>Kraftentwicklung je Übung</SectionLabel>
          {exercises.length === 0 ? (
            <p className="mt-2 text-sm text-muted">Nach dem ersten Training erscheinen hier deine Übungen.</p>
          ) : (
            <>
              <div className="mt-3">
                <Select value={exerciseId} onChange={(e) => setExerciseId(e.target.value)} aria-label="Übung wählen">
                  {exercises.map((e) => (
                    <option key={e.id} value={e.id}>
                      {e.name} ({e.sessions})
                    </option>
                  ))}
                </Select>
              </div>

              {records ? (
                <div className="mt-4 grid grid-cols-2 gap-2">
                  <Mini label="Schwerstes Gewicht" value={records.max_weight !== null ? `${formatWeight(records.max_weight, unit)} × ${records.max_weight_reps}` : "–"} />
                  <Mini label="Meiste Wdh" value={records.max_reps !== null ? `${records.max_reps} × ${formatWeight(records.max_reps_weight ?? 0, unit)}` : "–"} />
                  <Mini label="Gesch. 1RM" value={records.best_est_1rm !== null ? formatWeight(records.best_est_1rm, unit) : "–"} />
                  <Mini label="Bestes Volumen" value={records.max_session_volume !== null ? formatVolume(records.max_session_volume, unit) : "–"} />
                </div>
              ) : null}

              <div className="mt-5 space-y-6">
                <div>
                  <p className="mb-2 text-sm font-medium">Gewicht über Zeit (Top-Satz)</p>
                  <TrendChart data={exWeight} type="line" formatValue={(v) => formatWeight(v, unit)} />
                </div>
                <div>
                  <p className="mb-2 text-sm font-medium">Wiederholungen (max. je Training)</p>
                  <TrendChart data={exReps} type="bar" color="var(--chart-2)" formatValue={(v) => `${v} Wdh`} />
                </div>
                <div>
                  <p className="mb-2 text-sm font-medium">Geschätztes 1RM</p>
                  <TrendChart data={ex1rm} type="line" color="var(--chart-3)" formatValue={(v) => formatWeight(v, unit)} />
                </div>
                <div>
                  <p className="mb-2 text-sm font-medium">Volumen je Training</p>
                  <TrendChart data={exVolume} type="bar" color="var(--chart-4)" formatValue={(v) => formatVolume(v, unit)} />
                </div>
              </div>
            </>
          )}
        </CardContent>
      </Card>

      <Sheet open={bwOpen} onClose={() => setBwOpen(false)} title="Körpergewicht eintragen">
        <form onSubmit={saveBw} className="space-y-4">
          <Field label="Datum" htmlFor="bwDate">
            <Input id="bwDate" type="date" value={bwDate} onChange={(e) => setBwDate(e.target.value)} max={toDateKey(new Date())} />
          </Field>
          <Field label={`Gewicht (${unit})`} htmlFor="bwValue">
            <Input id="bwValue" inputMode="decimal" value={bwValue} onChange={(e) => setBwValue(e.target.value)} placeholder="z. B. 82,5" autoFocus />
          </Field>
          <Button type="submit" fullWidth loading={busy}>
            Speichern
          </Button>
        </form>
      </Sheet>
    </div>
  );
}

function ChartCard({ title, subtitle, action, children }: { title: string; subtitle?: string; action?: React.ReactNode; children: React.ReactNode }) {
  return (
    <Card>
      <CardContent className="pt-5">
        <div className="mb-3 flex items-start justify-between gap-3">
          <div>
            <p className="text-sm font-semibold">{title}</p>
            {subtitle ? <p className="text-xs text-muted">{subtitle}</p> : null}
          </div>
          {action}
        </div>
        {children}
      </CardContent>
    </Card>
  );
}

function Mini({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-border bg-card px-3 py-3">
      <p className="text-[10px] font-medium uppercase tracking-wider text-faint">{label}</p>
      <p className="tnum mt-1 text-base font-semibold">{value}</p>
    </div>
  );
}
