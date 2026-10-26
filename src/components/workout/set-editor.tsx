"use client";

import * as React from "react";
import { Scale } from "lucide-react";
import type { TrackingMode, WeightUnit } from "@/lib/supabase/types";
import { formatClock, formatDistance, formatPace, formatWeight, parseClock } from "@/lib/utils/format";
import { bodyweightLoad, paceSecPerKm, type SetValues } from "@/lib/utils/tracking";
import { cn } from "@/lib/utils/cn";
import { Stepper } from "@/components/ui/stepper";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

export interface EditableSet extends SetValues {
  rir: number | null;
}

interface SetEditorProps {
  mode: TrackingMode;
  /** Anteil des Körpergewichts (nur bodyweight) */
  factor: number;
  set: EditableSet;
  unit: WeightUnit;
  weightStep: number;
  showRir: boolean;
  /** Aktuelles Körpergewicht des Benutzers (nur bodyweight) */
  bodyWeight: number | null;
  onChange: (patch: Partial<EditableSet>) => void;
  /** Körpergewicht neu eintragen (speichert einen Eintrag für heute) */
  onBodyWeightChange?: (value: number) => Promise<void> | void;
  idPrefix?: string;
}

/**
 * Eingabefelder eines Satzes je Tracking-Art:
 * Gewicht × Wdh · Körpergewicht (Zusatzgewicht, reale Last wird sofort berechnet) · Cardio (Dauer, Distanz).
 */
export function SetEditor({ mode, factor, set, unit, weightStep, showRir, bodyWeight, onChange, onBodyWeightChange, idPrefix = "set" }: SetEditorProps) {
  if (mode === "cardio") {
    const pace = paceSecPerKm(set.duration_seconds, set.distance_m);
    return (
      <div className="space-y-3">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <Stepper
            label="Dauer"
            value={set.duration_seconds ?? 0}
            step={30}
            min={0}
            max={86400}
            format={formatClock}
            parse={parseClock}
            onChange={(v) => onChange({ duration_seconds: v })}
            hint="mm:ss, Schritte von 30 s"
            inputId={`${idPrefix}-duration`}
          />
          <Stepper
            label="Distanz"
            unit="km"
            value={(set.distance_m ?? 0) / 1000}
            step={0.1}
            min={0}
            max={1000}
            decimals={2}
            onChange={(v) => onChange({ distance_m: Math.round(v * 1000) })}
            inputId={`${idPrefix}-distance`}
          />
        </div>
        <Summary label="Pace" value={pace ? formatPace(pace) : "–"} note={set.distance_m ? formatDistance(set.distance_m) : "Nur Dauer oder nur Distanz ist auch in Ordnung."} />
      </div>
    );
  }

  if (mode === "bodyweight") {
    const bw = set.body_weight ?? bodyWeight;
    const extra = set.extra_weight ?? 0;
    const load = bodyweightLoad(bw, factor, extra);
    const applyExtra = (v: number) => onChange({ extra_weight: v, body_weight: bw, weight: bodyweightLoad(bw, factor, v) });
    return (
      <div className="space-y-3">
        <BodyWeightField
          value={bw}
          unit={unit}
          onSave={async (v) => {
            await onBodyWeightChange?.(v);
            onChange({ body_weight: v, weight: bodyweightLoad(v, factor, extra) });
          }}
        />
        <div className={cn("grid gap-3", showRir ? "grid-cols-1 sm:grid-cols-3" : "grid-cols-1 sm:grid-cols-2")}>
          <Stepper
            label="Zusatzgewicht"
            unit={unit}
            value={extra}
            step={weightStep}
            min={-200}
            max={500}
            decimals={2}
            onChange={applyExtra}
            hint="Negativ = unterstützt (z. B. Gegengewicht)"
            inputId={`${idPrefix}-extra`}
          />
          <Stepper label="Wiederholungen" value={set.reps} step={1} min={0} max={500} onChange={(v) => onChange({ reps: v })} inputId={`${idPrefix}-reps`} />
          {showRir ? <Stepper label="RIR" value={set.rir ?? 2} step={1} min={0} max={10} onChange={(v) => onChange({ rir: v })} inputId={`${idPrefix}-rir`} /> : null}
        </div>
        <Summary
          label="Reale Last"
          value={bw ? formatWeight(load, unit) : "–"}
          note={
            bw
              ? `${formatWeight(bw, unit)} × ${Math.round(factor * 100)} %${extra !== 0 ? ` ${extra > 0 ? "+" : "−"} ${formatWeight(Math.abs(extra), unit)}` : ""}`
              : "Körpergewicht eintragen, damit die Last berechnet wird."
          }
          emphasis
        />
      </div>
    );
  }

  return (
    <div className={cn("grid gap-3", showRir ? "grid-cols-1 sm:grid-cols-3" : "grid-cols-1 sm:grid-cols-2")}>
      <Stepper label="Gewicht" unit={unit} value={set.weight} step={weightStep} min={0} max={999} decimals={2} onChange={(v) => onChange({ weight: v })} inputId={`${idPrefix}-weight`} />
      <Stepper label="Wiederholungen" value={set.reps} step={1} min={0} max={500} onChange={(v) => onChange({ reps: v })} inputId={`${idPrefix}-reps`} />
      {showRir ? <Stepper label="RIR" value={set.rir ?? 2} step={1} min={0} max={10} onChange={(v) => onChange({ rir: v })} inputId={`${idPrefix}-rir`} /> : null}
    </div>
  );
}

function Summary({ label, value, note, emphasis }: { label: string; value: string; note?: string; emphasis?: boolean }) {
  return (
    <div className={cn("flex items-center justify-between gap-3 rounded-[var(--radius-control)] px-4 py-3", emphasis ? "bg-accent-soft" : "bg-subtle")}>
      <div className="min-w-0">
        <p className="text-[13px] font-medium text-muted">{label}</p>
        {note ? <p className="truncate text-xs text-faint">{note}</p> : null}
      </div>
      <p className={cn("display tnum shrink-0 text-xl", emphasis ? "text-accent" : "text-fg")}>{value}</p>
    </div>
  );
}

/** Körpergewicht anzeigen und bei Bedarf neu eintragen. */
function BodyWeightField({ value, unit, onSave }: { value: number | null; unit: WeightUnit; onSave: (v: number) => Promise<void> }) {
  const [editing, setEditing] = React.useState(value === null);
  const [text, setText] = React.useState(value ? String(value).replace(".", ",") : "");
  const [busy, setBusy] = React.useState(false);

  React.useEffect(() => {
    if (value !== null && !editing) setText(String(value).replace(".", ","));
  }, [value, editing]);

  const save = async () => {
    const v = parseFloat(text.replace(",", "."));
    if (!v || v <= 0 || v >= 500) return;
    setBusy(true);
    try {
      await onSave(Math.round(v * 100) / 100);
      setEditing(false);
    } finally {
      setBusy(false);
    }
  };

  if (!editing && value !== null) {
    return (
      <div className="flex items-center justify-between gap-3 rounded-[var(--radius-control)] bg-subtle px-4 py-2.5">
        <div className="flex items-center gap-2.5">
          <Scale className="h-4 w-4 text-muted" />
          <div>
            <p className="text-[13px] font-medium text-muted">Körpergewicht</p>
            <p className="tnum text-base font-semibold">{formatWeight(value, unit)}</p>
          </div>
        </div>
        <Button variant="plain" size="sm" onClick={() => setEditing(true)}>
          Ändern
        </Button>
      </div>
    );
  }

  return (
    <div className="rounded-[var(--radius-control)] bg-subtle p-3">
      <label htmlFor="bodyweight-input" className="mb-1.5 block text-[13px] font-medium text-muted">
        Körpergewicht heute
      </label>
      <div className="flex gap-2">
        <Input
          id="bodyweight-input"
          inputMode="decimal"
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder={`z. B. 80 ${unit}`}
          className="bg-card"
          onKeyDown={(e) => e.key === "Enter" && save()}
        />
        <Button onClick={save} loading={busy} disabled={!text}>
          Speichern
        </Button>
        {value !== null ? (
          <Button variant="ghost" onClick={() => setEditing(false)}>
            Abbrechen
          </Button>
        ) : null}
      </div>
      <p className="mt-1.5 text-xs text-faint">Wird als Eintrag für heute gespeichert und für die Last verwendet.</p>
    </div>
  );
}
