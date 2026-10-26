"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { LogOut } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import type { ThemePreference, WeightUnit } from "@/lib/supabase/types";
import { updateNickname, updateSettings } from "@/lib/services/profile";
import { emailSchema, nicknameSchema, passwordSchema } from "@/lib/validation/auth";
import { friendlyError } from "@/lib/utils/errors";
import { applyTheme } from "@/components/theme/theme-sync";
import { REST_PRESETS } from "@/components/workout/use-rest-timer";
import { Button } from "@/components/ui/button";
import { Card, CardContent, SectionLabel } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Segmented } from "@/components/ui/segmented";

export function SettingsForm() {
  const router = useRouter();
  const { userId, email, profile, settings } = useUser();
  const db = React.useMemo(() => createClient(), []);

  const [nickname, setNickname] = React.useState(profile.nickname);
  const [nickBusy, setNickBusy] = React.useState(false);
  const [nickError, setNickError] = React.useState<string | null>(null);

  const [newEmail, setNewEmail] = React.useState(email);
  const [emailBusy, setEmailBusy] = React.useState(false);

  const [pw, setPw] = React.useState({ next: "", confirm: "" });
  const [pwBusy, setPwBusy] = React.useState(false);
  const [pwError, setPwError] = React.useState<string | null>(null);

  const [unit, setUnit] = React.useState<WeightUnit>(settings.weight_unit);
  const [step, setStep] = React.useState(String(settings.weight_step));
  const [rest, setRest] = React.useState(settings.rest_timer_default);
  const [showRir, setShowRir] = React.useState(settings.show_rir);
  const [theme, setTheme] = React.useState<ThemePreference>(settings.theme);

  const saveNick = async () => {
    const parsed = nicknameSchema.safeParse(nickname);
    if (!parsed.success) {
      setNickError(parsed.error.issues[0]?.message ?? "Ungültig");
      return;
    }
    setNickError(null);
    if (parsed.data === profile.nickname) return;
    setNickBusy(true);
    try {
      const { data: available } = await db.rpc("is_nickname_available", { p_nickname: parsed.data });
      if (!available) {
        setNickError("Dieser Nickname ist bereits vergeben");
        return;
      }
      await updateNickname(db, userId, parsed.data);
      toast.success("Nickname geändert");
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setNickBusy(false);
    }
  };

  const saveEmail = async () => {
    const parsed = emailSchema.safeParse(newEmail);
    if (!parsed.success) {
      toast.error(parsed.error.issues[0]?.message ?? "Ungültige E-Mail");
      return;
    }
    if (parsed.data === email) return;
    setEmailBusy(true);
    try {
      const { error } = await db.auth.updateUser({ email: parsed.data }, { emailRedirectTo: `${window.location.origin}/auth/callback?next=/settings` });
      if (error) throw error;
      toast.success("Bestätigungs-E-Mail gesendet. Die Änderung wird nach Bestätigung aktiv.");
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setEmailBusy(false);
    }
  };

  const savePassword = async () => {
    const parsed = passwordSchema.safeParse(pw.next);
    if (!parsed.success) {
      setPwError(parsed.error.issues[0]?.message ?? "Ungültig");
      return;
    }
    if (pw.next !== pw.confirm) {
      setPwError("Die Passwörter stimmen nicht überein");
      return;
    }
    setPwError(null);
    setPwBusy(true);
    try {
      const { error } = await db.auth.updateUser({ password: pw.next });
      if (error) throw error;
      setPw({ next: "", confirm: "" });
      toast.success("Passwort geändert");
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setPwBusy(false);
    }
  };

  const persistTraining = async (patch: Partial<{ weight_unit: WeightUnit; weight_step: number; rest_timer_default: number; show_rir: boolean; theme: ThemePreference }>) => {
    try {
      await updateSettings(db, userId, patch);
      router.refresh();
    } catch (e) {
      toast.error(friendlyError(e));
    }
  };

  const onUnit = (v: WeightUnit) => {
    setUnit(v);
    persistTraining({ weight_unit: v });
  };
  const onStepBlur = () => {
    const v = parseFloat(step.replace(",", "."));
    if (!v || v <= 0 || v > 50) {
      setStep(String(settings.weight_step));
      return;
    }
    persistTraining({ weight_step: v });
  };
  const onRest = (v: number) => {
    setRest(v);
    persistTraining({ rest_timer_default: v });
  };
  const onRir = (v: boolean) => {
    setShowRir(v);
    persistTraining({ show_rir: v });
  };
  const onTheme = (v: ThemePreference) => {
    setTheme(v);
    applyTheme(v);
    persistTraining({ theme: v });
  };

  return (
    <div className="space-y-5">
      <Card>
        <CardContent className="space-y-4 pt-5">
          <SectionLabel>Konto</SectionLabel>
          <Field label="Nickname" htmlFor="nickname" error={nickError} hint="3–20 Zeichen, keine E-Mail-Adresse">
            <div className="flex gap-2">
              <Input id="nickname" value={nickname} onChange={(e) => setNickname(e.target.value)} maxLength={20} invalid={!!nickError} />
              <Button variant="secondary" onClick={saveNick} loading={nickBusy} disabled={nickname.trim() === profile.nickname}>
                Speichern
              </Button>
            </div>
          </Field>
          <Field label="E-Mail" htmlFor="email" hint="Die neue Adresse muss per Link bestätigt werden.">
            <div className="flex gap-2">
              <Input id="email" type="email" value={newEmail} onChange={(e) => setNewEmail(e.target.value)} />
              <Button variant="secondary" onClick={saveEmail} loading={emailBusy} disabled={newEmail.trim() === email}>
                Ändern
              </Button>
            </div>
          </Field>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="space-y-4 pt-5">
          <SectionLabel>Passwort ändern</SectionLabel>
          <Field label="Neues Passwort" htmlFor="pwNext" error={pwError}>
            <Input id="pwNext" type="password" autoComplete="new-password" value={pw.next} onChange={(e) => setPw((p) => ({ ...p, next: e.target.value }))} invalid={!!pwError} />
          </Field>
          <Field label="Passwort bestätigen" htmlFor="pwConfirm">
            <Input id="pwConfirm" type="password" autoComplete="new-password" value={pw.confirm} onChange={(e) => setPw((p) => ({ ...p, confirm: e.target.value }))} />
          </Field>
          <Button variant="secondary" onClick={savePassword} loading={pwBusy} disabled={!pw.next}>
            Passwort speichern
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="space-y-5 pt-5">
          <SectionLabel>Training</SectionLabel>
          <div>
            <p className="mb-1.5 text-sm font-medium text-muted">Gewichtseinheit</p>
            <Segmented value={unit} onChange={onUnit} options={[{ value: "kg", label: "Kilogramm" }, { value: "lb", label: "Pfund" }]} />
          </div>
          <Field label="Gewichtsschritt (+/- Buttons)" htmlFor="step" hint="z. B. 2,5 oder 1,25">
            <Input id="step" inputMode="decimal" value={step} onChange={(e) => setStep(e.target.value)} onBlur={onStepBlur} className="max-w-[10rem]" />
          </Field>
          <div>
            <p className="mb-1.5 text-sm font-medium text-muted">Rest Timer Standard</p>
            <div className="grid grid-cols-4 gap-2">
              {REST_PRESETS.map((p) => (
                <button
                  key={p}
                  type="button"
                  onClick={() => onRest(p)}
                  className={`press h-11 rounded-[var(--radius-control)] text-sm font-semibold ${rest === p ? "bg-accent-fill text-accent-fg" : "bg-subtle text-muted"}`}
                >
                  {p}s
                </button>
              ))}
            </div>
            <div className="mt-2 flex items-center gap-2">
              <Select value={String(rest)} onChange={(e) => onRest(Number(e.target.value))} aria-label="Eigene Zeit" className="max-w-[12rem]">
                {[30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240, 300].map((s) => (
                  <option key={s} value={s}>
                    {s} Sekunden
                  </option>
                ))}
              </Select>
            </div>
          </div>
          <div className="border-t border-border">
            <Switch checked={showRir} onChange={onRir} label="RIR anzeigen" description="Reps in Reserve pro Satz eintragen (Orientierung: 1–3)" />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="space-y-3 pt-5">
          <SectionLabel>Darstellung</SectionLabel>
          <Segmented value={theme} onChange={onTheme} options={[{ value: "dark", label: "Dunkel" }, { value: "light", label: "Hell" }, { value: "system", label: "System" }]} />
          <p className="text-xs text-faint">Dunkel ist Standard.</p>
        </CardContent>
      </Card>

      <form action="/auth/signout" method="post">
        <Button type="submit" variant="danger" fullWidth size="lg">
          <LogOut className="h-4 w-4" /> Abmelden
        </Button>
      </form>
    </div>
  );
}
