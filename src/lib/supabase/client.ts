import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "@/lib/supabase/types";
import { getSupabaseEnv } from "@/lib/supabase/env";

let browserClient: ReturnType<typeof createBrowserClient<Database>> | null = null;

/** Supabase-Client für Client Components (Singleton pro Browser-Tab). */
export function createClient() {
  if (browserClient) return browserClient;
  const { url, anonKey } = getSupabaseEnv();
  browserClient = createBrowserClient<Database>(url, anonKey);
  return browserClient;
}
