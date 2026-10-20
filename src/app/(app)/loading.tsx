import { Skeleton } from "@/components/ui/states";

export default function AppLoading() {
  return (
    <div className="space-y-5 animate-fade-in" aria-busy="true" aria-live="polite">
      <div className="space-y-2">
        <Skeleton className="h-4 w-24" />
        <Skeleton className="h-8 w-48" />
      </div>
      <Skeleton className="h-32 w-full rounded-[var(--radius-card)]" />
      <div className="grid grid-cols-3 gap-3">
        <Skeleton className="h-20 rounded-[var(--radius-card)]" />
        <Skeleton className="h-20 rounded-[var(--radius-card)]" />
        <Skeleton className="h-20 rounded-[var(--radius-card)]" />
      </div>
      <Skeleton className="h-40 w-full rounded-[var(--radius-card)]" />
    </div>
  );
}
