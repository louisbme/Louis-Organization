import { z } from "zod";

export const NICKNAME_REGEX = /^[A-Za-z0-9_.-]+$/;

export const nicknameSchema = z
  .string()
  .trim()
  .min(3, "Mindestens 3 Zeichen")
  .max(20, "Maximal 20 Zeichen")
  .regex(NICKNAME_REGEX, "Nur Buchstaben, Zahlen, Punkt, Unterstrich und Bindestrich")
  .refine((v) => !v.includes("@"), "Die E-Mail-Adresse darf nicht als Nickname verwendet werden");

export const emailSchema = z.string().trim().email("Bitte eine gültige E-Mail-Adresse eingeben");

export const passwordSchema = z.string().min(8, "Mindestens 8 Zeichen").max(72, "Maximal 72 Zeichen");

export const loginSchema = z.object({
  email: emailSchema,
  password: z.string().min(1, "Bitte Passwort eingeben"),
});

export const registerSchema = z
  .object({
    email: emailSchema,
    password: passwordSchema,
    confirmPassword: z.string(),
    nickname: nicknameSchema,
  })
  .refine((d) => d.password === d.confirmPassword, {
    path: ["confirmPassword"],
    message: "Die Passwörter stimmen nicht überein",
  });

export const resetPasswordSchema = z
  .object({
    password: passwordSchema,
    confirmPassword: z.string(),
  })
  .refine((d) => d.password === d.confirmPassword, {
    path: ["confirmPassword"],
    message: "Die Passwörter stimmen nicht überein",
  });

/** Zod-Fehler in ein flaches Objekt { feld: meldung } */
export function fieldErrors(result: { success: boolean; error?: { issues: Array<{ path: PropertyKey[]; message: string }> } }): Record<string, string> {
  if (result.success || !result.error) return {};
  const out: Record<string, string> = {};
  for (const issue of result.error.issues) {
    const key = String(issue.path[0] ?? "form");
    if (!out[key]) out[key] = issue.message;
  }
  return out;
}
