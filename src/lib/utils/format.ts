import { format, formatDistanceToNowStrict, isToday, isYesterday } from "date-fns";
import { de } from "date-fns/locale";
import type { WeightUnit } from "@/lib/supabase/types";

const numberFormat = new Intl.NumberFormat("de-DE", { maximumFractionDigits: 0 });
const decimalFormat = new Intl.NumberFormat("de-DE", { maximumFractionDigits: 2 });

export function formatNumber(value: number): string {
  return numberFormat.format(value);
}

export function formatDecimal(value: number): string {
  return decimalFormat.format(value);
}

export function formatWeight(value: number, unit: WeightUnit = "kg"): string {
  return `${decimalFormat.format(value)} ${unit}`;
}

/** Volumen kompakt: 12.450 kg / 1,2 t */
export function formatVolume(value: number, unit: WeightUnit = "kg"): string {
  if (unit === "kg" && value >= 10000) {
    return `${new Intl.NumberFormat("de-DE", { maximumFractionDigits: 1 }).format(value / 1000)} t`;
  }
  return `${numberFormat.format(Math.round(value))} ${unit}`;
}

/** Gewicht mit Vorzeichen: "+10 kg" / "−10 kg" / "±0 kg" */
export function formatSignedWeight(value: number, unit: WeightUnit = "kg"): string {
  if (value === 0) return `±0 ${unit}`;
  return `${value > 0 ? "+" : "−"}${decimalFormat.format(Math.abs(value))} ${unit}`;
}

/** Distanz: 5,00 km / 800 m */
export function formatDistance(meters: number): string {
  if (meters >= 1000) return `${new Intl.NumberFormat("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(meters / 1000)} km`;
  return `${numberFormat.format(Math.round(meters))} m`;
}

/** Pace: 5:12 /km */
export function formatPace(secPerKm: number): string {
  const s = Math.max(0, Math.round(secPerKm));
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return `${m}:${String(sec).padStart(2, "0")} /km`;
}

/**
 * Zeitangabe lesen: "12:30" → 750 s, "1:02:05" → 3725 s, "12" → 720 s (Minuten), "12,5" → 750 s.
 * null bei ungültiger Eingabe.
 */
export function parseClock(text: string): number | null {
  const t = text.trim().replace(",", ".");
  if (!t) return null;
  if (t.includes(":")) {
    const parts = t.split(":").map((p) => Number(p));
    if (parts.some((p) => Number.isNaN(p) || p < 0)) return null;
    if (parts.length === 2) return Math.round(parts[0] * 60 + parts[1]);
    if (parts.length === 3) return Math.round(parts[0] * 3600 + parts[1] * 60 + parts[2]);
    return null;
  }
  const minutes = Number(t);
  if (Number.isNaN(minutes) || minutes < 0) return null;
  return Math.round(minutes * 60);
}

/** 1 h 24 min / 45 min / 0 min */
export function formatDuration(seconds: number | null | undefined): string {
  if (!seconds || seconds <= 0) return "0 min";
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  if (h > 0) return `${h} h ${m} min`;
  return `${m} min`;
}

/** mm:ss bzw. h:mm:ss */
export function formatClock(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const mm = String(m).padStart(2, "0");
  const ss = String(sec).padStart(2, "0");
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

export function formatDate(value: string | Date, pattern = "d. MMM yyyy"): string {
  return format(typeof value === "string" ? new Date(value) : value, pattern, { locale: de });
}

export function formatDateTime(value: string | Date): string {
  return format(typeof value === "string" ? new Date(value) : value, "d. MMM yyyy, HH:mm", { locale: de });
}

export function formatRelativeDay(value: string | Date): string {
  const d = typeof value === "string" ? new Date(value) : value;
  if (isToday(d)) return "Heute";
  if (isYesterday(d)) return "Gestern";
  return format(d, "EEEE, d. MMM", { locale: de });
}

export function formatAgo(value: string | Date): string {
  const d = typeof value === "string" ? new Date(value) : value;
  return `vor ${formatDistanceToNowStrict(d, { locale: de })}`;
}

/** YYYY-MM-DD in lokaler Zeit */
export function toDateKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export function parseDateKey(key: string): Date {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(y, m - 1, d);
}
