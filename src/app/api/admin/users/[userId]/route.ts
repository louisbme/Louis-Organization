import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { emailSchema, passwordSchema } from "@/lib/validation/auth";

const bodySchema = z
  .object({
    email: emailSchema.optional(),
    password: passwordSchema.optional(),
  })
  .refine((b) => b.email !== undefined || b.password !== undefined, { message: "E-Mail oder Passwort angeben" });

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Admin setzt E-Mail und/oder Passwort eines Nutzers direkt (ohne Bestätigungs-Mail).
 * Zugriff nur für angemeldete Admins; die Änderung läuft über den Service-Zugang.
 */
export async function POST(req: Request, ctx: { params: Promise<{ userId: string }> }) {
  const { userId } = await ctx.params;
  if (!UUID_RE.test(userId)) return Response.json({ error: "Ungültige Nutzer-ID" }, { status: 400 });

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: "Nicht angemeldet" }, { status: 401 });

  const { data: me } = await supabase.from("profiles").select("role").eq("id", user.id).maybeSingle();
  if (me?.role !== "admin") return Response.json({ error: "Keine Berechtigung" }, { status: 403 });

  let body: z.infer<typeof bodySchema>;
  try {
    body = bodySchema.parse(await req.json());
  } catch (e) {
    const msg = e instanceof z.ZodError ? e.issues[0]?.message : "Ungültige Eingabe";
    return Response.json({ error: msg ?? "Ungültige Eingabe" }, { status: 400 });
  }

  let admin: ReturnType<typeof createAdminClient>;
  try {
    admin = createAdminClient();
  } catch (e) {
    return Response.json({ error: e instanceof Error ? e.message : "Service-Zugang fehlt" }, { status: 503 });
  }

  const { error } = await admin.auth.admin.updateUserById(userId, {
    ...(body.email ? { email: body.email, email_confirm: true } : {}),
    ...(body.password ? { password: body.password } : {}),
  });
  if (error) return Response.json({ error: error.message }, { status: 400 });

  return Response.json({ ok: true, changed: { email: !!body.email, password: !!body.password } });
}
