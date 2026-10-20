import { Card, CardContent } from "@/components/ui/card";
import { Wordmark } from "@/components/brand/logo";

/** Wird angezeigt, solange die Supabase-Umgebungsvariablen fehlen. */
export default function SetupPage() {
  return (
    <div className="flex min-h-dvh items-center justify-center bg-bg px-5">
      <div className="w-full max-w-lg space-y-6">
        <Wordmark />
        <Card>
          <CardContent className="space-y-4 pt-5">
            <h1 className="text-xl font-semibold tracking-tight">Supabase ist noch nicht konfiguriert</h1>
            <p className="text-sm text-muted">
              Lege eine Datei <code className="rounded bg-subtle px-1.5 py-0.5 text-xs">.env.local</code> im
              Projektordner an und trage Projekt-URL und Publishable Key ein. Beide Werte findest du im Supabase
              Dashboard unter <span className="text-fg">Project Settings → API</span>.
            </p>
            <pre className="overflow-x-auto rounded-xl border border-border bg-subtle p-4 text-xs leading-6 text-muted">
{`NEXT_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=sb_publishable_...`}
            </pre>
            <p className="text-sm text-muted">
              Danach den Dev-Server neu starten. Die Datenbank wird mit den SQL-Dateien unter{" "}
              <code className="rounded bg-subtle px-1.5 py-0.5 text-xs">supabase/migrations</code> eingerichtet
              (siehe README).
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
