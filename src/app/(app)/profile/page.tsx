import Link from "next/link";
import { Settings } from "lucide-react";
import { differenceInYears } from "date-fns";
import { requireUser } from "@/lib/auth/require-user";
import { getLatestBodyWeight, getUserStats } from "@/lib/services/stats";
import { formatDate, formatDecimal, formatDuration, formatRelativeDay, formatVolume, formatWeight } from "@/lib/utils/format";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardContent } from "@/components/ui/card";
import { Stat } from "@/components/ui/stat";
import { Button } from "@/components/ui/button";
import { Avatar } from "@/components/ui/avatar";
import { List, ListHeader, ListRow } from "@/components/ui/list";

export const metadata = { title: "Profil" };

export default async function ProfilePage() {
  const { supabase, user, profile, settings } = await requireUser();
  const [stats, bodyWeight] = await Promise.all([getUserStats(supabase), getLatestBodyWeight(supabase, user.id).catch(() => null)]);
  const unit = settings.weight_unit;
  const height = profile.height_cm;
  const bmi = bodyWeight && height ? bodyWeight.weight / Math.pow(height / 100, 2) : null;
  const age = profile.birth_date ? differenceInYears(new Date(), new Date(profile.birth_date)) : null;

  return (
    <div className="stagger space-y-5">
      <PageHeader
        title={profile.nickname}
        eyebrow="Profil"
        actions={
          <Link href="/settings" aria-label="Einstellungen">
            <Button variant="secondary" size="icon-sm">
              <Settings className="h-5 w-5" strokeWidth={2.2} />
            </Button>
          </Link>
        }
      />

      <Card>
        <CardContent className="flex items-center gap-4 pt-5">
          <Avatar name={profile.nickname} size={56} />
          <dl className="min-w-0 flex-1 space-y-1">
            <div className="flex justify-between gap-3 text-sm">
              <dt className="shrink-0 text-muted">E-Mail</dt>
              <dd className="min-w-0 truncate font-medium">{user.email}</dd>
            </div>
            <div className="flex justify-between gap-3 text-sm">
              <dt className="shrink-0 text-muted">Dabei seit</dt>
              <dd className="font-medium">{formatDate(profile.created_at)}</dd>
            </div>
          </dl>
        </CardContent>
      </Card>

      <section>
        <ListHeader
          trailing={
            <Link href="/settings" className="font-semibold text-accent">
              Bearbeiten
            </Link>
          }
        >
          Körperdaten
        </ListHeader>
        <div className="grid grid-cols-2 gap-3">
          <Stat label="Gewicht" value={bodyWeight ? formatWeight(bodyWeight.weight, unit) : "–"} hint={bodyWeight ? `Stand ${formatDate(bodyWeight.entry_date)}` : "In den Einstellungen eintragen"} />
          <Stat label="Größe" value={height ? `${formatDecimal(height)} cm` : "–"} />
          <Stat label="BMI" value={bmi ? formatDecimal(Math.round(bmi * 10) / 10) : "–"} hint={bmi ? "Gewicht ÷ Größe²" : "Braucht Gewicht und Größe"} />
          <Stat label="Alter" value={age !== null ? `${age} Jahre` : "–"} />
        </div>
        <p className="mt-2 px-1 text-xs text-faint">Das Gewicht wird bei Körpergewichtsübungen für die reale Last verwendet.</p>
      </section>

      <section>
        <ListHeader>Trainingsstatistiken</ListHeader>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <Stat label="Trainings gesamt" value={stats.total_workouts} hint={stats.last_workout_at ? `Zuletzt ${formatRelativeDay(stats.last_workout_at).toLowerCase()}` : undefined} />
          <Stat label="Trainingszeit" value={formatDuration(stats.total_duration_seconds)} />
          <Stat label="Gesamtvolumen" value={formatVolume(stats.total_volume, unit)} />
          <Stat label="Sätze" value={stats.total_sets} />
          <Stat label="Übungen trainiert" value={stats.distinct_exercises} />
        </div>
      </section>

      <List>
        <ListRow href="/settings" title="Einstellungen" subtitle="Nickname, Passwort, E-Mail, Körperdaten, Einheiten, Timer, Theme" chevron />
        <ListRow href="/stats" title="Gruppen-Stats" subtitle="Private Übersicht aller Mitglieder" chevron />
      </List>
    </div>
  );
}
