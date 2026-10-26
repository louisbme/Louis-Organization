import "server-only";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/types";
import { getSupabaseAdminEnv } from "@/lib/supabase/env";

/**
 * Supabase-Client mit Service-Rechten (Secret Key). Nur in Route Handlern und Server Actions,
 * und nur nachdem die Admin-Rolle des aufrufenden Nutzers geprüft wurde.
 */
export function createAdminClient() {
  const { url, secretKey } = getSupabaseAdminEnv();
  return createSupabaseClient<Database>(url, secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
