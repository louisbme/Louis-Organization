import { Quote } from "lucide-react";
import type { QuoteRow } from "@/lib/supabase/types";

export function QuoteCard({ quote }: { quote: QuoteRow | null }) {
  if (!quote) return null;
  return (
    <div className="flex items-start gap-3 rounded-[var(--radius-card)] border border-border bg-card px-5 py-4">
      <Quote className="mt-0.5 h-4 w-4 shrink-0 text-accent" strokeWidth={2} />
      <div>
        <p className="text-sm font-medium leading-relaxed">{quote.text}</p>
        {quote.author ? <p className="mt-1 text-xs text-faint">{quote.author}</p> : null}
      </div>
    </div>
  );
}
