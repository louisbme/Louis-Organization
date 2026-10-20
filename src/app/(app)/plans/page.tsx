import { requireUser } from "@/lib/auth/require-user";
import { listPlans } from "@/lib/services/plans";
import { PageHeader } from "@/components/ui/page-header";
import { PlansList } from "@/components/plans/plans-list";

export const metadata = { title: "Trainingspläne" };

export default async function PlansPage() {
  const { supabase, user } = await requireUser();
  const plans = await listPlans(supabase, user.id);
  return (
    <div>
      <PageHeader title="Trainingspläne" description="Rotation A → B → C. Du kannst jederzeit ein anderes Training wählen." />
      <PlansList plans={plans} />
    </div>
  );
}
