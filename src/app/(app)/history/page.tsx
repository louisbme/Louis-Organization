import Link from "next/link";
import { CalendarDays } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { listSessions } from "@/lib/services/sessions";
import { listPlans } from "@/lib/services/plans";
import { listTrainedExercises } from "@/lib/services/stats";
import { PageHeader } from "@/components/ui/page-header";
import { Button } from "@/components/ui/button";
import { AvatarLink } from "@/components/ui/avatar";
import { HistoryList } from "@/components/history/history-list";

export const metadata = { title: "Verlauf" };

export default async function HistoryPage() {
  const { supabase, user, profile } = await requireUser();
  const [sessions, plans, exercises] = await Promise.all([
    listSessions(supabase, user.id, { limit: 200 }),
    listPlans(supabase, user.id, true),
    listTrainedExercises(supabase, user.id),
  ]);
  return (
    <div>
      <PageHeader
        title="Verlauf"
        description={`${sessions.length} abgeschlossene Trainings`}
        actions={
          <>
            <Link href="/calendar" aria-label="Kalender">
              <Button variant="secondary" size="icon-sm">
                <CalendarDays className="h-5 w-5" strokeWidth={2.2} />
              </Button>
            </Link>
            <AvatarLink name={profile.nickname} className="lg:hidden" />
          </>
        }
      />
      <HistoryList initial={sessions} plans={plans.map((p) => ({ id: p.id, name: p.name }))} exercises={exercises} />
    </div>
  );
}
