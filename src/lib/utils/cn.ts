type ClassValue = string | number | null | undefined | false | ClassValue[] | Record<string, boolean | null | undefined>;

/** Minimaler Klassen-Kombinierer (ohne externe Abhängigkeit). */
export function cn(...inputs: ClassValue[]): string {
  const out: string[] = [];
  const walk = (v: ClassValue) => {
    if (!v) return;
    if (typeof v === "string" || typeof v === "number") {
      out.push(String(v));
    } else if (Array.isArray(v)) {
      v.forEach(walk);
    } else if (typeof v === "object") {
      for (const [k, val] of Object.entries(v)) if (val) out.push(k);
    }
  };
  inputs.forEach(walk);
  return out.join(" ");
}
