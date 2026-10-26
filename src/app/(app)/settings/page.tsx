import { requireUser } from "@/lib/auth/require-user";
import { getLatestBodyWeight } from "@/lib/services/stats";
import { PageHeader } from "@/components/ui/page-header";
import { SettingsForm } from "@/components/settings/settings-form";

export const metadata = { title: "Einstellungen" };

export default async function SettingsPage() {
  const { supabase, user } = await requireUser();
  const bodyWeight = await getLatestBodyWeight(supabase, user.id).catch(() => null);
  return (
    <div>
      <PageHeader title="Einstellungen" backHref="/profile" backLabel="Profil" compact />
      <SettingsForm initialBodyWeight={bodyWeight} />
    </div>
  );
}
