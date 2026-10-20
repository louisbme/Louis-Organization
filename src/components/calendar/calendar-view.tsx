"use client";

import * as React from "react";
import Link from "next/link";
import { toast } from "sonner";
import { addMonths, endOfMonth, startOfMonth, format, getDay, getDaysInMonth, isSameDay, isAfter } from "date-fns";
import { de } from "date-fns/locale";
import { ChevronLeft, ChevronRight, Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import type { CalendarEntryRow, CalendarEntryType } from "@/lib/supabase/types";
import { deleteCalendarEntry, listCalendarEntries, upsertCalendarEntry } from "@/lib/services/calendar";
import { listSessions, type SessionListItem } from "@/lib/services/sessions";
import { CALENDAR_TYPE_LABELS, CALENDAR_TYPE_ORDER, CALENDAR_TYPE_STYLES } from "@/lib/utils/labels";
import { formatDuration, formatVolume, toDateKey } from "@/lib/utils/format";
import { friendlyError } from "@/lib/utils/errors";
import { cn } from "@/lib/utils/cn";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Sheet } from "@/components/ui/sheet";
import { Textarea, Select } from "@/components/ui/input";

const MIN_YEAR = new Date().getFullYear() - 10;
const MAX_YEAR = new Date().getFullYear() + 10;
const WEEKDAYS = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"];

interface Props {
  initialMonth: string; // YYYY-MM
  initialEntries: CalendarEntryRow[];
  initialSessions: SessionListItem[];
}

export function CalendarView({ initialMonth, initialEntries, initialSessions }: Props) {
  const { userId, settings } = useUser();
  const db = React.useMemo(() => createClient(), []);
  const [month, setMonth] = React.useState(() => new Date(`${initialMonth}-01T00:00:00`));
  const [entries, setEntries] = React.useState(initialEntries);
  const [sessions, setSessions] = React.useState(initialSessions);
  const [selected, setSelected] = React.useState<string | null>(null);
  const [type, setType] = React.useState<CalendarEntryType>("training");
  const [note, setNote] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const first = React.useRef(true);

  const monthKey = format(month, "yyyy-MM");

  React.useEffect(() => {
    if (first.current) {
      first.current = false;
      return;
    }
    const from = startOfMonth(month);
    const to = endOfMonth(month);
    let cancelled = false;
    Promise.all([
      listCalendarEntries(db, userId, toDateKey(from), toDateKey(to)),
      listSessions(db, userId, { from: from.toISOString(), to: new Date(to.getTime() + 86_399_000).toISOString(), limit: 200 }),
    ])
      .then(([e, s]) => {
        if (cancelled) return;
        setEntries(e);
        setSessions(s);
      })
      .catch((e) => toast.error(friendlyError(e)));
    return () => {
      cancelled = true;
    };
  }, [monthKey, db, userId, month]);

  const entryByDate = React.useMemo(() => new Map(entries.map((e) => [e.entry_date, e])), [entries]);
  const sessionsByDate = React.useMemo(() => {
    const map = new Map<string, SessionListItem[]>();
    for (const s of sessions) {
      const key = toDateKey(new Date(s.started_at));
      map.set(key, [...(map.get(key) ?? []), s]);
    }
    return map;
  }, [sessions]);

  const days = React.useMemo(() => {
    const count = getDaysInMonth(month);
    const firstDay = startOfMonth(month);
    const offset = (getDay(firstDay) + 6) % 7; // Montag = 0
    const cells: Array<Date | null> = Array.from({ length: offset }, () => null);
    for (let d = 1; d <= count; d++) cells.push(new Date(month.getFullYear(), month.getMonth(), d));
    while (cells.length % 7 !== 0) cells.push(null);
    return cells;
  }, [month]);

  const today = new Date();

  const openDay = (date: Date) => {
    const key = toDateKey(date);
    const entry = entryByDate.get(key);
    setSelected(key);
    setType(entry?.entry_type ?? (sessionsByDate.has(key) ? "training" : "rest"));
    setNote(entry?.note ?? "");
  };

  const save = async () => {
    if (!selected) return;
    setBusy(true);
    try {
      const row = await upsertCalendarEntry(db, userId, selected, type, note.trim() || null);
      setEntries((list) => [...list.filter((e) => e.entry_date !== selected), row]);
      setSelected(null);
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    if (!selected) return;
    const entry = entryByDate.get(selected);
    if (!entry) {
      setSelected(null);
      return;
    }
    setBusy(true);
    try {
      await deleteCalendarEntry(db, entry.id);
      setEntries((list) => list.filter((e) => e.id !== entry.id));
      setSelected(null);
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setBusy(false);
    }
  };

  const canPrev = month.getFullYear() > MIN_YEAR || (month.getFullYear() === MIN_YEAR && month.getMonth() > 0);
  const canNext = month.getFullYear() < MAX_YEAR || (month.getFullYear() === MAX_YEAR && month.getMonth() < 11);
  const selectedDate = selected ? new Date(`${selected}T00:00:00`) : null;
  const selectedSessions = selected ? sessionsByDate.get(selected) ?? [] : [];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-2">
        <Button variant="secondary" size="icon" onClick={() => setMonth((m) => addMonths(m, -1))} disabled={!canPrev} aria-label="Vorheriger Monat">
          <ChevronLeft className="h-5 w-5" />
        </Button>
        <div className="flex items-center gap-2">
          <Select
            value={String(month.getMonth())}
            onChange={(e) => setMonth(new Date(month.getFullYear(), Number(e.target.value), 1))}
            aria-label="Monat"
            className="h-10 w-auto min-w-[8.5rem] text-sm"
          >
            {Array.from({ length: 12 }, (_, i) => (
              <option key={i} value={i}>
                {format(new Date(2000, i, 1), "LLLL", { locale: de })}
              </option>
            ))}
          </Select>
          <Select
            value={String(month.getFullYear())}
            onChange={(e) => setMonth(new Date(Number(e.target.value), month.getMonth(), 1))}
            aria-label="Jahr"
            className="h-10 w-auto text-sm"
          >
            {Array.from({ length: MAX_YEAR - MIN_YEAR + 1 }, (_, i) => MIN_YEAR + i).map((y) => (
              <option key={y} value={y}>
                {y}
              </option>
            ))}
          </Select>
        </div>
        <Button variant="secondary" size="icon" onClick={() => setMonth((m) => addMonths(m, 1))} disabled={!canNext} aria-label="Nächster Monat">
          <ChevronRight className="h-5 w-5" />
        </Button>
      </div>

      <Card className="p-3 sm:p-4">
        <div className="grid grid-cols-7 gap-1 text-center text-[11px] font-medium uppercase tracking-wider text-faint">
          {WEEKDAYS.map((d) => (
            <div key={d} className="py-1">
              {d}
            </div>
          ))}
        </div>
        <div className="mt-1 grid grid-cols-7 gap-1">
          {days.map((date, i) => {
            if (!date) return <div key={`empty-${i}`} />;
            const key = toDateKey(date);
            const entry = entryByDate.get(key);
            const daySessions = sessionsByDate.get(key) ?? [];
            const effectiveType: CalendarEntryType | null = entry?.entry_type ?? (daySessions.length > 0 ? "training" : null);
            const isToday = isSameDay(date, today);
            const future = isAfter(date, today) && !isToday;
            return (
              <button
                key={key}
                type="button"
                onClick={() => openDay(date)}
                className={cn(
                  "flex aspect-square flex-col items-center justify-center gap-1 rounded-lg text-sm transition-colors touch-manipulation",
                  effectiveType === "training" ? "bg-subtle" : "hover:bg-subtle",
                  isToday && "ring-1 ring-border-strong",
                  future && "text-faint"
                )}
                aria-label={format(date, "d. MMMM yyyy", { locale: de })}
              >
                <span className={cn("tnum font-medium", isToday && "font-bold")}>{date.getDate()}</span>
                <span className="flex h-1.5 items-center gap-0.5">
                  {effectiveType ? <span className={cn("h-2 w-2 rounded-full", CALENDAR_TYPE_STYLES[effectiveType].dot)} /> : null}
                  {entry?.note ? <span className="h-1 w-1 rounded-full bg-faint" /> : null}
                </span>
              </button>
            );
          })}
        </div>
      </Card>

      <div className="flex flex-wrap gap-x-4 gap-y-2 px-1 text-xs text-muted">
        {CALENDAR_TYPE_ORDER.map((t) => (
          <span key={t} className="inline-flex items-center gap-1.5">
            <span className={cn("h-2.5 w-2.5 rounded-full", CALENDAR_TYPE_STYLES[t].dot)} /> {CALENDAR_TYPE_LABELS[t]}
          </span>
        ))}
        <span className="inline-flex items-center gap-1.5">
          <span className="h-1.5 w-1.5 rounded-full bg-faint" /> Notiz
        </span>
      </div>

      <Sheet
        open={selected !== null}
        onClose={() => setSelected(null)}
        title={selectedDate ? format(selectedDate, "EEEE, d. MMMM yyyy", { locale: de }) : ""}
        footer={
          <div className="flex gap-2">
            {selected && entryByDate.has(selected) ? (
              <Button variant="danger" onClick={remove} loading={busy} aria-label="Markierung entfernen">
                <Trash2 className="h-4 w-4" />
              </Button>
            ) : null}
            <Button fullWidth onClick={save} loading={busy}>
              Speichern
            </Button>
          </div>
        }
      >
        {selectedSessions.length > 0 ? (
          <div className="mb-4 space-y-2">
            {selectedSessions.map((s) => (
              <Link key={s.id} href={`/history/${s.id}`} className="block rounded-xl border border-border bg-subtle px-4 py-3 hover:bg-hover">
                <p className="text-sm font-medium">{s.name}</p>
                <p className="text-xs text-muted">
                  {formatDuration(s.duration_seconds)} · {s.total_sets} Sätze · {formatVolume(s.total_volume, settings.weight_unit)}
                </p>
              </Link>
            ))}
          </div>
        ) : null}
        <p className="mb-2 text-sm font-medium text-muted">Tag markieren als</p>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
          {CALENDAR_TYPE_ORDER.map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => setType(t)}
              className={cn(
                "flex h-11 items-center gap-2 rounded-xl border px-3 text-sm font-medium touch-manipulation",
                type === t ? "border-border-strong bg-accent-soft text-fg" : "border-border bg-subtle text-muted hover:text-fg"
              )}
              aria-pressed={type === t}
            >
              <span className={cn("h-2.5 w-2.5 rounded-full", CALENDAR_TYPE_STYLES[t].dot)} /> {CALENDAR_TYPE_LABELS[t]}
            </button>
          ))}
        </div>
        <div className="mt-4">
          <label htmlFor="calNote" className="mb-1.5 block text-sm font-medium text-muted">
            Notiz (optional)
          </label>
          <Textarea id="calNote" value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} rows={3} />
        </div>
      </Sheet>
    </div>
  );
}
