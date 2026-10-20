import { notFound, redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { getExerciseBySlug, listGrips } from "@/lib/services/exercises";
import { PageHeader } from "@/components/ui/page-header";
import { ExerciseForm } from "@/components/exercise/exercise-form";

export const metadata = { title: "Übung bearbeiten" };

export default async function EditExercisePage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const { supabase, user, profile } = await requireUser();
  const [exercise, grips] = await Promise.all([getExerciseBySlug(supabase, user.id, slug), listGrips(supabase)]);
  if (!exercise) notFound();
  const isOwner = exercise.is_custom && exercise.owner_id === user.id;
  const isAdminStandard = !exercise.is_custom && profile.role === "admin";
  if (!isOwner && !isAdminStandard) redirect(`/exercises/${slug}`);
  return (
    <div>
      <PageHeader
        title="Übung bearbeiten"
        backHref={`/exercises/${slug}`}
        description={isAdminStandard ? "Standardübung: Änderungen gelten sofort für alle Nutzer." : undefined}
      />
      <ExerciseForm grips={grips} existing={exercise} />
    </div>
  );
}
