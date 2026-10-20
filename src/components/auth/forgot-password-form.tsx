"use client";

import * as React from "react";
import Link from "next/link";
import { toast } from "sonner";
import { createClient } from "@/lib/supabase/client";
import { emailSchema } from "@/lib/validation/auth";
import { friendlyError } from "@/lib/utils/errors";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Field } from "@/components/ui/field";

export function ForgotPasswordForm() {
  const [email, setEmail] = React.useState("");
  const [error, setError] = React.useState<string | null>(null);
  const [loading, setLoading] = React.useState(false);
  const [sent, setSent] = React.useState(false);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const parsed = emailSchema.safeParse(email);
    if (!parsed.success) {
      setError(parsed.error.issues[0]?.message ?? "Ungültige E-Mail");
      return;
    }
    setError(null);
    setLoading(true);
    const supabase = createClient();
    const { error: err } = await supabase.auth.resetPasswordForEmail(parsed.data, {
      redirectTo: `${window.location.origin}/auth/callback?next=/reset-password`,
    });
    setLoading(false);
    if (err) {
      toast.error(friendlyError(err));
      return;
    }
    setSent(true);
  };

  if (sent) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-semibold tracking-tight">E-Mail gesendet</h1>
        <p className="text-sm text-muted">
          Falls ein Konto für <span className="text-fg">{email}</span> existiert, haben wir einen Link zum
          Zurücksetzen des Passworts gesendet.
        </p>
        <Link href="/login" className="inline-block text-sm font-medium text-accent hover:text-accent-strong">
          Zurück zur Anmeldung
        </Link>
      </div>
    );
  }

  return (
    <form onSubmit={onSubmit} className="space-y-5" noValidate>
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Passwort vergessen</h1>
        <p className="mt-1 text-sm text-muted">Wir senden dir einen Link zum Zurücksetzen.</p>
      </div>
      <Field label="E-Mail" htmlFor="email" error={error}>
        <Input
          id="email"
          type="email"
          autoComplete="email"
          inputMode="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          invalid={!!error}
          required
        />
      </Field>
      <Button type="submit" size="lg" fullWidth loading={loading}>
        Link senden
      </Button>
      <p className="text-center text-sm">
        <Link href="/login" className="text-muted hover:text-fg">
          Zurück zur Anmeldung
        </Link>
      </p>
    </form>
  );
}
