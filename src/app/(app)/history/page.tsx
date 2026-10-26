import { endOfMonth, startOfMonth, format } from "date-fns";
import { requireUser } from "@/lib/auth/require-user";
import { listSessions } from "@/lib/services/sessions";
import { listPlans } from "@/lib/services/plans";
import { listTrainedExercises } from "@/lib/services/stats";
import { listCalendarEntries } from "@/lib/services/calendar";
import { toDateKey } from "@/lib/utils/format";
import { PageHeader } from "@/components/ui/page-header";
import { AvatarLink } from "@/components/ui/avatar";
import { HistoryList } from "@/components/history/history-list";
import { HistoryTabs } from "@/components/history/history-tabs";
import { CalendarView } from "@/components/calendar/calendar-view";

export const metadata = { title: "Verlauf" };

export default async function HistoryPage({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const { tab } = await searchParams;
  const { supabase, user, profile } = await requireUser();
  const now = new Date();
  const from = startOfMonth(now);
  const to = endOfMonth(now);
  const [sessions, plans, exercises, entries] = await Promise.all([
    listSessions(supabase, user.id, { limit: 200 }),
    listPlans(supabase, user.id, true),
    listTrainedExercises(supabase, user.id),
    listCalendarEntries(supabase, user.id, toDateKey(from), toDateKey(to)),
  ]);
  const monthSessions = sessions.filter((s) => {
    const t = new Date(s.started_at).getTime();
    return t >= from.getTime() && t <= to.getTime() + 86_399_000;
  });

  return (
    <div>
      <PageHeader
        title="Verlauf"
        description={`${sessions.length} abgeschlossene Trainings`}
        actions={<AvatarLink name={profile.nickname} className="lg:hidden" />}
      />
      <HistoryTabs
        initialTab={tab === "calendar" ? "calendar" : "list"}
        list={<HistoryList initial={sessions} plans={plans.map((p) => ({ id: p.id, name: p.name }))} exercises={exercises} />}
        calendar={<CalendarView initialMonth={format(now, "yyyy-MM")} initialEntries={entries} initialSessions={monthSessions} />}
      />
    </div>
  );
}
