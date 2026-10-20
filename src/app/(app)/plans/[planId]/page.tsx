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
      <Link href="/plans" className="-ml-1 mb-2 inline-flex items-center gap-0.5 text-sm text-muted hover:text-fg">
        <ChevronLeft className="h-4 w-4" /> Pläne
      </Link>
      <PlanEditor plan={plan} />
    </div>
  );
}
