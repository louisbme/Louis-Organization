export function getSupabaseEnv() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    throw new Error(
      "Supabase ist nicht konfiguriert. Bitte NEXT_PUBLIC_SUPABASE_URL und NEXT_PUBLIC_SUPABASE_ANON_KEY in .env.local setzen."
    );
  }
  return { url, anonKey };
}

/**
 * Server-seitiger Service-Zugang (Secret Key) für Admin-Funktionen der Auth-API.
 * Niemals im Browser verwenden; die Variable hat bewusst kein NEXT_PUBLIC_-Präfix.
 */
export function getSupabaseAdminEnv() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const secretKey = process.env.SUPABASE_SECRET_KEY;
  if (!url || !secretKey) {
    throw new Error("SUPABASE_SECRET_KEY ist nicht gesetzt. E-Mail und Passwort anderer Nutzer können nur mit Service-Zugang geändert werden.");
  }
  return { url, secretKey };
}

export function isSupabaseConfigured() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
  return url.startsWith("https://") && !url.includes("YOUR-PROJECT-REF") && key.length > 20;
}
