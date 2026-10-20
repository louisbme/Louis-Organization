import type { QuoteRow } from "@/lib/supabase/types";

/** Deterministisch: pro Kalendertag ein anderes Zitat. */
export function pickDailyQuote(quotes: QuoteRow[], date = new Date()): QuoteRow | null {
  if (quotes.length === 0) return null;
  const start = new Date(date.getFullYear(), 0, 0);
  const dayOfYear = Math.floor((date.getTime() - start.getTime()) / 86_400_000);
  const seed = date.getFullYear() * 400 + dayOfYear;
  return quotes[seed % quotes.length];
}
