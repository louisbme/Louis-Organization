import Link from "next/link";
import { CalendarDays } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { listSessions } from "@/lib/services/sessions";
import { listPlans } from "@/lib/services/plans";
import { listTrainedExercises } from "@/lib/services/stats";
import { PageHeader } from "@/components/ui/page-header";
import { Button } from "@/components/ui/button";
import { HistoryList } from "@/components/history/history-list";

export const metadata = { title: "Historie" };

export default async function HistoryPage() {
  const { supabase, user } = await requireUser();
  const [sessions, plans, exercises] = await Promise.all([
    listSessions(supabase, user.id, { limit: 200 }),
    listPlans(supabase, user.id, true),
    listTrainedExercises(supabase, user.id),
  ]);
  return (
    <div>
      <PageHeader
        title="Historie"
        description={`${sessions.length} abgeschlossene Trainings`}
        actions={
          <Link href="/calendar">
            <Button variant="secondary" size="sm">
              <CalendarDays className="h-4 w-4" /> Kalender
            </Button>
          </Link>
        }
      />
      <HistoryList initial={sessions} plans={plans.map((p) => ({ id: p.id, name: p.name }))} exercises={exercises} />
    </div>
  );
}
