import type { DbClient } from "@/lib/supabase/db";
import type { ProfileRow, UserSettingsRow, TablesUpdate } from "@/lib/supabase/types";

export async function getProfile(db: DbClient, userId: string): Promise<ProfileRow | null> {
  const { data, error } = await db.from("profiles").select("*").eq("id", userId).maybeSingle();
  if (error) throw error;
  return data;
}

export async function getSettings(db: DbClient, userId: string): Promise<UserSettingsRow> {
  const { data, error } = await db.from("user_settings").select("*").eq("user_id", userId).maybeSingle();
  if (error) throw error;
  if (data) return data;
  const { data: created, error: insertError } = await db
    .from("user_settings")
    .insert({ user_id: userId })
    .select("*")
    .single();
  if (insertError) throw insertError;
  return created;
}

/** Körperdaten im Profil (Größe, Geburtsdatum). Das Gewicht wird als Eintrag in body_weight_entries geführt. */
export async function updateBodyData(
  db: DbClient,
  userId: string,
  patch: { height_cm?: number | null; birth_date?: string | null }
): Promise<void> {
  const { error } = await db.from("profiles").update(patch).eq("id", userId);
  if (error) throw error;
}

export async function updateNickname(db: DbClient, userId: string, nickname: string): Promise<void> {
  const { error } = await db.from("profiles").update({ nickname }).eq("id", userId);
  if (error) throw error;
}

export async function updateSettings(
  db: DbClient,
  userId: string,
  patch: TablesUpdate<"user_settings">
): Promise<UserSettingsRow> {
  const { data, error } = await db.from("user_settings").update(patch).eq("user_id", userId).select("*").single();
  if (error) throw error;
  return data;
}
