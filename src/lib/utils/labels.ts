import type { CalendarEntryType, EquipmentType, ExerciseCategory, MuscleId } from "@/lib/supabase/types";

export const CATEGORY_LABELS: Record<ExerciseCategory, string> = {
  chest: "Brust",
  back: "Rücken",
  shoulders: "Schultern",
  biceps: "Bizeps",
  triceps: "Trizeps",
  quads: "Quadrizeps",
  hamstrings: "Hamstrings",
  glutes: "Gluteus",
  calves: "Waden",
  abs: "Bauch",
  forearms: "Unterarme",
  adductors: "Ad-/Abduktoren",
  cardio: "Cardio",
};

export const CATEGORY_ORDER: ExerciseCategory[] = [
  "chest",
  "back",
  "shoulders",
  "biceps",
  "triceps",
  "forearms",
  "quads",
  "hamstrings",
  "glutes",
  "calves",
  "adductors",
  "abs",
  "cardio",
];

export const EQUIPMENT_LABELS: Record<EquipmentType, string> = {
  machine: "Maschine",
  cable: "Kabelzug",
  barbell: "Langhantel",
  dumbbell: "Kurzhantel",
  bodyweight: "Körpergewicht",
  smith_machine: "Multipresse",
  bench: "Bank",
  other: "Sonstiges",
  cardio: "Cardiogerät",
};

export const EQUIPMENT_ORDER: EquipmentType[] = [
  "machine",
  "cable",
  "dumbbell",
  "barbell",
  "bodyweight",
  "smith_machine",
  "bench",
  "cardio",
  "other",
];

export const MUSCLE_LABELS: Record<MuscleId, string> = {
  chest: "Brust",
  upper_chest: "Obere Brust",
  front_delts: "Vordere Schulter",
  side_delts: "Seitliche Schulter",
  rear_delts: "Hintere Schulter",
  traps: "Trapez",
  lats: "Latissimus",
  upper_back: "Oberer Rücken",
  mid_back: "Mittlerer Rücken",
  lower_back: "Unterer Rücken",
  biceps: "Bizeps",
  triceps: "Trizeps",
  forearms: "Unterarme",
  abs: "Bauch",
  obliques: "Seitliche Bauchmuskeln",
  quads: "Quadrizeps",
  hamstrings: "Hamstrings",
  glutes: "Gluteus",
  calves: "Waden",
  adductors: "Adduktoren",
  abductors: "Abduktoren",
};

export const MUSCLE_IDS = Object.keys(MUSCLE_LABELS) as MuscleId[];

/** Gruppen der Übungsübersicht (Muskelkarten-Raster). */
export type ExerciseGroupKey =
  | "chest"
  | "back"
  | "legs"
  | "shoulders"
  | "biceps"
  | "triceps"
  | "abs"
  | "core"
  | "forearms"
  | "cardio"
  | "favorites"
  | "custom";

export interface ExerciseGroupDef {
  key: ExerciseGroupKey;
  label: string;
  /** Kategorien, die zur Gruppe gehören */
  categories?: ExerciseCategory[];
  /** Alternativ: primäre Muskeln, die zur Gruppe gehören */
  muscles?: MuscleId[];
  /** Ansicht der Figur auf der Karte */
  view: "front" | "back";
  /** Muskeln, die auf der Karte hervorgehoben werden */
  highlight: MuscleId[];
  /** Volle Breite (Cardio, Eigene, Favoriten) */
  wide?: boolean;
}

export const EXERCISE_GROUPS: ExerciseGroupDef[] = [
  { key: "chest", label: "Brust", categories: ["chest"], view: "front", highlight: ["chest", "upper_chest"] },
  { key: "back", label: "Rücken", categories: ["back"], view: "back", highlight: ["lats", "upper_back", "mid_back", "traps"] },
  { key: "legs", label: "Beine", categories: ["quads", "hamstrings", "glutes", "calves", "adductors"], view: "front", highlight: ["quads", "adductors", "calves"] },
  { key: "shoulders", label: "Schultern", categories: ["shoulders"], view: "front", highlight: ["front_delts", "side_delts"] },
  { key: "biceps", label: "Bizeps", categories: ["biceps"], view: "front", highlight: ["biceps"] },
  { key: "triceps", label: "Trizeps", categories: ["triceps"], view: "back", highlight: ["triceps"] },
  { key: "abs", label: "Bauch", categories: ["abs"], view: "front", highlight: ["abs", "obliques"] },
  { key: "core", label: "Rumpf", muscles: ["lower_back", "obliques"], view: "back", highlight: ["lower_back"] },
  { key: "forearms", label: "Unterarme", categories: ["forearms"], view: "front", highlight: ["forearms"] },
  { key: "cardio", label: "Cardio", categories: ["cardio"], view: "front", highlight: [], wide: true },
  { key: "favorites", label: "Favoriten", view: "front", highlight: [], wide: true },
  { key: "custom", label: "Eigene", view: "front", highlight: [], wide: true },
];

export function exerciseGroup(key: string | null | undefined): ExerciseGroupDef | null {
  return EXERCISE_GROUPS.find((g) => g.key === key) ?? null;
}

export function exerciseInGroup(
  e: { category: ExerciseCategory; primary_muscles: string[]; is_custom: boolean; is_favorite: boolean },
  group: ExerciseGroupDef
): boolean {
  if (group.key === "favorites") return e.is_favorite;
  if (group.key === "custom") return e.is_custom;
  if (group.categories && group.categories.includes(e.category)) return true;
  if (group.muscles && e.primary_muscles.some((m) => (group.muscles as string[]).includes(m))) return true;
  return false;
}

export function muscleLabel(id: string): string {
  return (MUSCLE_LABELS as Record<string, string>)[id] ?? id;
}

export const CALENDAR_TYPE_LABELS: Record<CalendarEntryType, string> = {
  training: "Training",
  rest: "Rest Day",
  leisure: "Freizeit-Aktivität",
  party: "Party",
  other: "Anderer Tag",
};

export const CALENDAR_TYPE_ORDER: CalendarEntryType[] = ["training", "rest", "leisure", "party", "other"];

/** Farbige Kennzeichnung je Kalendertyp (Farben als CSS-Variablen in globals.css) */
export const CALENDAR_TYPE_STYLES: Record<CalendarEntryType, { dot: string; chip: string }> = {
  training: { dot: "bg-[var(--cal-training)]", chip: "bg-subtle text-fg" },
  rest: { dot: "bg-[var(--cal-rest)]", chip: "bg-subtle text-fg" },
  leisure: { dot: "bg-[var(--cal-leisure)]", chip: "bg-subtle text-fg" },
  party: { dot: "bg-[var(--cal-party)]", chip: "bg-subtle text-fg" },
  other: { dot: "bg-[var(--cal-other)]", chip: "bg-subtle text-muted" },
};
