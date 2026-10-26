import { Suspense } from "react";
import Link from "next/link";
import { Plus } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { listExercises } from "@/lib/services/exercises";
import { PageHeader } from "@/components/ui/page-header";
import { Button } from "@/components/ui/button";
import { AvatarLink } from "@/components/ui/avatar";
import { LoadingBlock } from "@/components/ui/states";
import { ExerciseBrowser } from "@/components/exercise/exercise-browser";

export const metadata = { title: "Übungen" };

export default async function ExercisesPage() {
  const { supabase, user, profile } = await requireUser();
  const items = await listExercises(supabase, user.id);
  return (
    <div>
      <PageHeader
        title="Übungen"
        description={`${items.length} Übungen nach Muskelgruppen`}
        actions={
          <>
            <Link href="/exercises/new" aria-label="Eigene Übung erstellen">
              <Button variant="secondary" size="icon-sm">
                <Plus className="h-5 w-5" strokeWidth={2.4} />
              </Button>
            </Link>
            <AvatarLink name={profile.nickname} className="lg:hidden" />
          </>
        }
      />
      <Suspense fallback={<LoadingBlock />}>
        <ExerciseBrowser items={items} />
      </Suspense>
    </div>
  );
}
