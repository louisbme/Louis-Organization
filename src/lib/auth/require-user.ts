import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getProfile, getSettings } from "@/lib/services/profile";

/**
 * Liefert den angemeldeten Benutzer samt Profil und Einstellungen oder leitet zum Login um.
 * Per React cache() dedupliziert: Layout und Seite teilen sich innerhalb einer Anfrage einen Aufruf.
 */
export const requireUser = cache(async () => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  // Die Middleware prüft das Token nur lokal. Wurde die Sitzung serverseitig beendet
  // (z. B. Passwort durch einen Admin gesetzt), müssen die Cookies gelöscht werden,
  // sonst pendelt der Browser zwischen Login und Dashboard.
  if (!user) redirect("/auth/signout?reason=expired");

  const [profile, settings] = await Promise.all([getProfile(supabase, user.id), getSettings(supabase, user.id)]);

  return {
    supabase,
    user,
    profile: profile ?? { id: user.id, nickname: "Benutzer", role: "user" as const, created_at: user.created_at, updated_at: user.created_at },
    settings,
  };
});
