import { requireUser } from "@/lib/auth/require-user";
import { listSessions } from "@/lib/services/sessions";
import { listPlans } from "@/lib/services/plans";
import { listTrainedExercises } from "@/lib/services/stats";
import { PageHeader } from "@/components/ui/page-header";
import { AvatarLink } from "@/components/ui/avatar";
import { HistoryList } from "@/components/history/history-list";
import { HistoryTabs } from "@/components/history/history-tabs";

export const metadata = { title: "Verlauf" };

export default async function HistoryPage() {
  const { supabase, user, profile } = await requireUser();
  const [sessions, plans, exercises] = await Promise.all([
    listSessions(supabase, user.id, { limit: 200 }),
    listPlans(supabase, user.id, true),
    listTrainedExercises(supabase, user.id),
  ]);

  return (
    <div className="space-y-4">
      <PageHeader
        title="Verlauf"
        description={`${sessions.length} abgeschlossene Trainings`}
        actions={<AvatarLink name={profile.nickname} className="lg:hidden" />}
        className="mb-0"
      />
      <HistoryTabs active="list" />
      <HistoryList initial={sessions} plans={plans.map((p) => ({ id: p.id, name: p.name }))} exercises={exercises} />
    </div>
  );
}
