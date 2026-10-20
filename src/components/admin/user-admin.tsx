"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { ShieldCheck, Trash2, UserRound } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import type { AdminUserRow } from "@/lib/supabase/types";
import { adminDeleteUser, adminSetRole } from "@/lib/services/admin";
import { formatDate, formatRelativeDay, formatVolume } from "@/lib/utils/format";
import { friendlyError } from "@/lib/utils/errors";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Sheet } from "@/components/ui/sheet";

export function UserAdmin({ users: initial }: { users: AdminUserRow[] }) {
  const router = useRouter();
  const { userId, settings } = useUser();
  const [users, setUsers] = React.useState(initial);
  const [confirm, setConfirm] = React.useState<AdminUserRow | null>(null);
  const [busy, setBusy] = React.useState<string | null>(null);

  React.useEffect(() => setUsers(initial), [initial]);

  const toggleRole = async (u: AdminUserRow) => {
    const next = u.role === "admin" ? "user" : "admin";
    setBusy(u.user_id);
    try {
      await adminSetRole(createClient(), u.user_id, next);
      setUsers((list) => list.map((x) => (x.user_id === u.user_id ? { ...x, role: next } : x)));
      toast.success(next === "admin" ? `${u.nickname} ist jetzt Admin` : `${u.nickname} ist jetzt normaler Nutzer`);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setBusy(null);
    }
  };

  const remove = async () => {
    if (!confirm) return;
    setBusy(confirm.user_id);
    try {
      await adminDeleteUser(createClient(), confirm.user_id);
      setUsers((list) => list.filter((x) => x.user_id !== confirm.user_id));
      toast.success(`${confirm.nickname} wurde gelöscht`);
      setConfirm(null);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="stagger space-y-3">
      {users.map((u) => {
        const self = u.user_id === userId;
        return (
          <Card key={u.user_id} className="px-5 py-4">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="flex items-center gap-2 truncate text-base font-semibold">
                  {u.nickname}
                  {u.role === "admin" ? (
                    <Badge tone="accent">
                      <ShieldCheck className="mr-1 h-3 w-3" /> Admin
                    </Badge>
                  ) : null}
                  {self ? <Badge>Du</Badge> : null}
                </p>
                <p className="truncate text-sm text-muted">{u.email}</p>
                <p className="mt-1 text-xs text-faint">
                  Registriert {formatDate(u.created_at)}
                  {u.last_sign_in_at ? ` · Zuletzt aktiv ${formatRelativeDay(u.last_sign_in_at).toLowerCase()}` : " · Noch nie angemeldet"}
                </p>
              </div>
            </div>
            <div className="mt-3 grid grid-cols-2 gap-2">
              <Cell label="Trainings" value={String(u.total_workouts)} />
              <Cell label="Volumen" value={formatVolume(u.total_volume, settings.weight_unit)} />
            </div>
            <div className="mt-3 flex gap-2">
              <Button variant="secondary" size="sm" onClick={() => toggleRole(u)} loading={busy === u.user_id} disabled={self && u.role === "admin"}>
                {u.role === "admin" ? (
                  <>
                    <UserRound className="h-4 w-4" /> Zu Nutzer machen
                  </>
                ) : (
                  <>
                    <ShieldCheck className="h-4 w-4" /> Zu Admin machen
                  </>
                )}
              </Button>
              <Button variant="danger" size="sm" onClick={() => setConfirm(u)} disabled={self || busy === u.user_id}>
                <Trash2 className="h-4 w-4" /> Löschen
              </Button>
            </div>
          </Card>
        );
      })}

      <Sheet
        open={confirm !== null}
        onClose={() => setConfirm(null)}
        title={confirm ? `${confirm.nickname} löschen?` : ""}
        description="Konto, Pläne, Trainings, Sätze, Kalender und eigene Übungen werden dauerhaft entfernt."
        footer={
          <div className="flex gap-2">
            <Button variant="secondary" fullWidth onClick={() => setConfirm(null)}>
              Abbrechen
            </Button>
            <Button variant="danger" fullWidth onClick={remove} loading={busy !== null}>
              Endgültig löschen
            </Button>
          </div>
        }
      >
        <div />
      </Sheet>
    </div>
  );
}

function Cell({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg bg-subtle px-3 py-2">
      <p className="text-[10px] font-medium uppercase tracking-wider text-faint">{label}</p>
      <p className="tnum mt-0.5 text-sm font-semibold">{value}</p>
    </div>
  );
}
