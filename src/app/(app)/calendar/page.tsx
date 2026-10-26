import { endOfMonth, startOfMonth, format } from "date-fns";
import { requireUser } from "@/lib/auth/require-user";
import { listCalendarEntries } from "@/lib/services/calendar";
import { listSessions } from "@/lib/services/sessions";
import { toDateKey } from "@/lib/utils/format";
import { PageHeader } from "@/components/ui/page-header";
import { AvatarLink } from "@/components/ui/avatar";
import { HistoryTabs } from "@/components/history/history-tabs";
import { CalendarView } from "@/components/calendar/calendar-view";

export const metadata = { title: "Kalender" };

export default async function CalendarPage() {
  const { supabase, user, profile } = await requireUser();
  const now = new Date();
  const from = startOfMonth(now);
  const to = endOfMonth(now);
  const [entries, sessions] = await Promise.all([
    listCalendarEntries(supabase, user.id, toDateKey(from), toDateKey(to)),
    listSessions(supabase, user.id, { from: from.toISOString(), to: new Date(to.getTime() + 86_399_000).toISOString(), limit: 200 }),
  ]);
  return (
    <div className="space-y-4">
      <PageHeader
        title="Kalender"
        description="Tag antippen und als Training, Rest Day, Freizeit oder Party eintragen."
        actions={<AvatarLink name={profile.nickname} className="lg:hidden" />}
        className="mb-0"
      />
      <HistoryTabs active="calendar" />
      <CalendarView initialMonth={format(now, "yyyy-MM")} initialEntries={entries} initialSessions={sessions} />
    </div>
  );
}
