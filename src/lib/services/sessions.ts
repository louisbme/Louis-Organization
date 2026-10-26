import type { DbClient } from "@/lib/supabase/db";
import type {
  LastPerformanceRow,
  WorkoutSessionExerciseRow,
  WorkoutSessionRow,
  WorkoutSetRow,
} from "@/lib/supabase/types";
import { EXERCISE_SUMMARY_SELECT, toSummary, type ExerciseSummary } from "@/lib/services/exercises";
import { groupLastPerformance, type ExerciseLastPerformance } from "@/lib/utils/progression";

type RawSummary = Parameters<typeof toSummary>[0];

/** Numerische Spalten aus PostgREST (numeric → string) in Zahlen wandeln */
function normalizeSet(s: WorkoutSetRow): WorkoutSetRow {
  return {
    ...s,
    weight: Number(s.weight),
    body_weight: s.body_weight === null || s.body_weight === undefined ? null : Number(s.body_weight),
    extra_weight: s.extra_weight === null || s.extra_weight === undefined ? null : Number(s.extra_weight),
    duration_seconds: s.duration_seconds ?? null,
    distance_m: s.distance_m ?? null,
  };
}

export interface SessionExerciseDetail extends WorkoutSessionExerciseRow {
  exercise: ExerciseSummary;
  sets: WorkoutSetRow[];
}

export interface SessionDetail extends WorkoutSessionRow {
  exercises: SessionExerciseDetail[];
}

type SessionDetailRaw = WorkoutSessionRow & {
  workout_session_exercises: Array<
    WorkoutSessionExerciseRow & { exercises: RawSummary; workout_sets: WorkoutSetRow[] }
  >;
};

const SESSION_DETAIL_SELECT = `*, workout_session_exercises(*, exercises(${EXERCISE_SUMMARY_SELECT}), workout_sets(*))`;

function normalizeSession(raw: SessionDetailRaw): SessionDetail {
  const { workout_session_exercises, ...session } = raw;
  return {
    ...session,
    total_volume: Number(session.total_volume),
    exercises: workout_session_exercises
      .map((se) => {
        const { exercises, workout_sets, ...rest } = se;
        return {
          ...rest,
          exercise: toSummary(exercises),
          sets: workout_sets.map(normalizeSet).sort((a, b) => a.set_number - b.set_number),
        };
      })
      .sort((a, b) => a.sort_order - b.sort_order),
  };
}

export async function getActiveSession(db: DbClient, userId: string): Promise<WorkoutSessionRow | null> {
  const { data, error } = await db
    .from("workout_sessions")
    .select("*")
    .eq("user_id", userId)
    .eq("status", "active")
    .order("started_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function startSession(db: DbClient, planId: string): Promise<string> {
  const { data, error } = await db.rpc("start_workout_session", { p_plan_id: planId });
  if (error) throw error;
  return data;
}

export async function getSessionDetail(db: DbClient, sessionId: string): Promise<SessionDetail | null> {
  const { data, error } = await db
    .from("workout_sessions")
    .select(SESSION_DETAIL_SELECT)
    .eq("id", sessionId)
    .maybeSingle()
    .overrideTypes<SessionDetailRaw, { merge: false }>();
  if (error) throw error;
  return data ? normalizeSession(data) : null;
}

export interface SaveSetInput {
  id?: string;
  session_exercise_id: string;
  user_id: string;
  set_number: number;
  weight: number;
  reps: number;
  rir: number | null;
  is_warmup: boolean;
  completed: boolean;
  duration_seconds?: number | null;
  distance_m?: number | null;
  body_weight?: number | null;
  extra_weight?: number | null;
}

/**
 * Cardio-/Körpergewichtsfelder nur mitschicken, wenn sie gesetzt sind. Für Gewicht × Wdh
 * bleibt die Nutzlast damit identisch zum alten Schema (deploy-reihenfolgeunabhängig).
 */
function trackingFields(input: Pick<SaveSetInput, "duration_seconds" | "distance_m" | "body_weight" | "extra_weight">) {
  const out: Partial<Pick<WorkoutSetRow, "duration_seconds" | "distance_m" | "body_weight" | "extra_weight">> = {};
  if (input.duration_seconds !== null && input.duration_seconds !== undefined) out.duration_seconds = input.duration_seconds;
  if (input.distance_m !== null && input.distance_m !== undefined) out.distance_m = input.distance_m;
  if (input.body_weight !== null && input.body_weight !== undefined) out.body_weight = input.body_weight;
  if (input.extra_weight !== null && input.extra_weight !== undefined) out.extra_weight = input.extra_weight;
  return out;
}

export async function saveSet(db: DbClient, input: SaveSetInput): Promise<WorkoutSetRow> {
  const { data, error } = await db
    .from("workout_sets")
    .upsert(
      {
        ...(input.id ? { id: input.id } : {}),
        session_exercise_id: input.session_exercise_id,
        user_id: input.user_id,
        set_number: input.set_number,
        weight: input.weight,
        reps: input.reps,
        rir: input.rir,
        is_warmup: input.is_warmup,
        completed: input.completed,
        completed_at: new Date().toISOString(),
        ...trackingFields(input),
      },
      { onConflict: "session_exercise_id,set_number" }
    )
    .select("*")
    .single();
  if (error) throw error;
  return normalizeSet(data);
}

export type SetPatch = Partial<Pick<WorkoutSetRow, "weight" | "reps" | "rir" | "is_warmup" | "duration_seconds" | "distance_m" | "body_weight" | "extra_weight">>;

/** Werte eines bestehenden Satzes ändern (auch nach Abschluss des Trainings; Summen berechnet die DB neu). */
export async function updateSet(db: DbClient, setId: string, patch: SetPatch): Promise<WorkoutSetRow> {
  const { duration_seconds, distance_m, body_weight, extra_weight, ...base } = patch;
  const payload = { ...base, ...trackingFields({ duration_seconds, distance_m, body_weight, extra_weight }) };
  const { data, error } = await db.from("workout_sets").update(payload).eq("id", setId).select("*").single();
  if (error) throw error;
  return normalizeSet(data);
}

export async function deleteSet(db: DbClient, setId: string): Promise<void> {
  const { error } = await db.from("workout_sets").delete().eq("id", setId);
  if (error) throw error;
}

export async function addSessionExercise(
  db: DbClient,
  input: {
    session_id: string;
    user_id: string;
    exercise_id: string;
    sort_order: number;
    target_sets: number;
    rep_min: number;
    rep_max: number;
    target_duration_seconds?: number | null;
    target_distance_m?: number | null;
  }
): Promise<WorkoutSessionExerciseRow> {
  const { data, error } = await db.from("workout_session_exercises").insert(input).select("*").single();
  if (error) throw error;
  return data;
}

export async function removeSessionExercise(db: DbClient, id: string): Promise<void> {
  const { error } = await db.from("workout_session_exercises").delete().eq("id", id);
  if (error) throw error;
}

export async function completeSession(
  db: DbClient,
  sessionId: string,
  notes: string | null,
  localDate: string
): Promise<WorkoutSessionRow> {
  const { data, error } = await db.rpc("complete_workout_session", {
    p_session_id: sessionId,
    p_notes: notes,
    p_local_date: localDate,
  });
  if (error) throw error;
  return data;
}

export async function cancelSession(db: DbClient, sessionId: string): Promise<void> {
  const { error } = await db.rpc("cancel_workout_session", { p_session_id: sessionId });
  if (error) throw error;
}

export async function deleteSession(db: DbClient, sessionId: string): Promise<void> {
  const { error } = await db.from("workout_sessions").delete().eq("id", sessionId);
  if (error) throw error;
}

export async function updateSessionNotes(db: DbClient, sessionId: string, notes: string | null): Promise<void> {
  const { error } = await db.from("workout_sessions").update({ notes }).eq("id", sessionId);
  if (error) throw error;
}

export async function getLastPerformance(
  db: DbClient,
  exerciseIds: string[]
): Promise<Map<string, ExerciseLastPerformance>> {
  if (exerciseIds.length === 0) return new Map();
  const { data, error } = await db.rpc("get_last_exercise_performance", { p_exercise_ids: exerciseIds });
  if (error) throw error;
  return groupLastPerformance((data ?? []) as LastPerformanceRow[]);
}

/** Kompakte Session-Liste (Historie, Dashboard) */
export interface SessionListItem {
  id: string;
  name: string;
  plan_id: string | null;
  started_at: string;
  ended_at: string | null;
  duration_seconds: number | null;
  total_volume: number;
  total_sets: number;
  exercise_names: string[];
}

type SessionListRaw = {
  id: string;
  name: string;
  plan_id: string | null;
  started_at: string;
  ended_at: string | null;
  duration_seconds: number | null;
  total_volume: number;
  total_sets: number;
  workout_session_exercises: Array<{ sort_order: number; exercises: { name: string } }>;
};

export interface SessionListFilters {
  from?: string;
  to?: string;
  planId?: string;
  exerciseId?: string;
  limit?: number;
}

export async function listSessions(db: DbClient, userId: string, filters: SessionListFilters = {}): Promise<SessionListItem[]> {
  let sessionIds: string[] | null = null;
  if (filters.exerciseId) {
    const { data, error } = await db
      .from("workout_session_exercises")
      .select("session_id")
      .eq("user_id", userId)
      .eq("exercise_id", filters.exerciseId);
    if (error) throw error;
    sessionIds = Array.from(new Set((data ?? []).map((r) => r.session_id)));
    if (sessionIds.length === 0) return [];
  }

  let query = db
    .from("workout_sessions")
    .select(
      "id, name, plan_id, started_at, ended_at, duration_seconds, total_volume, total_sets, workout_session_exercises(sort_order, exercises(name))"
    )
    .eq("user_id", userId)
    .eq("status", "completed")
    .order("started_at", { ascending: false });

  if (filters.from) query = query.gte("started_at", filters.from);
  if (filters.to) query = query.lte("started_at", filters.to);
  if (filters.planId) query = query.eq("plan_id", filters.planId);
  if (sessionIds) query = query.in("id", sessionIds);
  if (filters.limit) query = query.limit(filters.limit);

  const { data, error } = await query.overrideTypes<SessionListRaw[], { merge: false }>();
  if (error) throw error;
  return (data ?? []).map((s) => ({
    id: s.id,
    name: s.name,
    plan_id: s.plan_id,
    started_at: s.started_at,
    ended_at: s.ended_at,
    duration_seconds: s.duration_seconds,
    total_volume: Number(s.total_volume),
    total_sets: s.total_sets,
    exercise_names: [...s.workout_session_exercises]
      .sort((a, b) => a.sort_order - b.sort_order)
      .map((e) => e.exercises.name),
  }));
}

export async function getLastCompletedSession(db: DbClient, userId: string): Promise<SessionListItem | null> {
  const list = await listSessions(db, userId, { limit: 1 });
  return list[0] ?? null;
}
