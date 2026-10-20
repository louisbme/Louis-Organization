import { requireUser } from "@/lib/auth/require-user";
import { listGrips } from "@/lib/services/exercises";
import { PageHeader } from "@/components/ui/page-header";
import { ExerciseForm } from "@/components/exercise/exercise-form";

export const metadata = { title: "Eigene Übung" };

export default async function NewExercisePage() {
  const { supabase } = await requireUser();
  const grips = await listGrips(supabase);
  return (
    <div>
      <PageHeader title="Eigene Übung erstellen" backHref="/exercises" description="Name, Muskelgruppe und Equipment sind Pflicht. Alles andere ist optional." />
      <ExerciseForm grips={grips} />
    </div>
  );
}
