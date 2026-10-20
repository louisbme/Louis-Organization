import Link from "next/link";
import { Settings, ChevronRight } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { getUserStats } from "@/lib/services/stats";
import { formatDate, formatDuration, formatRelativeDay, formatVolume } from "@/lib/utils/format";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardContent, SectionLabel } from "@/components/ui/card";
import { Stat } from "@/components/ui/stat";
import { Button } from "@/components/ui/button";

export const metadata = { title: "Profil" };

export default async function ProfilePage() {
  const { supabase, user, profile, settings } = await requireUser();
  const stats = await getUserStats(supabase);
  const unit = settings.weight_unit;

  return (
    <div className="stagger space-y-5">
      <PageHeader
        title={profile.nickname}
        eyebrow="Profil"
        actions={
          <Link href="/settings">
            <Button variant="secondary" size="sm">
              <Settings className="h-4 w-4" /> Einstellungen
            </Button>
          </Link>
        }
      />

      <Card>
        <CardContent className="pt-5">
          <dl className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div>
              <dt className="text-xs font-medium text-faint">Nickname</dt>
              <dd className="mt-0.5 text-sm font-medium">{profile.nickname}</dd>
            </div>
            <div>
              <dt className="text-xs font-medium text-faint">E-Mail</dt>
              <dd className="mt-0.5 truncate text-sm font-medium">{user.email}</dd>
            </div>
            <div>
              <dt className="text-xs font-medium text-faint">Konto erstellt</dt>
              <dd className="mt-0.5 text-sm font-medium">{formatDate(profile.created_at)}</dd>
            </div>
          </dl>
        </CardContent>
      </Card>

      <section>
        <SectionLabel className="mb-2 px-1">Trainingsstatistiken</SectionLabel>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <Stat label="Trainings gesamt" value={stats.total_workouts} hint={stats.last_workout_at ? `Zuletzt ${formatRelativeDay(stats.last_workout_at).toLowerCase()}` : undefined} />
          <Stat label="Trainingszeit" value={formatDuration(stats.total_duration_seconds)} />
          <Stat label="Gesamtvolumen" value={formatVolume(stats.total_volume, unit)} />
          <Stat label="Sätze" value={stats.total_sets} />
          <Stat label="Übungen trainiert" value={stats.distinct_exercises} />
        </div>
      </section>

      <Card className="divide-y divide-border overflow-hidden">
        <Row href="/settings" label="Persönliche Einstellungen" hint="Nickname, Passwort, E-Mail, Einheiten, Timer, Theme" />
        <Row href="/stats" label="Gruppen-Stats" hint="Private Übersicht aller Mitglieder" />
      </Card>
    </div>
  );
}

function Row({ href, label, hint }: { href: string; label: string; hint: string }) {
  return (
    <Link href={href} className="flex items-center justify-between gap-3 px-5 py-4 hover:bg-subtle">
      <div>
        <p className="text-sm font-medium">{label}</p>
        <p className="text-xs text-muted">{hint}</p>
      </div>
      <ChevronRight className="h-4 w-4 text-faint" />
    </Link>
  );
}
