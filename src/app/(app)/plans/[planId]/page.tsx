import { notFound } from "next/navigation";
import Link from "next/link";
import { ChevronLeft } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { getPlan } from "@/lib/services/plans";
import { getProfile } from "@/lib/services/profile";
import { PlanEditor } from "@/components/plans/plan-editor";

export const metadata = { title: "Training bearbeiten" };

export default async function PlanPage({ params }: { params: Promise<{ planId: string }> }) {
  const { planId } = await params;
  const { supabase, user, profile } = await requireUser();
  const plan = await getPlan(supabase, planId);
  if (!plan) notFound();
  const foreign = plan.user_id !== user.id;
  if (foreign && profile.role !== "admin") notFound();
  const owner = foreign ? await getProfile(supabase, plan.user_id).catch(() => null) : null;
  return (
    <div>
      <Link
        href={foreign ? `/admin/users/${plan.user_id}` : "/plans"}
        className="press -ml-1.5 mb-2 inline-flex h-9 items-center gap-0.5 pr-2 text-base font-medium text-accent"
      >
        <ChevronLeft className="h-5 w-5" strokeWidth={2.4} /> {foreign ? (owner?.nickname ?? "Zurück") : "Pläne"}
      </Link>
      {foreign ? <p className="mb-2 text-[13px] font-semibold uppercase tracking-[0.06em] text-muted">Plan von {owner?.nickname ?? "Mitglied"} · Admin</p> : null}
      <PlanEditor plan={plan} canStart={!foreign} />
    </div>
  );
}
