import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { getGroupStats, listMemberPlans, listMemberSessions } from "@/lib/services/stats";
import type { MemberSessionRow } from "@/lib/supabase/types";
import { formatDate, formatDuration, formatRelativeDay, formatVolume } from "@/lib/utils/format";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState } from "@/components/ui/states";
import { List, ListHeader, ListRow } from "@/components/ui/list";
import { MemberPlans } from "@/components/stats/member-plans";

export const metadata = { title: "Mitglied" };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Gruppiert Trainings nach Monat (neueste zuerst, Reihenfolge der Liste bleibt erhalten). */
function groupByMonth(items: MemberSessionRow[]): Array<[string, MemberSessionRow[]]> {
  const map = new Map<string, MemberSessionRow[]>();
  for (const s of items) {
    const d = new Date(s.started_at);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
    map.set(key, [...(map.get(key) ?? []), s]);
  }
  return Array.from(map.entries());
}

export default async function MemberStatsPage({ params }: { params: Promise<{ userId: string }> }) {
  const { userId } = await params;
  if (!UUID_RE.test(userId)) notFound();
  const { supabase, user, settings } = await requireUser();
  const [members, sessions, plans] = await Promise.all([
    getGroupStats(supabase),
    listMemberSessions(supabase, userId),
    listMemberPlans(supabase, userId).catch(() => []),
  ]);
  const member = members.find((m) => m.user_id === userId);
  if (!member) notFound();
  const unit = settings.weight_unit;
  const grouped = groupByMonth(sessions);
  const isSelf = user.id === userId;

  return (
    <div className="space-y-5">
      <PageHeader
        title={member.nickname}
        backHref="/stats"
        backLabel="Stats"
        description={`${sessions.length} abgeschlossene Trainings · Gesamtvolumen ${formatVolume(member.total_volume, unit)}`}
        compact
      />

      <section>
        <ListHeader
          trailing={
            isSelf ? (
              <Link href="/plans" className="font-semibold text-accent">
                Bearbeiten
              </Link>
            ) : undefined
          }
        >
          Trainingspläne
        </ListHeader>
        {isSelf ? (
          <p className="px-4 text-sm text-muted">Deine eigenen Pläne findest du unter Trainingspläne.</p>
        ) : (
          <MemberPlans plans={plans} ownerName={member.nickname} />
        )}
      </section>

      {sessions.length === 0 ? (
        <EmptyState title="Noch keine Trainings" description={`${member.nickname} hat noch kein Training abgeschlossen.`} />
      ) : (
        grouped.map(([month, items]) => {
          const [year, monthIndex] = month.split("-").map(Number);
          return (
            <section key={month}>
              <ListHeader trailing={String(items.length)}>{formatDate(new Date(year, monthIndex - 1, 1), "MMMM yyyy")}</ListHeader>
              <List>
                {items.map((s) => (
                  <ListRow
                    key={s.session_id}
                    href={`/stats/${userId}/${s.session_id}`}
                    title={s.name}
                    subtitle={
                      <>
                        {formatRelativeDay(s.started_at)} · {formatDuration(s.duration_seconds)} · {s.total_sets} Sätze
                        <span className="block truncate text-xs text-faint">{s.exercise_names.join(" · ")}</span>
                      </>
                    }
                    trailing={formatVolume(s.total_volume, unit)}
                    chevron
                  />
                ))}
              </List>
            </section>
          );
        })
      )}
    </div>
  );
}
