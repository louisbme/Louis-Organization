import Link from "next/link";
import { notFound } from "next/navigation";
import { Flame } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { getMemberSessionDetail } from "@/lib/services/stats";
import { formatDateTime, formatDuration, formatVolume } from "@/lib/utils/format";
import { describeBodyweight, describeSet, formatTarget, setVolume } from "@/lib/utils/tracking";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardContent, SectionLabel } from "@/components/ui/card";
import { Stat } from "@/components/ui/stat";
import { Badge } from "@/components/ui/badge";

export const metadata = { title: "Training" };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function MemberSessionPage({ params }: { params: Promise<{ userId: string; sessionId: string }> }) {
  const { userId, sessionId } = await params;
  if (!UUID_RE.test(userId) || !UUID_RE.test(sessionId)) notFound();
  const { supabase, settings } = await requireUser();
  const detail = await getMemberSessionDetail(supabase, sessionId);
  if (!detail || detail.session.user_id !== userId) notFound();
  const { session, exercises } = detail;
  const unit = settings.weight_unit;

  return (
    <div className="space-y-5">
      <PageHeader eyebrow={session.nickname} title={session.name} backHref={`/stats/${userId}`} backLabel={session.nickname} description={formatDateTime(session.started_at)} compact />

      <div className="grid grid-cols-3 gap-3">
        <Stat label="Dauer" value={formatDuration(session.duration_seconds)} />
        <Stat label="Sätze" value={session.total_sets} />
        <Stat label="Volumen" value={formatVolume(session.total_volume, unit)} />
      </div>

      {session.notes ? (
        <Card>
          <CardContent className="pt-5">
            <SectionLabel>Notiz</SectionLabel>
            <p className="mt-1.5 whitespace-pre-wrap text-base leading-relaxed">{session.notes}</p>
          </CardContent>
        </Card>
      ) : null}

      <div className="space-y-3">
        {exercises.map((se) => {
          const mode = se.exercise.tracking_mode;
          const working = se.sets.filter((s) => !s.is_warmup);
          const volume = working.reduce((v, s) => v + setVolume(mode, s), 0);
          return (
            <Card key={se.id} className="overflow-hidden">
              <div className="flex items-start justify-between gap-3 px-5 pt-4">
                <div className="min-w-0">
                  <Link href={`/exercises/${se.exercise.slug}`} className="block truncate text-base font-semibold hover:text-accent">
                    {se.exercise.name}
                  </Link>
                  <p className="tnum text-sm text-muted">
                    Ziel {formatTarget(mode, se.target_sets, se.rep_min, se.rep_max)} · {working.length} {mode === "cardio" ? "Einheiten" : "Arbeitssätze"}
                  </p>
                </div>
                {mode !== "cardio" ? <span className="tnum shrink-0 text-sm text-muted">{formatVolume(volume, unit)}</span> : null}
              </div>
              <div className="mt-3 border-t border-border">
                {se.sets.map((s) => {
                  const bwInfo = mode === "bodyweight" ? describeBodyweight(s, 1, unit) : null;
                  return (
                    <div
                      key={`${se.id}-${s.set_number}`}
                      className="relative flex min-h-[48px] items-center gap-3 px-5 py-2 after:absolute after:bottom-0 after:left-[68px] after:right-0 after:h-px after:bg-border after:content-[''] last:after:hidden"
                    >
                      <span className="tnum flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-subtle text-sm font-semibold text-muted">{s.set_number}</span>
                      <span className="min-w-0 flex-1">
                        <span className="tnum block text-base">
                          {describeSet(mode, s, unit)}
                          {settings.show_rir && s.rir !== null && mode !== "cardio" ? <span className="ml-2 text-sm text-muted">RIR {s.rir}</span> : null}
                        </span>
                        {bwInfo && s.body_weight ? <span className="tnum block truncate text-xs text-faint">Körpergewicht {bwInfo.split(" × ")[0]}{s.extra_weight ? ` · Zusatz ${s.extra_weight > 0 ? "+" : "−"}${Math.abs(s.extra_weight)} ${unit}` : ""}</span> : null}
                      </span>
                      {s.is_warmup ? (
                        <Badge tone="warning">
                          <Flame className="mr-1 h-3 w-3" /> Aufwärmen
                        </Badge>
                      ) : null}
                    </div>
                  );
                })}
              </div>
            </Card>
          );
        })}
      </div>
    </div>
  );
}
