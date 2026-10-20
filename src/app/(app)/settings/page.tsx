import { PageHeader } from "@/components/ui/page-header";
import { SettingsForm } from "@/components/settings/settings-form";

export const metadata = { title: "Einstellungen" };

export default function SettingsPage() {
  return (
    <div>
      <PageHeader title="Einstellungen" backHref="/profile" />
      <SettingsForm />
    </div>
  );
}
