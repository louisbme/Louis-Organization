import type { DbClient } from "@/lib/supabase/db";
import type {
  CableSetup,
  EquipmentType,
  ExerciseCategory,
  ExerciseRow,
  GripRow,
  MuscleRole,
} from "@/lib/supabase/types";

export interface ExerciseSummary {
  id: string;
  slug: string;
  name: string;
  category: ExerciseCategory;
  equipment: EquipmentType;
  image_url: string | null;
  is_custom: boolean;
}

export interface ExerciseListItem extends ExerciseSummary {
  grip_id: string | null;
  primary_muscles: string[];
  secondary_muscles: string[];
  is_favorite: boolean;
}

export interface ExerciseDetail extends ExerciseRow {
  primary_muscles: string[];
  secondary_muscles: string[];
  grip: GripRow | null;
  cable: CableSetup | null;
  is_favorite: boolean;
}

type ExerciseWithMusclesRaw = ExerciseRow & { exercise_muscles: Array<{ muscle_id: string; role: MuscleRole }> };
type ExerciseDetailRaw = ExerciseWithMusclesRaw & { grips: GripRow | null };

export const EXERCISE_SUMMARY_SELECT = "id, slug, name, category, equipment, image_url, is_custom";

function splitMuscles(list: Array<{ muscle_id: string; role: MuscleRole }>) {
  return {
    primary_muscles: list.filter((m) => m.role === "primary").map((m) => m.muscle_id),
    secondary_muscles: list.filter((m) => m.role === "secondary").map((m) => m.muscle_id),
  };
}

export async function listFavoriteIds(db: DbClient, userId: string): Promise<Set<string>> {
  const { data, error } = await db.from("favorites").select("exercise_id").eq("user_id", userId);
  if (error) throw error;
  return new Set((data ?? []).map((f) => f.exercise_id));
}

export async function listExercises(db: DbClient, userId: string): Promise<ExerciseListItem[]> {
  const [{ data, error }, favorites] = await Promise.all([
    db
      .from("exercises")
      .select("*, exercise_muscles(muscle_id, role)")
      .order("name", { ascending: true })
      .overrideTypes<ExerciseWithMusclesRaw[], { merge: false }>(),
    listFavoriteIds(db, userId),
  ]);
  if (error) throw error;
  return (data ?? []).map((e) => ({
    id: e.id,
    slug: e.slug,
    name: e.name,
    category: e.category,
    equipment: e.equipment,
    image_url: e.image_url,
    is_custom: e.is_custom,
    grip_id: e.grip_id,
    ...splitMuscles(e.exercise_muscles),
    is_favorite: favorites.has(e.id),
  }));
}

export async function getExerciseBySlug(db: DbClient, userId: string, slug: string): Promise<ExerciseDetail | null> {
  const { data, error } = await db
    .from("exercises")
    .select("*, exercise_muscles(muscle_id, role), grips(*)")
    .eq("slug", slug)
    .order("is_custom", { ascending: true })
    .limit(1)
    .maybeSingle()
    .overrideTypes<ExerciseDetailRaw, { merge: false }>();
  if (error) throw error;
  if (!data) return null;
  const { data: fav } = await db
    .from("favorites")
    .select("exercise_id")
    .eq("user_id", userId)
    .eq("exercise_id", data.id)
    .maybeSingle();
  return toDetail(data, !!fav);
}

export async function getExerciseById(db: DbClient, userId: string, id: string): Promise<ExerciseDetail | null> {
  const { data, error } = await db
    .from("exercises")
    .select("*, exercise_muscles(muscle_id, role), grips(*)")
    .eq("id", id)
    .maybeSingle()
    .overrideTypes<ExerciseDetailRaw, { merge: false }>();
  if (error) throw error;
  if (!data) return null;
  const { data: fav } = await db
    .from("favorites")
    .select("exercise_id")
    .eq("user_id", userId)
    .eq("exercise_id", data.id)
    .maybeSingle();
  return toDetail(data, !!fav);
}

function toDetail(raw: ExerciseDetailRaw, isFavorite: boolean): ExerciseDetail {
  const { exercise_muscles, grips, ...rest } = raw;
  const cable = isCableSetup(rest.cable_setup) ? rest.cable_setup : null;
  return {
    ...rest,
    ...splitMuscles(exercise_muscles),
    grip: grips ?? null,
    cable,
    is_favorite: isFavorite,
  };
}

function isCableSetup(value: unknown): value is CableSetup {
  return !!value && typeof value === "object" && "cable" in (value as Record<string, unknown>);
}

export async function listGrips(db: DbClient): Promise<GripRow[]> {
  const { data, error } = await db.from("grips").select("*").order("sort_order");
  if (error) throw error;
  return data ?? [];
}

export interface CustomExerciseInput {
  name: string;
  category: ExerciseCategory;
  equipment: EquipmentType;
  primary_muscles: string[];
  secondary_muscles: string[];
  grip_id: string | null;
  grip_notes: string | null;
  description: string | null;
  setup: string[];
  execution: string[];
  breathing: string | null;
  common_mistakes: string[];
  tips: string[];
  image_url: string | null;
  animation_url: string | null;
}

export function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/ä/g, "ae")
    .replace(/ö/g, "oe")
    .replace(/ü/g, "ue")
    .replace(/ß/g, "ss")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60);
}

function randomSuffix(): string {
  return Math.random().toString(36).slice(2, 6);
}

export async function createCustomExercise(db: DbClient, userId: string, input: CustomExerciseInput): Promise<ExerciseRow> {
  const base = slugify(input.name) || "uebung";
  const slug = `${base}-u${randomSuffix()}`;
  const { data, error } = await db
    .from("exercises")
    .insert({
      slug,
      name: input.name.trim(),
      category: input.category,
      equipment: input.equipment,
      grip_id: input.grip_id,
      grip_notes: input.grip_notes,
      description: input.description,
      setup: input.setup,
      execution: input.execution,
      breathing: input.breathing,
      common_mistakes: input.common_mistakes,
      tips: input.tips,
      image_url: input.image_url,
      animation_url: input.animation_url,
      is_custom: true,
      owner_id: userId,
    })
    .select("*")
    .single();
  if (error) throw error;
  await replaceMuscles(db, data.id, input.primary_muscles, input.secondary_muscles);
  return data;
}

export async function updateCustomExercise(db: DbClient, id: string, input: CustomExerciseInput): Promise<void> {
  const { error } = await db
    .from("exercises")
    .update({
      name: input.name.trim(),
      category: input.category,
      equipment: input.equipment,
      grip_id: input.grip_id,
      grip_notes: input.grip_notes,
      description: input.description,
      setup: input.setup,
      execution: input.execution,
      breathing: input.breathing,
      common_mistakes: input.common_mistakes,
      tips: input.tips,
      image_url: input.image_url,
      animation_url: input.animation_url,
    })
    .eq("id", id);
  if (error) throw error;
  await replaceMuscles(db, id, input.primary_muscles, input.secondary_muscles);
}

async function replaceMuscles(db: DbClient, exerciseId: string, primary: string[], secondary: string[]) {
  const { error: delError } = await db.from("exercise_muscles").delete().eq("exercise_id", exerciseId);
  if (delError) throw delError;
  const rows = [
    ...primary.map((muscle_id) => ({ exercise_id: exerciseId, muscle_id, role: "primary" as const })),
    ...secondary
      .filter((m) => !primary.includes(m))
      .map((muscle_id) => ({ exercise_id: exerciseId, muscle_id, role: "secondary" as const })),
  ];
  if (rows.length === 0) return;
  const { error } = await db.from("exercise_muscles").insert(rows);
  if (error) throw error;
}

export async function deleteCustomExercise(db: DbClient, id: string): Promise<void> {
  const { error } = await db.from("exercises").delete().eq("id", id);
  if (error) throw error;
}

export async function setFavorite(db: DbClient, userId: string, exerciseId: string, favorite: boolean): Promise<void> {
  if (favorite) {
    const { error } = await db.from("favorites").upsert({ user_id: userId, exercise_id: exerciseId });
    if (error) throw error;
  } else {
    const { error } = await db.from("favorites").delete().eq("user_id", userId).eq("exercise_id", exerciseId);
    if (error) throw error;
  }
}
