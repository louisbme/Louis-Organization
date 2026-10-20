"use client";

import * as React from "react";
import { toast } from "sonner";
import { createClient } from "@/lib/supabase/client";
import type { ExerciseSummary } from "@/lib/services/exercises";
import {
  addSessionExercise,
  deleteSet as deleteSetDb,
  removeSessionExercise,
  saveSet as saveSetDb,
  type SessionDetail,
} from "@/lib/services/sessions";
import type { ExerciseLastPerformance } from "@/lib/utils/progression";
import { suggestProgression } from "@/lib/utils/progression";
import { friendlyError } from "@/lib/utils/errors";

export interface LocalSet {
  key: string;
  id: string | null;
  set_number: number;
  weight: number;
  reps: number;
  rir: number | null;
  is_warmup: boolean;
  completed: boolean;
  pending: boolean;
}

export interface LocalExercise {
  sessionExerciseId: string;
  exercise: ExerciseSummary;
  sort_order: number;
  target_sets: number;
  rep_min: number;
  rep_max: number;
  sets: LocalSet[];
}

interface Snapshot {
  version: 1;
  exercises: Record<string, LocalSet[]>;
}

const storageKey = (sessionId: string) => `workout:${sessionId}`;

function readSnapshot(sessionId: string): Snapshot | null {
  try {
    const raw = localStorage.getItem(storageKey(sessionId));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Snapshot;
    return parsed.version === 1 ? parsed : null;
  } catch {
    return null;
  }
}

function writeSnapshot(sessionId: string, exercises: LocalExercise[]) {
  try {
    const snap: Snapshot = { version: 1, exercises: {} };
    for (const e of exercises) snap.exercises[e.sessionExerciseId] = e.sets;
    localStorage.setItem(storageKey(sessionId), JSON.stringify(snap));
  } catch {
    // Speicher nicht verfügbar
  }
}

export function clearSnapshot(sessionId: string) {
  try {
    localStorage.removeItem(storageKey(sessionId));
  } catch {
    // ignore
  }
}

const newKey = () => Math.random().toString(36).slice(2, 10);

function buildPlaceholders(
  ex: { target_sets: number; rep_min: number; rep_max: number },
  existing: LocalSet[],
  last: ExerciseLastPerformance | undefined,
  weightStep: number
): LocalSet[] {
  const result = [...existing].sort((a, b) => a.set_number - b.set_number);
  const { suggestion, lastWeight } = suggestProgression(last, ex.target_sets, ex.rep_max);
  const lastWorking = (last?.sets ?? []).filter((s) => !s.isWarmup);
  for (let n = 1; n <= ex.target_sets; n++) {
    if (result.some((s) => s.set_number === n)) continue;
    const ref = lastWorking[n - 1] ?? lastWorking[lastWorking.length - 1];
    let weight = ref?.weight ?? lastWeight ?? 0;
    if (suggestion === "increase" && lastWeight !== null) weight = Math.max(weight, lastWeight) + weightStep;
    const reps = ref?.reps ?? ex.rep_min;
    result.push({
      key: newKey(),
      id: null,
      set_number: n,
      weight: Math.round(weight * 100) / 100,
      reps,
      rir: null,
      is_warmup: false,
      completed: false,
      pending: false,
    });
  }
  return result.sort((a, b) => a.set_number - b.set_number);
}

export function useWorkoutStore(session: SessionDetail, lastPerformance: Map<string, ExerciseLastPerformance>, weightStep: number, userId: string) {
  const db = React.useMemo(() => createClient(), []);
  const [exercises, setExercises] = React.useState<LocalExercise[]>(() => {
    const snapshot = typeof window !== "undefined" ? readSnapshot(session.id) : null;
    return session.exercises.map((se) => {
      const serverSets: LocalSet[] = se.sets
        .filter((s) => s.completed)
        .map((s) => ({
          key: s.id,
          id: s.id,
          set_number: s.set_number,
          weight: Number(s.weight),
          reps: s.reps,
          rir: s.rir,
          is_warmup: s.is_warmup,
          completed: true,
          pending: false,
        }));
      const localSets = snapshot?.exercises[se.id] ?? [];
      // Lokale Sätze übernehmen, die der Server noch nicht kennt (ausstehend oder Entwurf)
      const merged = [...serverSets];
      for (const ls of localSets) {
        if (merged.some((s) => s.set_number === ls.set_number)) continue;
        merged.push({ ...ls, id: null, pending: ls.completed });
      }
      const last = lastPerformance.get(se.exercise_id);
      return {
        sessionExerciseId: se.id,
        exercise: se.exercise,
        sort_order: se.sort_order,
        target_sets: se.target_sets,
        rep_min: se.rep_min,
        rep_max: se.rep_max,
        sets: buildPlaceholders(se, merged, last, weightStep),
      };
    });
  });
  const [syncing, setSyncing] = React.useState(false);
  const flushingRef = React.useRef(false);

  React.useEffect(() => {
    writeSnapshot(session.id, exercises);
  }, [exercises, session.id]);

  const pendingCount = exercises.reduce((n, e) => n + e.sets.filter((s) => s.pending).length, 0);

  const patchSet = React.useCallback((sessionExerciseId: string, key: string, patch: Partial<LocalSet>) => {
    setExercises((list) =>
      list.map((e) =>
        e.sessionExerciseId === sessionExerciseId
          ? { ...e, sets: e.sets.map((s) => (s.key === key ? { ...s, ...patch } : s)) }
          : e
      )
    );
  }, []);

  const persist = React.useCallback(
    async (sessionExerciseId: string, set: LocalSet): Promise<boolean> => {
      try {
        const saved = await saveSetDb(db, {
          id: set.id ?? undefined,
          session_exercise_id: sessionExerciseId,
          user_id: userId,
          set_number: set.set_number,
          weight: set.weight,
          reps: set.reps,
          rir: set.rir,
          is_warmup: set.is_warmup,
          completed: true,
        });
        patchSet(sessionExerciseId, set.key, { id: saved.id, pending: false, completed: true });
        return true;
      } catch (e) {
        const msg = friendlyError(e);
        if (msg.includes("Verbindung")) {
          patchSet(sessionExerciseId, set.key, { pending: true, completed: true });
        } else {
          toast.error(msg);
          patchSet(sessionExerciseId, set.key, { pending: false, completed: false });
        }
        return false;
      }
    },
    [db, userId, patchSet]
  );

  const flushPending = React.useCallback(async (): Promise<boolean> => {
    if (flushingRef.current) return false;
    flushingRef.current = true;
    setSyncing(true);
    let allOk = true;
    try {
      for (const e of exercises) {
        for (const s of e.sets) {
          if (s.pending) {
            const ok = await persist(e.sessionExerciseId, s);
            if (!ok) allOk = false;
          }
        }
      }
    } finally {
      flushingRef.current = false;
      setSyncing(false);
    }
    return allOk;
  }, [exercises, persist]);

  React.useEffect(() => {
    const onOnline = () => {
      if (pendingCount > 0) {
        flushPending().then((ok) => ok && toast.success("Sätze synchronisiert"));
      }
    };
    window.addEventListener("online", onOnline);
    return () => window.removeEventListener("online", onOnline);
  }, [pendingCount, flushPending]);

  const saveSet = React.useCallback(
    async (sessionExerciseId: string, key: string): Promise<boolean> => {
      const ex = exercises.find((e) => e.sessionExerciseId === sessionExerciseId);
      const set = ex?.sets.find((s) => s.key === key);
      if (!ex || !set) return false;
      const next = { ...set, completed: true, pending: true };
      patchSet(sessionExerciseId, key, { completed: true, pending: true });
      const ok = await persist(sessionExerciseId, next);
      if (!ok && pendingCount === 0 && !navigator.onLine) {
        toast.message("Offline – Satz wird synchronisiert, sobald die Verbindung zurück ist.");
      }
      return true;
    },
    [exercises, patchSet, persist, pendingCount]
  );

  const addSet = React.useCallback((sessionExerciseId: string) => {
    setExercises((list) =>
      list.map((e) => {
        if (e.sessionExerciseId !== sessionExerciseId) return e;
        const last = e.sets[e.sets.length - 1];
        const n = (last?.set_number ?? 0) + 1;
        if (n > 30) return e;
        return {
          ...e,
          sets: [
            ...e.sets,
            {
              key: newKey(),
              id: null,
              set_number: n,
              weight: last?.weight ?? 0,
              reps: last?.reps ?? e.rep_min,
              rir: last?.rir ?? null,
              is_warmup: false,
              completed: false,
              pending: false,
            },
          ],
        };
      })
    );
  }, []);

  const removeLastSet = React.useCallback(
    async (sessionExerciseId: string) => {
      const ex = exercises.find((e) => e.sessionExerciseId === sessionExerciseId);
      const last = ex?.sets[ex.sets.length - 1];
      if (!ex || !last || ex.sets.length <= 1) return;
      setExercises((list) =>
        list.map((e) => (e.sessionExerciseId === sessionExerciseId ? { ...e, sets: e.sets.slice(0, -1) } : e))
      );
      if (last.id) {
        try {
          await deleteSetDb(db, last.id);
        } catch (e) {
          toast.error(friendlyError(e));
        }
      }
    },
    [db, exercises]
  );

  const addExercise = React.useCallback(
    async (item: ExerciseSummary) => {
      const order = (exercises[exercises.length - 1]?.sort_order ?? 0) + 1;
      try {
        const row = await addSessionExercise(db, {
          session_id: session.id,
          user_id: userId,
          exercise_id: item.id,
          sort_order: order,
          target_sets: 3,
          rep_min: 8,
          rep_max: 12,
        });
        setExercises((list) => [
          ...list,
          {
            sessionExerciseId: row.id,
            exercise: item,
            sort_order: row.sort_order,
            target_sets: row.target_sets,
            rep_min: row.rep_min,
            rep_max: row.rep_max,
            sets: buildPlaceholders(row, [], lastPerformance.get(item.id), weightStep),
          },
        ]);
        return true;
      } catch (e) {
        toast.error(friendlyError(e));
        return false;
      }
    },
    [db, exercises, session.id, userId, lastPerformance, weightStep]
  );

  const removeExercise = React.useCallback(
    async (sessionExerciseId: string) => {
      const ex = exercises.find((e) => e.sessionExerciseId === sessionExerciseId);
      if (!ex) return;
      if (ex.sets.some((s) => s.completed)) {
        toast.error("Übungen mit gespeicherten Sätzen können nicht entfernt werden.");
        return;
      }
      setExercises((list) => list.filter((e) => e.sessionExerciseId !== sessionExerciseId));
      try {
        await removeSessionExercise(db, sessionExerciseId);
      } catch (e) {
        toast.error(friendlyError(e));
      }
    },
    [db, exercises]
  );

  const completedSets = exercises.flatMap((e) => e.sets.filter((s) => s.completed));
  const volume = completedSets.filter((s) => !s.is_warmup).reduce((v, s) => v + s.weight * s.reps, 0);

  return {
    exercises,
    patchSet,
    saveSet,
    addSet,
    removeLastSet,
    addExercise,
    removeExercise,
    flushPending,
    pendingCount,
    syncing,
    completedSetCount: completedSets.length,
    workingSetCount: completedSets.filter((s) => !s.is_warmup).length,
    volume,
  };
}
