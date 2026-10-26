import type { EquipmentType, ExerciseCategory, TrackingMode, WeightUnit } from "@/lib/supabase/types";
import { formatClock, formatDistance, formatPace, formatWeight } from "@/lib/utils/format";

/** Wie eine Übung erfasst wird, abgeleitet aus Kategorie und Equipment (gleiche Regel wie der DB-Trigger). */
export function deriveTrackingMode(category: ExerciseCategory, equipment: EquipmentType): TrackingMode {
  if (category === "cardio" || equipment === "cardio") return "cardio";
  if (equipment === "bodyweight") return "bodyweight";
  return "weight_reps";
}

/** Nutzt die gespeicherte Tracking-Art, fällt sonst auf die Ableitung zurück. */
export function trackingModeOf(e: { tracking_mode?: TrackingMode | null; category: ExerciseCategory; equipment: EquipmentType }): TrackingMode {
  return e.tracking_mode ?? deriveTrackingMode(e.category, e.equipment);
}

export const TRACKING_LABELS: Record<TrackingMode, string> = {
  weight_reps: "Gewicht × Wiederholungen",
  bodyweight: "Körpergewicht",
  cardio: "Dauer und Distanz",
};

/**
 * Reale Last einer Körpergewichtsübung: Körpergewicht × Anteil + Zusatzgewicht.
 * Negatives Zusatzgewicht (unterstützt) ist erlaubt, das Ergebnis nie unter 0.
 */
export function bodyweightLoad(bodyWeight: number | null | undefined, factor: number, extraWeight: number): number {
  const base = (bodyWeight ?? 0) * (Number.isFinite(factor) ? factor : 1);
  return Math.max(0, Math.round((base + extraWeight) * 100) / 100);
}

/** Zusatzgewicht, das zu einer gewünschten Gesamtlast führt (für Progressionsvorschläge). */
export function extraForLoad(targetLoad: number, bodyWeight: number | null | undefined, factor: number): number {
  const base = (bodyWeight ?? 0) * factor;
  return Math.round((targetLoad - base) * 100) / 100;
}

export interface SetValues {
  weight: number;
  reps: number;
  duration_seconds: number | null;
  distance_m: number | null;
  body_weight: number | null;
  extra_weight: number | null;
}

/** Volumen eines Satzes: bewegte Last × Wiederholungen, Cardio hat kein Volumen. */
export function setVolume(mode: TrackingMode, set: Pick<SetValues, "weight" | "reps">): number {
  if (mode === "cardio") return 0;
  return set.weight * set.reps;
}

/** Pace in Sekunden pro Kilometer, null wenn nicht berechenbar. */
export function paceSecPerKm(durationSeconds: number | null | undefined, distanceM: number | null | undefined): number | null {
  if (!durationSeconds || !distanceM || distanceM < 100) return null;
  return Math.round(durationSeconds / (distanceM / 1000));
}

/** Ein Satz hat Inhalt, wenn für seine Tracking-Art etwas eingetragen ist. */
export function setHasValues(mode: TrackingMode, set: SetValues): boolean {
  if (mode === "cardio") return (set.duration_seconds ?? 0) > 0 || (set.distance_m ?? 0) > 0;
  return set.reps > 0;
}

/** Zielvorgabe einer Übung im Plan: "3 × 8–12" oder "1 Einheit" (Cardio). */
export function formatTarget(mode: TrackingMode, sets: number, repMin: number, repMax: number): string {
  if (mode === "cardio") return sets === 1 ? "1 Einheit" : `${sets} Einheiten`;
  return `${sets} × ${repMin}–${repMax}`;
}

/** Kompakte Darstellung eines Satzes, z. B. "80 kg × 10", "5,00 km · 25:00", "92 kg × 8". */
export function describeSet(mode: TrackingMode, set: SetValues, unit: WeightUnit): string {
  if (mode === "cardio") {
    const parts: string[] = [];
    if (set.distance_m) parts.push(formatDistance(set.distance_m));
    if (set.duration_seconds) parts.push(formatClock(set.duration_seconds));
    const pace = paceSecPerKm(set.duration_seconds, set.distance_m);
    if (pace) parts.push(formatPace(pace));
    return parts.length > 0 ? parts.join(" · ") : "–";
  }
  return `${formatWeight(set.weight, unit)} × ${set.reps}`;
}

/** Zusatzinfo für Körpergewichtssätze: "KG 82 kg × 0,6 + 10 kg" */
export function describeBodyweight(set: SetValues, factor: number, unit: WeightUnit): string | null {
  if (set.body_weight === null) return null;
  const pct = Math.round(factor * 100);
  const extra = set.extra_weight ?? 0;
  const extraText = extra === 0 ? "" : ` ${extra > 0 ? "+" : "−"} ${formatWeight(Math.abs(extra), unit)}`;
  return `${formatWeight(set.body_weight, unit)} × ${pct} %${extraText}`;
}
