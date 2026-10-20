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
