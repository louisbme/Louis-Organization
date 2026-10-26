import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

/** Abmelden per Formular (Button in der App). */
export async function POST(request: Request) {
  const supabase = await createClient();
  await supabase.auth.signOut();
  const { origin } = new URL(request.url);
  return NextResponse.redirect(`${origin}/login`, { status: 303 });
}

/**
 * Abmelden per Weiterleitung, wenn eine Sitzung serverseitig ungültig geworden ist.
 * Löscht nur die lokalen Cookies (scope local), damit andere Geräte unberührt bleiben.
 */
export async function GET(request: Request) {
  const supabase = await createClient();
  await supabase.auth.signOut({ scope: "local" }).catch(() => undefined);
  const { origin, searchParams } = new URL(request.url);
  const reason = searchParams.get("reason");
  return NextResponse.redirect(`${origin}/login${reason === "expired" ? "?expired=1" : ""}`, { status: 303 });
}
