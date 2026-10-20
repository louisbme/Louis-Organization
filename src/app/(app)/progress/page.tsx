import { subMonths } from "date-fns";
import { requireUser } from "@/lib/auth/require-user";
import { getSessionPoints, listBodyWeight, listTrainedExercises } from "@/lib/services/stats";
import { PageHeader } from "@/components/ui/page-header";
import { ProgressView } from "@/components/progress/progress-view";

export const metadata = { title: "Fortschritt" };

export default async function ProgressPage() {
  const { supabase, user } = await requireUser();
  const from = subMonths(new Date(), 12).toISOString();
  const [exercises, points, bodyWeight] = await Promise.all([
    listTrainedExercises(supabase, user.id),
    getSessionPoints(supabase, user.id, from),
    listBodyWeight(supabase, user.id, from),
  ]);
  return (
    <div>
      <PageHeader title="Fortschritt" description="Volumen, Häufigkeit, Dauer und Kraftentwicklung." />
      <ProgressView exercises={exercises} initialPoints={points} initialBodyWeight={bodyWeight} />
    </div>
  );
}
