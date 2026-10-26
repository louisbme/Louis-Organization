import { Suspense } from "react";
import Link from "next/link";
import { ChevronDown, Plus } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { listExercises } from "@/lib/services/exercises";
import { PageHeader } from "@/components/ui/page-header";
import { Button } from "@/components/ui/button";
import { AvatarLink } from "@/components/ui/avatar";
import { LoadingBlock } from "@/components/ui/states";
import { ExerciseBrowser } from "@/components/exercise/exercise-browser";

export const metadata = { title: "Übungen" };

export default async function ExercisesPage() {
  const { supabase, user, profile } = await requireUser();
  const items = await listExercises(supabase, user.id);
  return (
    <div>
      <PageHeader
        title="Übungen"
        description={`${items.length} Übungen nach Muskelgruppen`}
        actions={
          <>
            <Link href="/exercises/new" aria-label="Eigene Übung erstellen">
              <Button variant="secondary" size="icon-sm">
                <Plus className="h-5 w-5" strokeWidth={2.4} />
              </Button>
            </Link>
            <AvatarLink name={profile.nickname} className="lg:hidden" />
          </>
        }
      />
      <Suspense fallback={<LoadingBlock />}>
        <ExerciseBrowser items={items} />
      </Suspense>

      <details className="group mt-6 rounded-[var(--radius-card)] bg-card">
        <summary className="flex cursor-pointer list-none items-center justify-between gap-3 px-5 py-4 text-base font-semibold [&::-webkit-details-marker]:hidden">
          Grundsätze für Muskelaufbau
          <ChevronDown className="h-5 w-5 text-faint transition-transform group-open:rotate-180" strokeWidth={2.4} />
        </summary>
        <ul className="space-y-2.5 px-5 pb-5 text-sm leading-relaxed text-muted">
          <li><span className="font-semibold text-fg">Eine Übung je Bewegung.</span> Maschinen, Griffe oder Winkel sind Varianten derselben Übung und stehen in der Übung erklärt, nicht als Dubletten im Katalog.</li>
          <li><span className="font-semibold text-fg">Voller Bewegungsradius mit Betonung der Dehnung.</span> Muskeln wachsen am stärksten, wenn sie in gedehnter Position unter Last stehen; dort kontrolliert ankommen und kurz halten.</li>
          <li><span className="font-semibold text-fg">Nahe ans Muskelversagen.</span> 5 bis 30 Wiederholungen bauen Muskeln gleich gut auf, solange der Satz 0 bis 3 Wiederholungen vor dem Versagen endet. Die App schlägt die Gewichtssteigerung vor, sobald alle Sätze das obere Ende des Bereichs erreichen.</li>
          <li><span className="font-semibold text-fg">Kontrollierte Exzentrik.</span> 2 bis 3 Sekunden absenken, zügig heben, kein Schwung.</li>
          <li><span className="font-semibold text-fg">Volumen und Frequenz.</span> Etwa 10 bis 20 harte Sätze je Muskel und Woche, verteilt auf zwei Einheiten, mit 1 bis 3 Minuten Pause.</li>
        </ul>
      </details>
    </div>
  );
}
