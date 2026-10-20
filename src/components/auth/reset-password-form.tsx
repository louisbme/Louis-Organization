"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { createClient } from "@/lib/supabase/client";
import { resetPasswordSchema, fieldErrors } from "@/lib/validation/auth";
import { friendlyError } from "@/lib/utils/errors";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Field } from "@/components/ui/field";

export function ResetPasswordForm() {
  const router = useRouter();
  const [form, setForm] = React.useState({ password: "", confirmPassword: "" });
  const [errors, setErrors] = React.useState<Record<string, string>>({});
  const [loading, setLoading] = React.useState(false);
  const [hasSession, setHasSession] = React.useState<boolean | null>(null);

  React.useEffect(() => {
    const supabase = createClient();
    supabase.auth.getSession().then(({ data }) => setHasSession(!!data.session));
  }, []);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const parsed = resetPasswordSchema.safeParse(form);
    const errs = fieldErrors(parsed);
    setErrors(errs);
    if (!parsed.success) return;

    setLoading(true);
    const supabase = createClient();
    const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
    setLoading(false);
    if (error) {
      toast.error(friendlyError(error));
      return;
    }
    await supabase.auth.signOut();
    router.replace("/login?reset=ok");
    router.refresh();
  };

  if (hasSession === false) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-semibold tracking-tight">Link ungültig</h1>
        <p className="text-sm text-muted">
          Der Link zum Zurücksetzen ist abgelaufen oder wurde bereits verwendet. Bitte fordere einen neuen an.
        </p>
        <Button variant="secondary" onClick={() => router.push("/forgot-password")}>
          Neuen Link anfordern
        </Button>
      </div>
    );
  }

  return (
    <form onSubmit={onSubmit} className="space-y-5" noValidate>
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Neues Passwort</h1>
        <p className="mt-1 text-sm text-muted">Mindestens 8 Zeichen.</p>
      </div>
      <Field label="Neues Passwort" htmlFor="password" error={errors.password}>
        <Input
          id="password"
          type="password"
          autoComplete="new-password"
          value={form.password}
          onChange={(e) => setForm((f) => ({ ...f, password: e.target.value }))}
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
          onChange={(e) => setForm((f) => ({ ...f, confirmPassword: e.target.value }))}
          invalid={!!errors.confirmPassword}
          required
        />
      </Field>
      <Button type="submit" size="lg" fullWidth loading={loading || hasSession === null}>
        Passwort speichern
      </Button>
    </form>
  );
}
