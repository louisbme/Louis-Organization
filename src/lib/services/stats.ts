import type { DbClient } from "@/lib/supabase/db";
import type {
  ExerciseHistoryRow,
  ExerciseRecordsRow,
  GroupStatsRow,
  MemberSessionDetail,
  MemberSessionRow,
  UserStatsRow,
} from "@/lib/supabase/types";

export async function getUserStats(db: DbClient): Promise<UserStatsRow> {
  const { data, error } = await db.rpc("get_user_stats");
  if (error) throw error;
  const row = (data ?? [])[0];
  return {
    total_workouts: Number(row?.total_workouts ?? 0),
    total_duration_seconds: Number(row?.total_duration_seconds ?? 0),
    total_volume: Number(row?.total_volume ?? 0),
    total_sets: Number(row?.total_sets ?? 0),
    distinct_exercises: Number(row?.distinct_exercises ?? 0),
    last_workout_at: row?.last_workout_at ?? null,
  };
}

export async function getGroupStats(db: DbClient): Promise<GroupStatsRow[]> {
  const { data, error } = await db.rpc("get_group_stats");
  if (error) throw error;
  return (data ?? []).map((r) => ({
    ...r,
    total_workouts: Number(r.total_workouts),
    total_duration_seconds: Number(r.total_duration_seconds),
    total_volume: Number(r.total_volume),
  }));
}

/** Abgeschlossene Trainings eines Mitglieds (Stats-Detailansicht, nur lesend). */
export async function listMemberSessions(db: DbClient, userId: string, limit = 200): Promise<MemberSessionRow[]> {
  const { data, error } = await db.rpc("get_member_sessions", { p_user_id: userId, p_limit: limit });
  if (error) throw error;
  return (data ?? []).map((r) => ({
    ...r,
    total_volume: Number(r.total_volume),
    exercise_names: r.exercise_names ?? [],
  }));
}

/** Detail eines abgeschlossenen Trainings eines Mitglieds; null, wenn nicht vorhanden oder nicht abgeschlossen. */
export async function getMemberSessionDetail(db: DbClient, sessionId: string): Promise<MemberSessionDetail | null> {
  const { data, error } = await db.rpc("get_member_session_detail", { p_session_id: sessionId });
  if (error) throw error;
  if (!data) return null;
  return {
    session: { ...data.session, total_volume: Number(data.session.total_volume) },
    exercises: (data.exercises ?? []).map((ex) => ({
      ...ex,
      sets: (ex.sets ?? []).map((s) => ({ ...s, weight: Number(s.weight) })),
    })),
  };
}

export async function getExerciseRecords(db: DbClient, exerciseId: string): Promise<ExerciseRecordsRow | null> {
  const { data, error } = await db.rpc("get_exercise_records", { p_exercise_id: exerciseId });
  if (error) throw error;
  const row = (data ?? [])[0];
  if (!row || Number(row.total_sessions) === 0) return null;
  return {
    ...row,
    max_weight: row.max_weight === null ? null : Number(row.max_weight),
    max_reps_weight: row.max_reps_weight === null ? null : Number(row.max_reps_weight),
    best_est_1rm: row.best_est_1rm === null ? null : Number(row.best_est_1rm),
    max_session_volume: row.max_session_volume === null ? null : Number(row.max_session_volume),
    total_sessions: Number(row.total_sessions),
  };
}

export async function getExerciseHistory(
  db: DbClient,
  exerciseId: string,
  from: string | null
): Promise<ExerciseHistoryRow[]> {
  const { data, error } = await db.rpc("get_exercise_history", { p_exercise_id: exerciseId, p_from: from });
  if (error) throw error;
  return (data ?? []).map((r) => ({
    ...r,
    max_weight: Number(r.max_weight),
    top_set_weight: Number(r.top_set_weight),
    est_1rm: Number(r.est_1rm),
    volume: Number(r.volume),
  }));
}

export interface SessionPoint {
  id: string;
  started_at: string;
  total_volume: number;
  duration_seconds: number;
  total_sets: number;
}

export async function getSessionPoints(db: DbClient, userId: string, from: string | null): Promise<SessionPoint[]> {
  let query = db
    .from("workout_sessions")
    .select("id, started_at, total_volume, duration_seconds, total_sets")
    .eq("user_id", userId)
    .eq("status", "completed")
    .order("started_at", { ascending: true });
  if (from) query = query.gte("started_at", from);
  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []).map((s) => ({
    id: s.id,
    started_at: s.started_at,
    total_volume: Number(s.total_volume),
    duration_seconds: s.duration_seconds ?? 0,
    total_sets: s.total_sets,
  }));
}

export interface TrainedExercise {
  id: string;
  name: string;
  slug: string;
  sessions: number;
}

/** Übungen, die der Benutzer bereits trainiert hat (für Auswahl im Fortschritt). */
export async function listTrainedExercises(db: DbClient, userId: string): Promise<TrainedExercise[]> {
  const { data, error } = await db
    .from("workout_session_exercises")
    .select("exercise_id, exercises(id, name, slug), workout_sessions!inner(status)")
    .eq("user_id", userId)
    .eq("workout_sessions.status", "completed")
    .overrideTypes<Array<{ exercise_id: string; exercises: { id: string; name: string; slug: string } }>, { merge: false }>();
  if (error) throw error;
  const map = new Map<string, TrainedExercise>();
  for (const r of data ?? []) {
    const existing = map.get(r.exercise_id);
    if (existing) existing.sessions += 1;
    else map.set(r.exercise_id, { id: r.exercises.id, name: r.exercises.name, slug: r.exercises.slug, sessions: 1 });
  }
  return Array.from(map.values()).sort((a, b) => b.sessions - a.sessions || a.name.localeCompare(b.name, "de"));
}

export interface BodyWeightPoint {
  id: string;
  entry_date: string;
  weight: number;
}

export async function listBodyWeight(db: DbClient, userId: string, from: string | null): Promise<BodyWeightPoint[]> {
  let query = db
    .from("body_weight_entries")
    .select("id, entry_date, weight")
    .eq("user_id", userId)
    .order("entry_date", { ascending: true });
  if (from) query = query.gte("entry_date", from.slice(0, 10));
  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []).map((r) => ({ ...r, weight: Number(r.weight) }));
}

export async function upsertBodyWeight(db: DbClient, userId: string, entryDate: string, weight: number): Promise<void> {
  const { error } = await db
    .from("body_weight_entries")
    .upsert({ user_id: userId, entry_date: entryDate, weight }, { onConflict: "user_id,entry_date" });
  if (error) throw error;
}

export async function deleteBodyWeight(db: DbClient, id: string): Promise<void> {
  const { error } = await db.from("body_weight_entries").delete().eq("id", id);
  if (error) throw error;
}
