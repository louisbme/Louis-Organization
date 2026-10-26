import { notFound } from "next/navigation";
import Link from "next/link";
import { ChevronLeft } from "lucide-react";
import { requireUser } from "@/lib/auth/require-user";
import { getPlan } from "@/lib/services/plans";
import { PlanEditor } from "@/components/plans/plan-editor";

export const metadata = { title: "Training bearbeiten" };

export default async function PlanPage({ params }: { params: Promise<{ planId: string }> }) {
  const { planId } = await params;
  const { supabase, user } = await requireUser();
  const plan = await getPlan(supabase, planId);
  if (!plan || plan.user_id !== user.id) notFound();
  return (
    <div>
      <Link href="/plans" className="press -ml-1.5 mb-2 inline-flex h-9 items-center gap-0.5 pr-2 text-base font-medium text-accent">
        <ChevronLeft className="h-5 w-5" strokeWidth={2.4} /> Pläne
      </Link>
      <PlanEditor plan={plan} />
    </div>
  );
}
