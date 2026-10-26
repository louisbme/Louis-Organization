import Link from "next/link";
import { Play } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { listPlans, getNextPlanInRotation } from "@/lib/services/plans";
import { getActiveSession, getLastCompletedSession } from "@/lib/services/sessions";
import { formatRelativeDay } from "@/lib/utils/format";
import { PageHeader } from "@/components/ui/page-header";
import { Button } from "@/components/ui/button";
import { AvatarLink } from "@/components/ui/avatar";
import { Card, CardContent, SectionLabel } from "@/components/ui/card";
import { WorkoutStartList } from "@/components/workout/workout-start-list";

export const metadata = { title: "Training" };

export default async function WorkoutPage({ searchParams }: { searchParams: Promise<{ plan?: string }> }) {
  const { plan: preselect } = await searchParams;
  const { supabase, user, profile } = await requireUser();
  const [plans, active, last] = await Promise.all([
    listPlans(supabase, user.id),
    getActiveSession(supabase, user.id),
    getLastCompletedSession(supabase, user.id),
  ]);
  const next = getNextPlanInRotation(plans, last?.plan_id ?? null);

  return (
    <div>
      <PageHeader
        title="Training"
        description={last ? `Letztes Training: ${last.name}, ${formatRelativeDay(last.started_at).toLowerCase()}` : "Wähle ein Training und starte."}
        actions={<AvatarLink name={profile.nickname} className="lg:hidden" />}
      />
      {active ? (
        <Card className="mb-4 ring-1 ring-accent/40">
          <CardContent className="pt-5">
            <SectionLabel className="text-accent">Aktives Training</SectionLabel>
            <p className="mt-1 text-xl font-semibold">{active.name}</p>
            <p className="text-sm text-muted">Gestartet {formatRelativeDay(active.started_at).toLowerCase()}</p>
            <Link href={`/workout/${active.id}`} className="mt-4 block">
              <Button size="lg" fullWidth>
                <Play className="h-4 w-4" fill="currentColor" /> Fortsetzen
              </Button>
            </Link>
          </CardContent>
        </Card>
      ) : null}
      <WorkoutStartList plans={plans} nextPlanId={next?.id ?? null} preselectPlanId={preselect ?? null} />
    </div>
  );
}
