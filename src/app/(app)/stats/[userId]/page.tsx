import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowRight } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { getGroupStats, listMemberSessions } from "@/lib/services/stats";
import type { MemberSessionRow } from "@/lib/supabase/types";
import { formatDate, formatDuration, formatRelativeDay, formatVolume } from "@/lib/utils/format";
import { PageHeader } from "@/components/ui/page-header";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/states";

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
  const { supabase, settings } = await requireUser();
  const [members, sessions] = await Promise.all([getGroupStats(supabase), listMemberSessions(supabase, userId)]);
  const member = members.find((m) => m.user_id === userId);
  if (!member) notFound();
  const unit = settings.weight_unit;
  const grouped = groupByMonth(sessions);

  return (
    <div className="space-y-4">
      <PageHeader
        title={member.nickname}
        backHref="/stats"
        description={`${sessions.length} abgeschlossene Trainings · Gesamtvolumen ${formatVolume(member.total_volume, unit)}`}
      />

      {sessions.length === 0 ? (
        <EmptyState title="Noch keine Trainings" description={`${member.nickname} hat noch kein Training abgeschlossen.`} />
      ) : (
        grouped.map(([month, items]) => {
          const [year, monthIndex] = month.split("-").map(Number);
          return (
            <section key={month}>
              <h2 className="mb-2 px-1 text-[11px] font-semibold uppercase tracking-[0.12em] text-faint">
                {formatDate(new Date(year, monthIndex - 1, 1), "MMMM yyyy")}
                <span className="ml-2 normal-case tracking-normal">· {items.length}</span>
              </h2>
              <Card className="divide-y divide-border overflow-hidden">
                {items.map((s) => (
                  <Link
                    key={s.session_id}
                    href={`/stats/${userId}/${s.session_id}`}
                    className="flex items-center gap-3 px-5 py-3.5 hover:bg-subtle"
                  >
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium">{s.name}</p>
                      <p className="text-xs text-muted">
                        {formatRelativeDay(s.started_at)} · {formatDuration(s.duration_seconds)} · {s.total_sets} Sätze
                      </p>
                      <p className="mt-0.5 truncate text-xs text-faint">{s.exercise_names.join(" · ")}</p>
                    </div>
                    <span className="tnum shrink-0 text-sm text-muted">{formatVolume(s.total_volume, unit)}</span>
                    <ArrowRight className="h-4 w-4 shrink-0 text-faint" />
                  </Link>
                ))}
              </Card>
            </section>
          );
        })
      )}
    </div>
  );
}
