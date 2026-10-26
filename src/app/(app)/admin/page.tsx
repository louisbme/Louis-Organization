import Link from "next/link";
import { redirect } from "next/navigation";
import { BookOpen, ChevronRight, ExternalLink } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { adminListUsers } from "@/lib/services/admin";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardContent, SectionLabel } from "@/components/ui/card";
import { UserAdmin } from "@/components/admin/user-admin";

export const metadata = { title: "Verwaltung" };

export default async function AdminPage() {
  const { supabase, profile } = await requireUser();
  if (profile.role !== "admin") redirect("/dashboard");
  const users = await adminListUsers(supabase);

  return (
    <div className="space-y-6">
      <PageHeader title="Verwaltung" description={`${users.length} registrierte Nutzer. Nur für Admins sichtbar.`} />

      <section>
        <SectionLabel className="mb-2 px-1">Nutzer</SectionLabel>
        <UserAdmin users={users} />
      </section>

      <section>
        <SectionLabel className="mb-2 px-1">Standardübungen</SectionLabel>
        <Card>
          <CardContent className="space-y-3 pt-5">
            <p className="text-sm text-muted">
              Als Admin kannst du jede Standardübung über das normale Bearbeiten-Formular anpassen (Texte, Muskeln, Griff, Muskelfokus, Ausstattung). Die Änderung gilt sofort für alle Nutzer.
            </p>
            <p className="text-xs text-faint">
              Hinweis: Wird der Übungs-Seed später erneut eingespielt, überschreibt er diese Änderungen. Dauerhafte Änderungen gehören zusätzlich in die Seed-Dateien im Repository.
            </p>
            <Link href="/exercises" className="press flex items-center justify-between rounded-[var(--radius-control)] bg-subtle px-4 py-3 text-sm font-medium hover:bg-hover">
              <span className="flex items-center gap-2">
                <BookOpen className="h-4 w-4 text-muted" /> Zur Übungsdatenbank
              </span>
              <ChevronRight className="h-4 w-4 text-faint" />
            </Link>
          </CardContent>
        </Card>
      </section>

      <section>
        <SectionLabel className="mb-2 px-1">Konten und Passwörter</SectionLabel>
        <Card>
          <CardContent className="pt-5">
            <p className="text-sm text-muted">
              Nickname, E-Mail und Passwort setzt du direkt in der Nutzerliste; Trainings und Pläne öffnest du über „Trainingsdaten“. Einladungen und Sperren laufen weiterhin über das Supabase-Dashboard.
            </p>
            <a
              href="https://supabase.com/dashboard/project/kmufqcgqsqewhupsycoi/auth/users"
              target="_blank"
              rel="noreferrer"
              className="press mt-3 flex items-center justify-between rounded-[var(--radius-control)] bg-subtle px-4 py-3 text-sm font-medium hover:bg-hover"
            >
              Supabase Dashboard öffnen
              <ExternalLink className="h-4 w-4 text-faint" />
            </a>
          </CardContent>
        </Card>
      </section>
    </div>
  );
}
