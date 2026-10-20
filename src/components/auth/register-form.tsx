"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { MailCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { registerSchema, fieldErrors } from "@/lib/validation/auth";
import { friendlyError } from "@/lib/utils/errors";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Field } from "@/components/ui/field";

export function RegisterForm() {
  const router = useRouter();
  const [form, setForm] = React.useState({ email: "", password: "", confirmPassword: "", nickname: "" });
  const [errors, setErrors] = React.useState<Record<string, string>>({});
  const [loading, setLoading] = React.useState(false);
  const [done, setDone] = React.useState(false);

  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const parsed = registerSchema.safeParse(form);
    const errs = fieldErrors(parsed);
    setErrors(errs);
    if (!parsed.success) return;

    setLoading(true);
    const supabase = createClient();

    const { data: available, error: nickError } = await supabase.rpc("is_nickname_available", {
      p_nickname: parsed.data.nickname,
    });
    if (nickError) {
      setLoading(false);
      toast.error(friendlyError(nickError));
      return;
    }
    if (!available) {
      setLoading(false);
      setErrors({ nickname: "Dieser Nickname ist bereits vergeben" });
      return;
    }

    const { data, error } = await supabase.auth.signUp({
      email: parsed.data.email,
      password: parsed.data.password,
      options: {
        data: { nickname: parsed.data.nickname },
        emailRedirectTo: `${window.location.origin}/auth/callback?next=/dashboard`,
      },
    });
    setLoading(false);

    if (error) {
      toast.error(friendlyError(error));
      return;
    }

    if (data.session) {
      router.replace("/dashboard");
      router.refresh();
      return;
    }
    setDone(true);
  };

  if (done) {
    return (
      <div className="space-y-4 text-center">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-accent-soft text-accent">
          <MailCheck className="h-7 w-7" />
        </div>
        <h1 className="text-2xl font-semibold tracking-tight">E-Mail bestätigen</h1>
        <p className="text-sm text-muted">
          Wir haben eine Bestätigungs-E-Mail an <span className="text-fg">{form.email}</span> gesendet. Nach dem
          Klick auf den Link kannst du dich anmelden.
        </p>
        <Button variant="secondary" fullWidth onClick={() => router.push("/login")}>
          Zur Anmeldung
        </Button>
      </div>
    );
  }

  return (
    <form onSubmit={onSubmit} className="space-y-5" noValidate>
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Konto erstellen</h1>
        <p className="mt-1 text-sm text-muted">Für die private Nutzung.</p>
      </div>
      <Field label="E-Mail" htmlFor="email" error={errors.email}>
        <Input
          id="email"
          type="email"
          autoComplete="email"
          inputMode="email"
          value={form.email}
          onChange={set("email")}
          invalid={!!errors.email}
          required
        />
      </Field>
      <Field label="Passwort" htmlFor="password" error={errors.password} hint="Mindestens 8 Zeichen">
        <Input
          id="password"
          type="password"
          autoComplete="new-password"
          value={form.password}
          onChange={set("password")}
          invalid={!!errors.password}
          required
        />
      </Field>
      <Field label="Passwort bestätigen" htmlFor="confirmPassword" error={errors.confirmPassword}>
        <Input
          id="confirmPassword"
          type="password"
          autoComplete="new-password"
          value={form.confirmPassword}
          onChange={set("confirmPassword")}
          invalid={!!errors.confirmPassword}
          required
        />
      </Field>
      <Field
        label="Nickname"
        htmlFor="nickname"
        error={errors.nickname}
        hint="Sichtbarer Name, 3–20 Zeichen. Kann später geändert werden."
      >
        <Input
          id="nickname"
          type="text"
          autoComplete="nickname"
          autoCapitalize="off"
          value={form.nickname}
          onChange={set("nickname")}
          invalid={!!errors.nickname}
          maxLength={20}
          required
        />
      </Field>
      <Button type="submit" size="lg" fullWidth loading={loading}>
        Konto erstellen
      </Button>
      <p className="text-center text-sm text-muted">
        Bereits registriert?{" "}
        <Link href="/login" className="font-medium text-accent hover:text-accent-strong">
          Anmelden
        </Link>
      </p>
    </form>
  );
}
