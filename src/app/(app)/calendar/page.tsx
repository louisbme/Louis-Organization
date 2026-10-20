import { endOfMonth, startOfMonth, format } from "date-fns";
import { requireUser } from "@/lib/auth/require-user";
import { listCalendarEntries } from "@/lib/services/calendar";
import { listSessions } from "@/lib/services/sessions";
import { toDateKey } from "@/lib/utils/format";
import { PageHeader } from "@/components/ui/page-header";
import { CalendarView } from "@/components/calendar/calendar-view";

export const metadata = { title: "Kalender" };

export default async function CalendarPage() {
  const { supabase, user } = await requireUser();
  const now = new Date();
  const from = startOfMonth(now);
  const to = endOfMonth(now);
  const [entries, sessions] = await Promise.all([
    listCalendarEntries(supabase, user.id, toDateKey(from), toDateKey(to)),
    listSessions(supabase, user.id, { from: from.toISOString(), to: to.toISOString(), limit: 200 }),
  ]);
  return (
    <div>
      <PageHeader title="Kalender" description="Trainings, Rest Days und andere Tage markieren." />
      <CalendarView initialMonth={format(now, "yyyy-MM")} initialEntries={entries} initialSessions={sessions} />
    </div>
  );
}
