import { notFound, redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { getLastPerformance, getSessionDetail } from "@/lib/services/sessions";
import { ActiveWorkout } from "@/components/workout/active-workout";

export const metadata = { title: "Aktives Training" };

export default async function ActiveWorkoutPage({ params }: { params: Promise<{ sessionId: string }> }) {
  const { sessionId } = await params;
  const { supabase, user } = await requireUser();
  const session = await getSessionDetail(supabase, sessionId);
  if (!session || session.user_id !== user.id) notFound();
  if (session.status !== "active") redirect(`/history/${session.id}`);

  const lastPerformance = await getLastPerformance(
    supabase,
    Array.from(new Set(session.exercises.map((e) => e.exercise_id)))
  );

  // Map ist nicht serialisierbar – als Objekt an die Client-Komponente übergeben
  return <ActiveWorkout session={session} lastPerformance={Object.fromEntries(lastPerformance)} />;
}
