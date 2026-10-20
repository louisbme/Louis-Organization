import { requireUser } from "@/lib/auth/require-user";
import { getActiveSession } from "@/lib/services/sessions";
import { UserProvider } from "@/lib/context/user-context";
import { ThemeSync } from "@/components/theme/theme-sync";
import { AppShell } from "@/components/nav/app-shell";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const { supabase, user, profile, settings } = await requireUser();
  const activeSession = await getActiveSession(supabase, user.id).catch(() => null);

  return (
    <UserProvider value={{ userId: user.id, email: user.email ?? "", profile, settings }}>
      <ThemeSync theme={settings.theme} />
      <AppShell activeSession={activeSession ? { id: activeSession.id, name: activeSession.name } : null}>
        {children}
      </AppShell>
    </UserProvider>
  );
}
