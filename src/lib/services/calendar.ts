import type { DbClient } from "@/lib/supabase/db";
import type { CalendarEntryRow, CalendarEntryType } from "@/lib/supabase/types";

export async function listCalendarEntries(
  db: DbClient,
  userId: string,
  fromKey: string,
  toKey: string
): Promise<CalendarEntryRow[]> {
  const { data, error } = await db
    .from("calendar_entries")
    .select("*")
    .eq("user_id", userId)
    .gte("entry_date", fromKey)
    .lte("entry_date", toKey)
    .order("entry_date");
  if (error) throw error;
  return data ?? [];
}

export async function upsertCalendarEntry(
  db: DbClient,
  userId: string,
  entryDate: string,
  entryType: CalendarEntryType,
  note: string | null
): Promise<CalendarEntryRow> {
  const { data, error } = await db
    .from("calendar_entries")
    .upsert({ user_id: userId, entry_date: entryDate, entry_type: entryType, note }, { onConflict: "user_id,entry_date" })
    .select("*")
    .single();
  if (error) throw error;
  return data;
}

export async function deleteCalendarEntry(db: DbClient, id: string): Promise<void> {
  const { error } = await db.from("calendar_entries").delete().eq("id", id);
  if (error) throw error;
}
