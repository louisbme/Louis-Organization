import type { DbClient } from "@/lib/supabase/db";
import type { WorkoutPlanExerciseRow, WorkoutPlanRow } from "@/lib/supabase/types";
import { EXERCISE_SUMMARY_SELECT, toSummary, type ExerciseSummary } from "@/lib/services/exercises";

export interface PlanExerciseWithExercise extends WorkoutPlanExerciseRow {
  exercise: ExerciseSummary;
}

export interface PlanWithExercises extends WorkoutPlanRow {
  exercises: PlanExerciseWithExercise[];
}

type PlanRaw = WorkoutPlanRow & {
  workout_plan_exercises: Array<WorkoutPlanExerciseRow & { exercises: Parameters<typeof toSummary>[0] }>;
};

const PLAN_SELECT = `*, workout_plan_exercises(*, exercises(${EXERCISE_SUMMARY_SELECT}))`;

function normalize(raw: PlanRaw): PlanWithExercises {
  const { workout_plan_exercises, ...plan } = raw;
  return {
    ...plan,
    exercises: workout_plan_exercises
      .map((pe) => {
        const { exercises, ...rest } = pe;
        return { ...rest, exercise: toSummary(exercises) };
      })
      .sort((a, b) => a.sort_order - b.sort_order),
  };
}

export async function listPlans(db: DbClient, userId: string, includeArchived = false): Promise<PlanWithExercises[]> {
  let query = db.from("workout_plans").select(PLAN_SELECT).eq("user_id", userId).order("sort_order");
  if (!includeArchived) query = query.eq("is_archived", false);
  const { data, error } = await query.overrideTypes<PlanRaw[], { merge: false }>();
  if (error) throw error;
  return (data ?? []).map(normalize);
}

export async function getPlan(db: DbClient, planId: string): Promise<PlanWithExercises | null> {
  const { data, error } = await db
    .from("workout_plans")
    .select(PLAN_SELECT)
    .eq("id", planId)
    .maybeSingle()
    .overrideTypes<PlanRaw, { merge: false }>();
  if (error) throw error;
  return data ? normalize(data) : null;
}

export async function createPlan(db: DbClient, userId: string, name: string): Promise<string> {
  const { data: existing } = await db
    .from("workout_plans")
    .select("sort_order")
    .eq("user_id", userId)
    .order("sort_order", { ascending: false })
    .limit(1);
  const nextOrder = (existing?.[0]?.sort_order ?? 0) + 1;
  const { data, error } = await db
    .from("workout_plans")
    .insert({ user_id: userId, name: name.trim(), sort_order: nextOrder })
    .select("id")
    .single();
  if (error) throw error;
  return data.id;
}

export async function renamePlan(db: DbClient, planId: string, name: string): Promise<void> {
  const { error } = await db.from("workout_plans").update({ name: name.trim() }).eq("id", planId);
  if (error) throw error;
}

export async function deletePlan(db: DbClient, planId: string): Promise<void> {
  const { error } = await db.from("workout_plans").delete().eq("id", planId);
  if (error) throw error;
}

export async function reorderPlans(db: DbClient, orderedIds: string[]): Promise<void> {
  await Promise.all(
    orderedIds.map((id, index) => db.from("workout_plans").update({ sort_order: index + 1 }).eq("id", id))
  );
}

export async function duplicatePlan(db: DbClient, userId: string, planId: string): Promise<string> {
  const source = await getPlan(db, planId);
  if (!source) throw new Error("Trainingsplan nicht gefunden");
  const newId = await createPlan(db, userId, `${source.name} (Kopie)`);
  if (source.exercises.length > 0) {
    const { error } = await db.from("workout_plan_exercises").insert(
      source.exercises.map((e) => ({
        plan_id: newId,
        exercise_id: e.exercise_id,
        sort_order: e.sort_order,
        target_sets: e.target_sets,
        rep_min: e.rep_min,
        rep_max: e.rep_max,
        notes: e.notes,
        target_duration_seconds: e.target_duration_seconds ?? null,
        target_distance_m: e.target_distance_m ?? null,
      }))
    );
    if (error) throw error;
  }
  return newId;
}

export interface PlanExerciseTargets {
  target_sets: number;
  rep_min: number;
  rep_max: number;
  /** Cardio: Zieldauer je Einheit in Sekunden */
  target_duration_seconds?: number | null;
  /** Cardio: Zieldistanz je Einheit in Metern */
  target_distance_m?: number | null;
}

export async function addPlanExercise(
  db: DbClient,
  planId: string,
  exerciseId: string,
  targets: PlanExerciseTargets,
  sortOrder: number
): Promise<WorkoutPlanExerciseRow> {
  const { data, error } = await db
    .from("workout_plan_exercises")
    .insert({ plan_id: planId, exercise_id: exerciseId, sort_order: sortOrder, ...targets })
    .select("*")
    .single();
  if (error) throw error;
  return data;
}

export async function updatePlanExercise(
  db: DbClient,
  id: string,
  patch: Partial<PlanExerciseTargets & { notes: string | null; exercise_id: string }>
): Promise<void> {
  const { error } = await db.from("workout_plan_exercises").update(patch).eq("id", id);
  if (error) throw error;
}

export async function removePlanExercise(db: DbClient, id: string): Promise<void> {
  const { error } = await db.from("workout_plan_exercises").delete().eq("id", id);
  if (error) throw error;
}

export async function reorderPlanExercises(db: DbClient, orderedIds: string[]): Promise<void> {
  const results = await Promise.all(
    orderedIds.map((id, index) => db.from("workout_plan_exercises").update({ sort_order: index + 1 }).eq("id", id))
  );
  const failed = results.find((r) => r.error);
  if (failed?.error) throw failed.error;
}

/** Nächster Plan in der Rotation (A → B → C → A). Nutzer darf jederzeit abweichen. */
export function getNextPlanInRotation<T extends { id: string }>(plans: T[], lastPlanId: string | null): T | null {
  if (plans.length === 0) return null;
  if (!lastPlanId) return plans[0];
  const idx = plans.findIndex((p) => p.id === lastPlanId);
  if (idx === -1) return plans[0];
  return plans[(idx + 1) % plans.length];
}
