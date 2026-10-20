import type { DbClient } from "@/lib/supabase/db";
import type { AdminUserRow, UserRole } from "@/lib/supabase/types";

export async function adminListUsers(db: DbClient): Promise<AdminUserRow[]> {
  const { data, error } = await db.rpc("admin_list_users");
  if (error) throw error;
  return (data ?? []).map((r) => ({ ...r, total_workouts: Number(r.total_workouts), total_volume: Number(r.total_volume) }));
}

export async function adminSetRole(db: DbClient, userId: string, role: UserRole): Promise<void> {
  const { error } = await db.rpc("admin_set_role", { p_user_id: userId, p_role: role });
  if (error) throw error;
}

export async function adminDeleteUser(db: DbClient, userId: string): Promise<void> {
  const { error } = await db.rpc("admin_delete_user", { p_user_id: userId });
  if (error) throw error;
}
