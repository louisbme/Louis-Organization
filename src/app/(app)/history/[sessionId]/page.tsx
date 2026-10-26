import { Suspense } from "react";
import { notFound, redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/require-user";
import { getSessionDetail } from "@/lib/services/sessions";
import { getLatestBodyWeight } from "@/lib/services/stats";
import { getProfile } from "@/lib/services/profile";
import { formatDateTime, formatDuration, formatVolume } from "@/lib/utils/format";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardContent, SectionLabel } from "@/components/ui/card";
import { Stat } from "@/components/ui/stat";
import { SessionActions } from "@/components/history/session-actions";
import { SessionEditor } from "@/components/history/session-editor";

export const metadata = { title: "Training" };

export default async function SessionPage({ params }: { params: Promise<{ sessionId: string }> }) {
  const { sessionId } = await params;
  const { supabase, user, profile, settings } = await requireUser();
  const session = await getSessionDetail(supabase, sessionId);
  if (!session) notFound();
  const foreign = session.user_id !== user.id;
  // Fremde Trainings nur für Admins (RLS liefert sie sonst gar nicht)
  if (foreign && profile.role !== "admin") notFound();
  if (session.status === "active") {
    if (foreign) notFound();
    redirect(`/workout/${session.id}`);
  }
  const [bodyWeight, owner] = await Promise.all([
    getLatestBodyWeight(supabase, session.user_id).catch(() => null),
    foreign ? getProfile(supabase, session.user_id).catch(() => null) : Promise.resolve(null),
  ]);
  const unit = settings.weight_unit;

  return (
    <div className="space-y-5">
      <PageHeader
        title={session.name}
        eyebrow={foreign ? `Training von ${owner?.nickname ?? "Mitglied"} · Admin` : undefined}
        backHref={foreign ? `/admin/users/${session.user_id}` : "/history"}
        backLabel={foreign ? (owner?.nickname ?? "Zurück") : "Verlauf"}
        description={formatDateTime(session.started_at)}
        compact
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
            <p className="mt-1.5 whitespace-pre-wrap text-base leading-relaxed">{session.notes}</p>
          </CardContent>
        </Card>
      ) : null}

      <div>
        <SectionLabel className="mb-2 px-1">Übungen · tippen zum Bearbeiten</SectionLabel>
        <SessionEditor session={session} bodyWeight={bodyWeight?.weight ?? null} />
      </div>

      <Suspense>
        <SessionActions sessionId={session.id} notes={session.notes} backHref={foreign ? `/admin/users/${session.user_id}` : "/history"} />
      </Suspense>
    </div>
  );
}
