"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { ChevronLeft, HeartPulse, PenLine, Plus, Star } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import type { EquipmentType } from "@/lib/supabase/types";
import type { ExerciseListItem } from "@/lib/services/exercises";
import {
  CATEGORY_LABELS,
  EQUIPMENT_LABELS,
  EQUIPMENT_ORDER,
  EXERCISE_GROUPS,
  exerciseGroup,
  exerciseInGroup,
  type ExerciseGroupDef,
  type ExerciseGroupKey,
} from "@/lib/utils/labels";
import { EquipmentIcon } from "@/components/exercise/equipment-icon";
import { MuscleFigure } from "@/components/muscle-map/muscle-map";
import { SearchField } from "@/components/ui/search-field";
import { List, ListRow } from "@/components/ui/list";
import { EmptyState } from "@/components/ui/states";
import { Button } from "@/components/ui/button";

interface ExerciseBrowserProps {
  items: ExerciseListItem[];
  mode?: "browse" | "pick";
  onPick?: (item: ExerciseListItem) => void;
  showCreateLink?: boolean;
}

type EquipmentFilter = EquipmentType | "all";

/**
 * Übungsübersicht: Suche oben, darunter Muskelgruppen als Karten mit Figur.
 * Eine Gruppe öffnet die Liste ihrer Übungen; die Suche durchsucht alle Übungen.
 * Im Auswahlmodus (Sheet) bleibt die Gruppe lokal, sonst steht sie in der URL (?g=).
 */
export function ExerciseBrowser({ items, mode = "browse", onPick, showCreateLink = true }: ExerciseBrowserProps) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const [localGroup, setLocalGroup] = React.useState<ExerciseGroupKey | null>(null);
  const [query, setQuery] = React.useState("");
  const [equipment, setEquipment] = React.useState<EquipmentFilter>("all");

  const groupKey = mode === "browse" ? params.get("g") : localGroup;
  const group = exerciseGroup(groupKey);
  const setGroup = React.useCallback(
    (key: ExerciseGroupKey | null) => {
      setEquipment("all");
      if (mode === "browse") router.push(key ? `${pathname}?g=${key}` : pathname, { scroll: false });
      else setLocalGroup(key);
    },
    [mode, pathname, router]
  );

  const counts = React.useMemo(() => {
    const map = new Map<ExerciseGroupKey, number>();
    for (const g of EXERCISE_GROUPS) map.set(g.key, items.filter((e) => exerciseInGroup(e, g)).length);
    return map;
  }, [items]);

  const searching = query.trim().length > 0;
  const q = query.trim().toLowerCase();

  const list = React.useMemo(() => {
    return items
      .filter((e) => (searching || !group ? true : exerciseInGroup(e, group)))
      .filter((e) => (equipment === "all" ? true : e.equipment === equipment))
      .filter((e) =>
        q
          ? e.name.toLowerCase().includes(q) ||
            CATEGORY_LABELS[e.category].toLowerCase().includes(q) ||
            EQUIPMENT_LABELS[e.equipment].toLowerCase().includes(q)
          : true
      )
      .sort((a, b) => Number(b.is_favorite) - Number(a.is_favorite) || a.name.localeCompare(b.name, "de"));
  }, [items, searching, group, equipment, q]);

  const equipmentOptions = React.useMemo(() => {
    const base = searching || !group ? items : items.filter((e) => exerciseInGroup(e, group));
    const present = new Set(base.map((e) => e.equipment));
    return EQUIPMENT_ORDER.filter((e) => present.has(e) && e !== "other" && e !== "bench");
  }, [items, searching, group]);

  const showList = searching || !!group;

  return (
    <div className="space-y-4">
      <SearchField value={query} onChange={setQuery} placeholder="Übungen suchen" />

      {!showList ? (
        <GroupGrid counts={counts} onSelect={setGroup} />
      ) : (
        <>
          <div className="flex items-center justify-between gap-3">
            {group && !searching ? (
              <button type="button" onClick={() => setGroup(null)} className="press -ml-1.5 inline-flex h-9 items-center gap-0.5 pr-2 text-base font-medium text-accent">
                <ChevronLeft className="h-5 w-5" strokeWidth={2.4} /> Gruppen
              </button>
            ) : (
              <p className="text-sm text-muted">
                {list.length} {list.length === 1 ? "Treffer" : "Treffer"}
              </p>
            )}
            {group && !searching ? (
              <h2 className="font-sans text-base font-semibold">
                {group.label} <span className="font-normal text-muted">· {list.length}</span>
              </h2>
            ) : null}
          </div>

          {equipmentOptions.length > 1 ? (
            <div className="no-scrollbar -mx-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
              <div className="flex w-max gap-2 pb-1">
                <FilterChip active={equipment === "all"} onClick={() => setEquipment("all")}>
                  Alle
                </FilterChip>
                {equipmentOptions.map((eq) => (
                  <FilterChip key={eq} active={equipment === eq} onClick={() => setEquipment(equipment === eq ? "all" : eq)}>
                    <EquipmentIcon equipment={eq} className="h-3.5 w-3.5" /> {EQUIPMENT_LABELS[eq]}
                  </FilterChip>
                ))}
              </div>
            </div>
          ) : null}

          {list.length === 0 ? (
            <EmptyState
              title="Keine Übungen gefunden"
              description={searching ? "Andere Suche ausprobieren." : "In dieser Gruppe gibt es noch keine Übungen."}
              action={
                showCreateLink && mode === "browse" ? (
                  <Link href="/exercises/new">
                    <Button variant="secondary">
                      <Plus className="h-4 w-4" /> Eigene Übung erstellen
                    </Button>
                  </Link>
                ) : undefined
              }
            />
          ) : (
            <List>
              {list.map((e) => (
                <Row key={e.id} item={e} mode={mode} onPick={onPick} />
              ))}
            </List>
          )}
        </>
      )}
    </div>
  );
}

function GroupGrid({ counts, onSelect }: { counts: Map<ExerciseGroupKey, number>; onSelect: (key: ExerciseGroupKey) => void }) {
  const visible = EXERCISE_GROUPS.filter((g) => (counts.get(g.key) ?? 0) > 0 || g.key === "custom");
  return (
    <div className="stagger grid grid-cols-2 gap-3">
      {visible.map((g) => (
        <GroupCard key={g.key} group={g} count={counts.get(g.key) ?? 0} onClick={() => onSelect(g.key)} />
      ))}
    </div>
  );
}

function GroupCard({ group, count, onClick }: { group: ExerciseGroupDef; count: number; onClick: () => void }) {
  const wide = !!group.wide;
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={`${group.label}, ${count} Übungen`}
      className={cn(
        "card-interactive press relative flex items-center justify-between overflow-hidden rounded-[var(--radius-card)] bg-card text-left",
        wide ? "col-span-2 h-[96px] pl-5 pr-6" : "h-[124px] gap-1 pl-4 pr-2.5"
      )}
    >
      <span className="min-w-0 flex-1">
        <span className={cn("block font-semibold leading-tight text-fg", wide ? "text-lg" : "text-[17px]")}>{group.label}</span>
        <span className="tnum block whitespace-nowrap text-xs text-muted">{count === 1 ? "1 Übung" : `${count} Übungen`}</span>
      </span>
      <span className={cn("flex shrink-0 items-center justify-center text-fg/55", wide ? "h-14 w-14" : "h-[100px] w-[56px]")} aria-hidden>
        {group.highlight.length > 0 ? <MuscleFigure view={group.view} highlight={group.highlight} /> : <GroupIcon groupKey={group.key} />}
      </span>
    </button>
  );
}

function GroupIcon({ groupKey }: { groupKey: ExerciseGroupKey }) {
  const cls = "h-10 w-10";
  if (groupKey === "cardio") return <HeartPulse className={cls} strokeWidth={1.6} />;
  if (groupKey === "favorites") return <Star className={cn(cls, "text-warning")} strokeWidth={1.6} />;
  if (groupKey === "custom") return <PenLine className={cls} strokeWidth={1.6} />;
  return null;
}

function FilterChip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={cn(
        "press inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full px-3.5 text-sm font-medium transition-colors touch-manipulation",
        active ? "bg-fg text-bg" : "bg-card text-muted hover:text-fg"
      )}
    >
      {children}
    </button>
  );
}

function Row({ item, mode, onPick }: { item: ExerciseListItem; mode: "browse" | "pick"; onPick?: (i: ExerciseListItem) => void }) {
  const subtitle = `${CATEGORY_LABELS[item.category]} · ${EQUIPMENT_LABELS[item.equipment]}${item.is_custom ? " · Eigene" : ""}`;
  const trailing = (
    <span className="flex items-center gap-2">
      {item.is_favorite ? <Star className="h-4 w-4 fill-current text-warning" aria-label="Favorit" /> : null}
      {mode === "pick" ? <Plus className="h-5 w-5 text-accent" strokeWidth={2.4} /> : null}
    </span>
  );
  const leading = <EquipmentIcon equipment={item.equipment} className="h-5 w-5" strokeWidth={1.8} />;
  if (mode === "pick") {
    return <ListRow onClick={() => onPick?.(item)} leading={leading} title={item.name} subtitle={subtitle} trailing={trailing} />;
  }
  return <ListRow href={`/exercises/${item.slug}`} leading={leading} title={item.name} subtitle={subtitle} trailing={trailing} chevron />;
}
