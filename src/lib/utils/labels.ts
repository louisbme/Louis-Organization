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
  "abs",
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
};

export const EQUIPMENT_ORDER: EquipmentType[] = [
  "machine",
  "cable",
  "dumbbell",
  "barbell",
  "bodyweight",
  "smith_machine",
  "bench",
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

/** Farbklassen (Tailwind) je Kalendertyp – dezent */
export const CALENDAR_TYPE_STYLES: Record<CalendarEntryType, { dot: string; chip: string }> = {
  training: { dot: "bg-accent", chip: "bg-accent-soft text-accent" },
  rest: { dot: "bg-info", chip: "bg-info-soft text-info" },
  leisure: { dot: "bg-warning", chip: "bg-warning-soft text-warning" },
  party: { dot: "bg-[var(--chart-3)]", chip: "bg-[rgba(167,139,250,0.14)] text-[var(--chart-3)]" },
  other: { dot: "bg-faint", chip: "bg-subtle text-muted" },
};
