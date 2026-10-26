"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { toast } from "sonner";
import { createClient } from "@/lib/supabase/client";
import { loginSchema, fieldErrors } from "@/lib/validation/auth";
import { friendlyError } from "@/lib/utils/errors";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Field } from "@/components/ui/field";

export function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const next = params.get("next");
  const [email, setEmail] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [errors, setErrors] = React.useState<Record<string, string>>({});
  const [loading, setLoading] = React.useState(false);

  React.useEffect(() => {
    if (params.get("error") === "auth") {
      toast.error("Der Link konnte nicht verarbeitet werden. Falls du deine E-Mail gerade bestätigt hast, melde dich einfach an.");
    }
    if (params.get("reset") === "ok") {
      toast.success("Passwort wurde geändert. Bitte anmelden.");
    }
    if (params.get("expired") === "1") {
      toast.message("Deine Sitzung ist abgelaufen. Bitte erneut anmelden.");
    }
  }, [params]);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const parsed = loginSchema.safeParse({ email, password });
    const errs = fieldErrors(parsed);
    setErrors(errs);
    if (!parsed.success) return;

    setLoading(true);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword(parsed.data);
    setLoading(false);
    if (error) {
      toast.error(friendlyError(error));
      return;
    }
    router.replace(next && next.startsWith("/") ? next : "/dashboard");
    router.refresh();
  };

  return (
    <form onSubmit={onSubmit} className="space-y-5" noValidate>
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Anmelden</h1>
        <p className="mt-1 text-sm text-muted">Mit E-Mail und Passwort.</p>
      </div>
      <Field label="E-Mail" htmlFor="email" error={errors.email}>
        <Input
          id="email"
          type="email"
          autoComplete="email"
          inputMode="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          invalid={!!errors.email}
          required
        />
      </Field>
      <Field label="Passwort" htmlFor="password" error={errors.password}>
        <Input
          id="password"
          type="password"
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          invalid={!!errors.password}
          required
        />
      </Field>
      <Button type="submit" size="lg" fullWidth loading={loading}>
        Anmelden
      </Button>
      <div className="flex items-center justify-between text-sm">
        <Link href="/forgot-password" className="text-muted hover:text-fg">
          Passwort vergessen?
        </Link>
        <Link href="/register" className="font-medium text-accent hover:text-accent-strong">
          Konto erstellen
        </Link>
      </div>
    </form>
  );
}
