import type { LastPerformanceRow } from "@/lib/supabase/types";

export type ProgressionSuggestion = "increase" | "hold" | "none";

export interface ExerciseLastPerformance {
  exerciseId: string;
  sessionId: string;
  startedAt: string;
  targetSets: number;
  repMin: number;
  repMax: number;
  sets: Array<{
    setNumber: number;
    weight: number;
    reps: number;
    rir: number | null;
    isWarmup: boolean;
    durationSeconds: number | null;
    distanceM: number | null;
    bodyWeight: number | null;
    extraWeight: number | null;
  }>;
}

export function groupLastPerformance(rows: LastPerformanceRow[]): Map<string, ExerciseLastPerformance> {
  const map = new Map<string, ExerciseLastPerformance>();
  for (const r of rows) {
    let entry = map.get(r.exercise_id);
    if (!entry) {
      entry = {
        exerciseId: r.exercise_id,
        sessionId: r.session_id,
        startedAt: r.started_at,
        targetSets: r.target_sets,
        repMin: r.rep_min,
        repMax: r.rep_max,
        sets: [],
      };
      map.set(r.exercise_id, entry);
    }
    entry.sets.push({
      setNumber: r.set_number,
      weight: Number(r.weight),
      reps: r.reps,
      rir: r.rir,
      isWarmup: r.is_warmup,
      durationSeconds: r.duration_seconds ?? null,
      distanceM: r.distance_m ?? null,
      bodyWeight: r.body_weight === null || r.body_weight === undefined ? null : Number(r.body_weight),
      extraWeight: r.extra_weight === null || r.extra_weight === undefined ? null : Number(r.extra_weight),
    });
  }
  return map;
}

/**
 * Double Progression:
 * Alle geplanten Arbeitssätze am oberen Ende des Wiederholungsbereichs → Gewicht erhöhen.
 * Sonst → Gewicht halten. Die Entscheidung bleibt beim Benutzer.
 */
export function suggestProgression(
  last: ExerciseLastPerformance | undefined,
  targetSets: number,
  repMax: number
): { suggestion: ProgressionSuggestion; lastWeight: number | null; reason: string } {
  if (!last) return { suggestion: "none", lastWeight: null, reason: "Noch keine Daten" };
  const working = last.sets.filter((s) => !s.isWarmup);
  if (working.length === 0) return { suggestion: "none", lastWeight: null, reason: "Noch keine Arbeitssätze" };

  const lastWeight = working[working.length - 1].weight;
  const maxWeight = Math.max(...working.map((s) => s.weight));
  const setsAtMax = working.filter((s) => s.weight === maxWeight);
  const allAtTop = setsAtMax.length >= targetSets && setsAtMax.every((s) => s.reps >= repMax);

  if (allAtTop) {
    return {
      suggestion: "increase",
      lastWeight: maxWeight,
      reason: `${setsAtMax.length} × ${repMax}+ Wdh erreicht`,
    };
  }
  return {
    suggestion: "hold",
    lastWeight,
    reason: "Wiederholungsbereich noch nicht komplett erreicht",
  };
}

/** Geschätztes 1RM (Epley) */
export function estimateOneRepMax(weight: number, reps: number): number {
  if (reps <= 0 || weight <= 0) return 0;
  if (reps === 1) return weight;
  return Math.round(weight * (1 + reps / 30) * 10) / 10;
}
