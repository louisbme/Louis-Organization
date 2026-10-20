import Link from "next/link";
import { requireUser } from "@/lib/auth/require-user";
import { getGroupStats } from "@/lib/services/stats";
import { formatDate, formatDuration, formatVolume, formatRelativeDay } from "@/lib/utils/format";
import { PageHeader } from "@/components/ui/page-header";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Stat } from "@/components/ui/stat";
import { EmptyState } from "@/components/ui/states";

export const metadata = { title: "Stats" };

export default async function StatsPage() {
  const { supabase, user, settings } = await requireUser();
  const rows = await getGroupStats(supabase);
  const unit = settings.weight_unit;

  return (
    <div>
      <PageHeader title="Stats" description="Private Übersicht aller Mitglieder dieser Gruppe. Keine öffentliche Rangliste." />
      {rows.length === 0 ? (
        <EmptyState title="Noch keine Daten" />
      ) : (
        <div className="stagger space-y-3">
          {rows.map((r) => (
            <Card key={r.user_id} className="px-5 py-4">
              <div className="min-w-0">
                <p className="flex items-center gap-2 truncate text-base font-semibold">
                  {r.nickname}
                  {r.user_id === user.id ? <Badge tone="accent">Du</Badge> : null}
                </p>
                <p className="text-xs text-muted">Dabei seit {formatDate(r.member_since)}</p>
              </div>
              <Stat label="Gesamtvolumen" value={formatVolume(r.total_volume, unit)} className="mt-4" />
              <div className="mt-3 grid grid-cols-3 gap-2">
                <Cell label="Trainings" value={String(r.total_workouts)} />
                <Cell label="Trainingszeit" value={formatDuration(r.total_duration_seconds)} />
                <Cell label="Letztes Training" value={r.last_workout_at ? formatRelativeDay(r.last_workout_at) : "–"} />
              </div>
              <Link href={`/stats/${r.user_id}`} className="mt-4 block">
                <Button variant="secondary" fullWidth>
                  Mehr sehen
                </Button>
              </Link>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}

function Cell({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0 rounded-lg bg-subtle px-3 py-2">
      <p className="text-[10px] font-medium uppercase tracking-wider text-faint">{label}</p>
      <p className="tnum mt-0.5 text-sm font-semibold">{value}</p>
    </div>
  );
}
