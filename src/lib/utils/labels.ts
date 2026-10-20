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
