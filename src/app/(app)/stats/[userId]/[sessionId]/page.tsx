import Link from "next/link";
import { notFound } from "next/navigation";
import { Flame } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { getMemberSessionDetail } from "@/lib/services/stats";
import { formatDateTime, formatDuration, formatVolume, formatWeight } from "@/lib/utils/format";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardContent, SectionLabel } from "@/components/ui/card";
import { Stat } from "@/components/ui/stat";

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
      <PageHeader
        eyebrow={session.nickname}
        title={session.name}
        backHref={`/stats/${userId}`}
        description={formatDateTime(session.started_at)}
      />

      <div className="grid grid-cols-3 gap-3">
        <Stat label="Dauer" value={formatDuration(session.duration_seconds)} />
        <Stat label="Sätze" value={session.total_sets} />
        <Stat label="Volumen" value={formatVolume(session.total_volume, unit)} />
      </div>

      {session.notes ? (
        <Card>
          <CardContent className="pt-5">
            <SectionLabel>Notiz</SectionLabel>
            <p className="mt-1.5 whitespace-pre-wrap text-sm leading-relaxed">{session.notes}</p>
          </CardContent>
        </Card>
      ) : null}

      <div className="space-y-3">
        {exercises.map((se) => {
          const working = se.sets.filter((s) => !s.is_warmup);
          const volume = working.reduce((v, s) => v + s.weight * s.reps, 0);
          return (
            <Card key={se.id} className="overflow-hidden">
              <div className="flex items-start justify-between gap-3 px-5 pt-4">
                <div className="min-w-0">
                  <Link href={`/exercises/${se.exercise.slug}`} className="block truncate text-base font-semibold hover:text-accent">
                    {se.exercise.name}
                  </Link>
                  <p className="tnum text-xs text-muted">
                    Ziel {se.target_sets} × {se.rep_min}–{se.rep_max} · {working.length} Arbeitssätze
                  </p>
                </div>
                <span className="tnum shrink-0 text-sm text-muted">{formatVolume(volume, unit)}</span>
              </div>
              <table className="mt-3 w-full text-sm">
                <thead>
                  <tr className="border-t border-border text-left text-[11px] uppercase tracking-wider text-faint">
                    <th className="px-5 py-2 font-medium">Satz</th>
                    <th className="py-2 font-medium">Gewicht</th>
                    <th className="py-2 font-medium">Wdh</th>
                    {settings.show_rir ? <th className="py-2 font-medium">RIR</th> : null}
                    <th className="py-2 pr-5 text-right font-medium">Volumen</th>
                  </tr>
                </thead>
                <tbody className="tnum">
                  {se.sets.map((s) => (
                    <tr key={`${se.id}-${s.set_number}`} className="border-t border-border">
                      <td className="px-5 py-2 text-muted">
                        {s.set_number}
                        {s.is_warmup ? <Flame className="ml-1 inline h-3 w-3 text-warning" aria-label="Aufwärmsatz" /> : null}
                      </td>
                      <td className="py-2">{formatWeight(s.weight, unit)}</td>
                      <td className="py-2">{s.reps}</td>
                      {settings.show_rir ? <td className="py-2 text-muted">{s.rir ?? "–"}</td> : null}
                      <td className="py-2 pr-5 text-right text-muted">{s.is_warmup ? "–" : formatVolume(s.weight * s.reps, unit)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </Card>
          );
        })}
      </div>
    </div>
  );
}
