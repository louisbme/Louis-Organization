import type { DbClient } from "@/lib/supabase/db";
import type {
  LastPerformanceRow,
  WorkoutSessionExerciseRow,
  WorkoutSessionRow,
  WorkoutSetRow,
} from "@/lib/supabase/types";
import type { ExerciseSummary } from "@/lib/services/exercises";
import { groupLastPerformance, type ExerciseLastPerformance } from "@/lib/utils/progression";

export interface SessionExerciseDetail extends WorkoutSessionExerciseRow {
  exercise: ExerciseSummary;
  sets: WorkoutSetRow[];
}

export interface SessionDetail extends WorkoutSessionRow {
  exercises: SessionExerciseDetail[];
}

type SessionDetailRaw = WorkoutSessionRow & {
  workout_session_exercises: Array<
    WorkoutSessionExerciseRow & { exercises: ExerciseSummary; workout_sets: WorkoutSetRow[] }
  >;
};

const SESSION_DETAIL_SELECT =
  "*, workout_session_exercises(*, exercises(id, slug, name, category, equipment, image_url, is_custom), workout_sets(*))";

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
          exercise: exercises,
          sets: workout_sets
            .map((s) => ({ ...s, weight: Number(s.weight) }))
            .sort((a, b) => a.set_number - b.set_number),
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
      },
      { onConflict: "session_exercise_id,set_number" }
    )
    .select("*")
    .single();
  if (error) throw error;
  return { ...data, weight: Number(data.weight) };
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
