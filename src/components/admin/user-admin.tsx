"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Check, Dumbbell, KeyRound, Mail, Pencil, ShieldCheck, Trash2, UserRound, X } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import type { AdminUserRow } from "@/lib/supabase/types";
import { adminDeleteUser, adminSendPasswordReset, adminSetNickname, adminSetRole, adminUpdateAuth } from "@/lib/services/admin";
import { emailSchema, passwordSchema } from "@/lib/validation/auth";
import { formatDate, formatRelativeDay, formatVolume } from "@/lib/utils/format";
import { friendlyError } from "@/lib/utils/errors";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Sheet } from "@/components/ui/sheet";
import { Input } from "@/components/ui/input";
import { Field } from "@/components/ui/field";
import { Avatar } from "@/components/ui/avatar";

type AuthEdit = { user: AdminUserRow; kind: "email" | "password" };

export function UserAdmin({ users: initial }: { users: AdminUserRow[] }) {
  const router = useRouter();
  const { userId, settings } = useUser();
  const [users, setUsers] = React.useState(initial);
  const [confirm, setConfirm] = React.useState<AdminUserRow | null>(null);
  const [busy, setBusy] = React.useState<string | null>(null);
  const [editing, setEditing] = React.useState<{ id: string; value: string } | null>(null);
  const [authEdit, setAuthEdit] = React.useState<AuthEdit | null>(null);
  const [authValue, setAuthValue] = React.useState("");
  const [authConfirm, setAuthConfirm] = React.useState("");
  const [authError, setAuthError] = React.useState<string | null>(null);

  React.useEffect(() => setUsers(initial), [initial]);

  const saveNickname = async () => {
    if (!editing) return;
    const u = users.find((x) => x.user_id === editing.id);
    if (!u) return;
    const next = editing.value.trim();
    if (next === u.nickname) {
      setEditing(null);
      return;
    }
    setBusy(u.user_id);
    try {
      await adminSetNickname(createClient(), u.user_id, next);
      setUsers((list) => list.map((x) => (x.user_id === u.user_id ? { ...x, nickname: next } : x)));
      toast.success(`Nickname geändert: ${next}`);
      setEditing(null);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setBusy(null);
    }
  };

  const openAuth = (user: AdminUserRow, kind: "email" | "password") => {
    setAuthEdit({ user, kind });
    setAuthValue(kind === "email" ? user.email : "");
    setAuthConfirm("");
    setAuthError(null);
  };

  const saveAuth = async () => {
    if (!authEdit) return;
    const { user, kind } = authEdit;
    if (kind === "email") {
      const parsed = emailSchema.safeParse(authValue);
      if (!parsed.success) {
        setAuthError(parsed.error.issues[0]?.message ?? "Ungültige E-Mail");
        return;
      }
      if (parsed.data === user.email) {
        setAuthEdit(null);
        return;
      }
      setBusy(user.user_id);
      try {
        await adminUpdateAuth(user.user_id, { email: parsed.data });
        setUsers((list) => list.map((x) => (x.user_id === user.user_id ? { ...x, email: parsed.data } : x)));
        toast.success(`E-Mail von ${user.nickname} geändert`);
        setAuthEdit(null);
        router.refresh();
      } catch (e) {
        setAuthError(friendlyError(e));
      } finally {
        setBusy(null);
      }
      return;
    }
    const parsed = passwordSchema.safeParse(authValue);
    if (!parsed.success) {
      setAuthError(parsed.error.issues[0]?.message ?? "Ungültig");
      return;
    }
    if (authValue !== authConfirm) {
      setAuthError("Die Passwörter stimmen nicht überein");
      return;
    }
    setBusy(user.user_id);
    try {
      await adminUpdateAuth(user.user_id, { password: parsed.data });
      toast.success(`Passwort von ${user.nickname} gesetzt`);
      setAuthEdit(null);
    } catch (e) {
      setAuthError(friendlyError(e));
    } finally {
      setBusy(null);
    }
  };

  const sendReset = async (u: AdminUserRow) => {
    setBusy(u.user_id);
    try {
      await adminSendPasswordReset(createClient(), u.email, window.location.origin);
      toast.success(`Passwort-Reset-Mail an ${u.email} gesendet`);
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setBusy(null);
    }
  };

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
            <div className="flex items-start gap-3">
              <Avatar name={u.nickname} size={40} className="mt-0.5" />
              <div className="min-w-0 flex-1">
                {editing?.id === u.user_id ? (
                  <div className="flex items-center gap-2">
                    <Input
                      value={editing.value}
                      onChange={(e) => setEditing({ id: u.user_id, value: e.target.value })}
                      maxLength={20}
                      autoFocus
                      className="h-10"
                      onKeyDown={(e) => {
                        if (e.key === "Enter") saveNickname();
                        if (e.key === "Escape") setEditing(null);
                      }}
                      aria-label="Nickname"
                    />
                    <Button size="icon-sm" variant="secondary" onClick={saveNickname} loading={busy === u.user_id} aria-label="Nickname speichern">
                      <Check className="h-4 w-4" />
                    </Button>
                    <Button size="icon-sm" variant="ghost" onClick={() => setEditing(null)} aria-label="Abbrechen">
                      <X className="h-4 w-4" />
                    </Button>
                  </div>
                ) : (
                  <p className="flex items-center gap-2 truncate text-base font-semibold">
                    {u.nickname}
                    <button
                      type="button"
                      onClick={() => setEditing({ id: u.user_id, value: u.nickname })}
                      className="press flex h-7 w-7 items-center justify-center rounded-full text-faint hover:bg-subtle hover:text-fg"
                      aria-label="Nickname ändern"
                      title="Nickname ändern"
                    >
                      <Pencil className="h-3.5 w-3.5" />
                    </button>
                    {u.role === "admin" ? (
                      <Badge tone="accent">
                        <ShieldCheck className="mr-1 h-3 w-3" /> Admin
                      </Badge>
                    ) : null}
                    {self ? <Badge>Du</Badge> : null}
                  </p>
                )}
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
            <div className="mt-3 flex flex-wrap gap-2">
              <Link href={`/admin/users/${u.user_id}`}>
                <Button variant="secondary" size="sm">
                  <Dumbbell className="h-4 w-4" /> Trainingsdaten
                </Button>
              </Link>
              <Button variant="secondary" size="sm" onClick={() => openAuth(u, "email")} disabled={busy === u.user_id}>
                <Mail className="h-4 w-4" /> E-Mail
              </Button>
              <Button variant="secondary" size="sm" onClick={() => openAuth(u, "password")} disabled={busy === u.user_id}>
                <KeyRound className="h-4 w-4" /> Passwort
              </Button>
              <Button variant="ghost" size="sm" onClick={() => sendReset(u)} loading={busy === u.user_id} title="Sendet die Passwort-zurücksetzen-E-Mail">
                Reset-Mail
              </Button>
              <Button variant="ghost" size="sm" onClick={() => toggleRole(u)} loading={busy === u.user_id} disabled={self && u.role === "admin"}>
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
        open={authEdit !== null}
        onClose={() => setAuthEdit(null)}
        title={authEdit ? (authEdit.kind === "email" ? "E-Mail ändern" : "Passwort setzen") : ""}
        description={authEdit ? `${authEdit.user.nickname} · ${authEdit.user.email}` : undefined}
        footer={
          <Button fullWidth onClick={saveAuth} loading={busy !== null} disabled={!authValue}>
            Speichern
          </Button>
        }
      >
        {authEdit?.kind === "email" ? (
          <Field label="Neue E-Mail-Adresse" htmlFor="adminEmail" error={authError} hint="Wird sofort gesetzt und gilt als bestätigt, ohne Mail an den Nutzer.">
            <Input id="adminEmail" type="email" value={authValue} onChange={(e) => setAuthValue(e.target.value)} invalid={!!authError} autoFocus />
          </Field>
        ) : (
          <div className="space-y-4">
            <Field label="Neues Passwort" htmlFor="adminPw" error={authError} hint="Mindestens 8 Zeichen. Der Nutzer wird auf allen Geräten abgemeldet und kann das Passwort danach selbst ändern.">
              <Input id="adminPw" type="password" autoComplete="new-password" value={authValue} onChange={(e) => setAuthValue(e.target.value)} invalid={!!authError} autoFocus />
            </Field>
            <Field label="Passwort bestätigen" htmlFor="adminPw2">
              <Input id="adminPw2" type="password" autoComplete="new-password" value={authConfirm} onChange={(e) => setAuthConfirm(e.target.value)} />
            </Field>
          </div>
        )}
      </Sheet>

      <Sheet
        open={confirm !== null}
        onClose={() => setConfirm(null)}
        title={confirm ? `${confirm.nickname} löschen?` : ""}
        description="Konto, Pläne, Trainings, Sätze, Kalender und Favoriten werden dauerhaft entfernt."
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
    <div className="rounded-[var(--radius-control)] bg-subtle px-3 py-2">
      <p className="text-xs font-medium text-muted">{label}</p>
      <p className="tnum mt-0.5 text-sm font-semibold">{value}</p>
    </div>
  );
}
