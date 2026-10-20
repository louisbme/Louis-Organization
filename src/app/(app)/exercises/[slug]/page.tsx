import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { getExerciseBySlug } from "@/lib/services/exercises";
import { getExerciseRecords } from "@/lib/services/stats";
import { ExerciseDetail } from "@/components/exercise/exercise-detail";

type Params = Promise<{ slug: string }>;

export async function generateMetadata({ params }: { params: Params }): Promise<Metadata> {
  const { slug } = await params;
  return { title: slug.replace(/-/g, " ") };
}

export default async function ExerciseDetailPage({ params }: { params: Params }) {
  const { slug } = await params;
  const { supabase, user, profile } = await requireUser();
  const exercise = await getExerciseBySlug(supabase, user.id, slug);
  if (!exercise) notFound();
  const records = await getExerciseRecords(supabase, exercise.id).catch(() => null);
  return <ExerciseDetail exercise={exercise} records={records} canEditStandard={profile.role === "admin" && !exercise.is_custom} />;
}
