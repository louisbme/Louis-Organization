import type { DbClient } from "@/lib/supabase/db";
import type { QuoteRow } from "@/lib/supabase/types";

export async function listQuotes(db: DbClient): Promise<QuoteRow[]> {
  const { data, error } = await db.from("quotes").select("*").eq("active", true).order("created_at");
  if (error) throw error;
  return data ?? [];
}
