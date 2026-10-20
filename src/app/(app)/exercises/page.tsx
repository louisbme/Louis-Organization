import Link from "next/link";
import { Plus } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { listExercises } from "@/lib/services/exercises";
import { PageHeader } from "@/components/ui/page-header";
import { Button } from "@/components/ui/button";
import { ExerciseBrowser } from "@/components/exercise/exercise-browser";

export const metadata = { title: "Übungen" };

export default async function ExercisesPage() {
  const { supabase, user } = await requireUser();
  const items = await listExercises(supabase, user.id);
  return (
    <div>
      <PageHeader
        title="Übungen"
        description={`${items.length} Übungen · Favoriten zuerst`}
        actions={
          <Link href="/exercises/new">
            <Button variant="secondary" size="sm">
              <Plus className="h-4 w-4" /> Eigene Übung
            </Button>
          </Link>
        }
      />
      <ExerciseBrowser items={items} />
    </div>
  );
}
