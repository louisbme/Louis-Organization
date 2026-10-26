"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/context/user-context";
import type { EquipmentType, ExerciseCategory, ExerciseVariant, GripRow, MuscleId } from "@/lib/supabase/types";
import {
  createCustomExercise,
  updateCustomExercise,
  type CustomExerciseInput,
  type ExerciseDetail,
} from "@/lib/services/exercises";
import { CATEGORY_LABELS, CATEGORY_ORDER, EQUIPMENT_LABELS, EQUIPMENT_ORDER, MUSCLE_IDS, MUSCLE_LABELS } from "@/lib/utils/labels";
import { friendlyError } from "@/lib/utils/errors";
import { deriveTrackingMode, TRACKING_LABELS } from "@/lib/utils/tracking";
import { cn } from "@/lib/utils/cn";
import { Button } from "@/components/ui/button";
import { Input, Select, Textarea } from "@/components/ui/input";
import { Field } from "@/components/ui/field";
import { Card, CardContent, SectionLabel } from "@/components/ui/card";
import { MuscleMap } from "@/components/muscle-map/muscle-map";

interface ExerciseFormProps {
  grips: GripRow[];
  existing?: ExerciseDetail;
}

const DEFAULT_PRIMARY: Record<ExerciseCategory, MuscleId> = {
  chest: "chest",
  back: "lats",
  shoulders: "side_delts",
  biceps: "biceps",
  triceps: "triceps",
  quads: "quads",
  hamstrings: "hamstrings",
  glutes: "glutes",
  calves: "calves",
  abs: "abs",
  forearms: "forearms",
  adductors: "adductors",
  cardio: "quads",
};

/** "Name: Beschreibung | https://…" je Zeile → Varianten */
function parseVariants(text: string): ExerciseVariant[] {
  return text
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .map((line) => {
      const [main, url] = line.split("|").map((p) => p.trim());
      const idx = main.indexOf(":");
      const name = idx > 0 ? main.slice(0, idx).trim() : main;
      const description = idx > 0 ? main.slice(idx + 1).trim() : "";
      return { name, description: description || name, ...(url && /^https:\/\//.test(url) ? { source_url: url } : {}) };
    })
    .filter((v) => v.name.length > 0);
}

const linesToArray = (s: string) =>
  s
    .split("\n")
    .map((l) => l.replace(/^\s*(\d+[.)]|[-•])\s*/, "").trim())
    .filter(Boolean);

export function ExerciseForm({ grips, existing }: ExerciseFormProps) {
  const router = useRouter();
  const { userId } = useUser();
  const [busy, setBusy] = React.useState(false);
  const [errors, setErrors] = React.useState<Record<string, string>>({});

  const [name, setName] = React.useState(existing?.name ?? "");
  const [category, setCategory] = React.useState<ExerciseCategory>(existing?.category ?? "chest");
  const [equipment, setEquipment] = React.useState<EquipmentType>(existing?.equipment ?? "machine");
  const [primary, setPrimary] = React.useState<string[]>(existing?.primary_muscles ?? ["chest"]);
  const [secondary, setSecondary] = React.useState<string[]>(existing?.secondary_muscles ?? []);
  const [gripId, setGripId] = React.useState<string>(existing?.grip_id ?? "");
  const [gripNotes, setGripNotes] = React.useState(existing?.grip_notes ?? "");
  const [description, setDescription] = React.useState(existing?.description ?? "");
  const [setup, setSetup] = React.useState((existing?.setup ?? []).join("\n"));
  const [execution, setExecution] = React.useState((existing?.execution ?? []).join("\n"));
  const [breathing, setBreathing] = React.useState(existing?.breathing ?? "");
  const [mistakes, setMistakes] = React.useState((existing?.common_mistakes ?? []).join("\n"));
  const [tips, setTips] = React.useState((existing?.tips ?? []).join("\n"));
  const [focus, setFocus] = React.useState((existing?.muscle_focus ?? []).join("\n"));
  const [requirements, setRequirements] = React.useState((existing?.requirements ?? []).join("\n"));
  const [animationUrl, setAnimationUrl] = React.useState(existing?.animation_url ?? "");
  const [bodyweightPct, setBodyweightPct] = React.useState(String(Math.round((existing?.bodyweight_factor ?? 1) * 100)));
  const [variants, setVariants] = React.useState((existing?.variants ?? []).map((v) => `${v.name}: ${v.description}${v.source_url ? ` | ${v.source_url}` : ""}`).join("\n"));

  const onCategoryChange = (next: ExerciseCategory) => {
    setCategory(next);
    if (!existing && primary.length <= 1) setPrimary([DEFAULT_PRIMARY[next]]);
  };

  const toggle = (list: string[], set: (v: string[]) => void, id: string, otherSet?: (v: string[]) => void, other?: string[]) => {
    if (list.includes(id)) set(list.filter((m) => m !== id));
    else {
      set([...list, id]);
      if (otherSet && other) otherSet(other.filter((m) => m !== id));
    }
  };

  const validate = (): boolean => {
    const errs: Record<string, string> = {};
    if (name.trim().length < 2) errs.name = "Mindestens 2 Zeichen";
    if (name.trim().length > 80) errs.name = "Maximal 80 Zeichen";
    if (primary.length === 0) errs.primary = "Mindestens eine primäre Muskelgruppe wählen";
    if (animationUrl && !/^(https?:\/\/|\/).+/.test(animationUrl.trim())) errs.animationUrl = "Bitte eine vollständige URL (https://…) angeben";
    if (equipment === "bodyweight") {
      const pct = parseFloat(bodyweightPct.replace(",", "."));
      if (Number.isNaN(pct) || pct < 0 || pct > 200) errs.bodyweightPct = "Zwischen 0 und 200 %";
    }
    setErrors(errs);
    return Object.keys(errs).length === 0;
  };

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validate()) return;
    setBusy(true);
    const input: CustomExerciseInput = {
      name: name.trim(),
      category,
      equipment,
      primary_muscles: primary,
      secondary_muscles: secondary.filter((m) => !primary.includes(m)),
      grip_id: equipment === "cable" && gripId ? gripId : null,
      grip_notes: gripNotes.trim() || null,
      description: description.trim() || null,
      setup: linesToArray(setup),
      execution: linesToArray(execution),
      breathing: breathing.trim() || null,
      common_mistakes: linesToArray(mistakes),
      tips: linesToArray(tips),
      muscle_focus: linesToArray(focus),
      requirements: linesToArray(requirements),
      image_url: existing?.image_url ?? null,
      animation_url: animationUrl.trim() || null,
      bodyweight_factor: equipment === "bodyweight" ? Math.round(parseFloat(bodyweightPct.replace(",", ".")) ) / 100 : 1,
      variants: parseVariants(variants),
    };
    try {
      const db = createClient();
      if (existing) {
        await updateCustomExercise(db, existing.id, input);
        toast.success("Übung gespeichert");
        router.push(`/exercises/${existing.slug}`);
      } else {
        const created = await createCustomExercise(db, userId, input);
        toast.success("Übung erstellt");
        router.push(`/exercises/${created.slug}`);
      }
      router.refresh();
    } catch (err) {
      toast.error(friendlyError(err));
      setBusy(false);
    }
  };

  return (
    <form onSubmit={onSubmit} className="space-y-5" noValidate>
      <Card>
        <CardContent className="space-y-4 pt-5">
          <Field label="Name" htmlFor="name" error={errors.name}>
            <Input id="name" value={name} onChange={(e) => setName(e.target.value)} maxLength={80} required invalid={!!errors.name} />
          </Field>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Field label="Muskelgruppe (Kategorie)" htmlFor="category">
              <Select id="category" value={category} onChange={(e) => onCategoryChange(e.target.value as ExerciseCategory)}>
                {CATEGORY_ORDER.map((c) => (
                  <option key={c} value={c}>
                    {CATEGORY_LABELS[c]}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Equipment" htmlFor="equipment">
              <Select id="equipment" value={equipment} onChange={(e) => setEquipment(e.target.value as EquipmentType)}>
                {EQUIPMENT_ORDER.map((eq) => (
                  <option key={eq} value={eq}>
                    {EQUIPMENT_LABELS[eq]}
                  </option>
                ))}
              </Select>
            </Field>
          </div>
          <p className="text-sm text-muted">
            Getrackt wird als <span className="font-semibold text-fg">{TRACKING_LABELS[deriveTrackingMode(category, equipment)]}</span>.
          </p>
          {equipment === "bodyweight" ? (
            <Field
              label="Anteil des Körpergewichts"
              htmlFor="bodyweightPct"
              error={errors.bodyweightPct}
              hint="Wie viel Prozent deines Körpergewichts bei dieser Übung bewegt werden, z. B. Klimmzug 100 %, Liegestütz 65 %, Hyperextensions 60 %. Daraus wird die reale Last berechnet."
            >
              <div className="flex items-center gap-2">
                <Input id="bodyweightPct" inputMode="numeric" value={bodyweightPct} onChange={(e) => setBodyweightPct(e.target.value)} className="max-w-[8rem]" invalid={!!errors.bodyweightPct} />
                <span className="text-base text-muted">%</span>
              </div>
            </Field>
          ) : null}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="space-y-4 pt-5">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-start">
            <div className="sm:w-44 shrink-0">
              <MuscleMap primary={primary} secondary={secondary} compact showLegend={false} />
            </div>
            <div className="flex-1 space-y-4">
              <div>
                <SectionLabel>Primäre Muskeln</SectionLabel>
                {errors.primary ? <p className="mt-1 text-sm text-danger">{errors.primary}</p> : null}
                <ChipGrid ids={MUSCLE_IDS} selected={primary} onToggle={(id) => toggle(primary, setPrimary, id, setSecondary, secondary)} />
              </div>
              <div>
                <SectionLabel>Sekundäre Muskeln</SectionLabel>
                <ChipGrid
                  ids={MUSCLE_IDS.filter((m) => !primary.includes(m))}
                  selected={secondary}
                  onToggle={(id) => toggle(secondary, setSecondary, id)}
                  tone="secondary"
                />
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="space-y-4 pt-5">
          {equipment === "cable" ? (
            <Field label="Griff (Kabelzug)" htmlFor="grip">
              <Select id="grip" value={gripId} onChange={(e) => setGripId(e.target.value)}>
                <option value="">Kein spezieller Griff</option>
                {grips.map((g) => (
                  <option key={g.id} value={g.id}>
                    {g.name_de}
                  </option>
                ))}
              </Select>
            </Field>
          ) : null}
          <Field label="Hinweise zum Griff (optional)" htmlFor="gripNotes">
            <Input id="gripNotes" value={gripNotes} onChange={(e) => setGripNotes(e.target.value)} maxLength={300} />
          </Field>
          <Field label="Beschreibung (optional)" htmlFor="description">
            <Textarea id="description" value={description} onChange={(e) => setDescription(e.target.value)} maxLength={600} rows={2} />
          </Field>
          <Field label="Setup / Startposition (optional)" htmlFor="setup" hint="Ein Schritt pro Zeile">
            <Textarea id="setup" value={setup} onChange={(e) => setSetup(e.target.value)} rows={4} />
          </Field>
          <Field label="Ausführung (optional)" htmlFor="execution" hint="Ein Schritt pro Zeile">
            <Textarea id="execution" value={execution} onChange={(e) => setExecution(e.target.value)} rows={5} />
          </Field>
          <Field label="Atmung (optional)" htmlFor="breathing">
            <Input id="breathing" value={breathing} onChange={(e) => setBreathing(e.target.value)} maxLength={300} />
          </Field>
          <Field label="Häufige Fehler (optional)" htmlFor="mistakes" hint="Ein Punkt pro Zeile">
            <Textarea id="mistakes" value={mistakes} onChange={(e) => setMistakes(e.target.value)} rows={3} />
          </Field>
          <Field label="Hinweise / Tipps (optional)" htmlFor="tips" hint="Ein Punkt pro Zeile">
            <Textarea id="tips" value={tips} onChange={(e) => setTips(e.target.value)} rows={3} />
          </Field>
          <Field label="Muskelfokus (optional)" htmlFor="focus" hint="Wie der Muskel am besten getroffen wird, ein Punkt pro Zeile">
            <Textarea id="focus" value={focus} onChange={(e) => setFocus(e.target.value)} rows={3} />
          </Field>
          <Field label="Das brauchst du (optional)" htmlFor="requirements" hint="Ausstattung, ein Punkt pro Zeile">
            <Textarea id="requirements" value={requirements} onChange={(e) => setRequirements(e.target.value)} rows={2} />
          </Field>
          <Field label="Varianten (optional)" htmlFor="variants" hint="Eine je Zeile im Format „Name: Beschreibung“, optional „| https://…“ für einen Link. Unterschiede derselben Übung hier erklären statt eine zweite Übung anzulegen.">
            <Textarea id="variants" value={variants} onChange={(e) => setVariants(e.target.value)} rows={3} placeholder="Stehend: Knie gestreckt, trifft den Gastrocnemius" />
          </Field>
          <Field label="Animations-URL (optional)" htmlFor="animationUrl" error={errors.animationUrl} hint="GIF, WebP oder MP4 der Ausführung">
            <Input id="animationUrl" type="url" value={animationUrl} onChange={(e) => setAnimationUrl(e.target.value)} invalid={!!errors.animationUrl} />
          </Field>
        </CardContent>
      </Card>

      <div className="flex gap-2">
        <Button type="button" variant="secondary" onClick={() => router.back()} fullWidth>
          Abbrechen
        </Button>
        <Button type="submit" loading={busy} fullWidth>
          {existing ? "Speichern" : "Übung erstellen"}
        </Button>
      </div>
    </form>
  );
}

function ChipGrid({
  ids,
  selected,
  onToggle,
  tone = "primary",
}: {
  ids: MuscleId[];
  selected: string[];
  onToggle: (id: string) => void;
  tone?: "primary" | "secondary";
}) {
  return (
    <div className="mt-2 flex flex-wrap gap-1.5">
      {ids.map((id) => {
        const active = selected.includes(id);
        return (
          <button
            key={id}
            type="button"
            onClick={() => onToggle(id)}
            aria-pressed={active}
            className={cn(
              "h-8 rounded-full border px-3 text-xs font-medium transition-colors touch-manipulation",
              active
                ? tone === "primary"
                  ? "border-accent bg-accent-soft text-accent"
                  : "border-border-strong bg-subtle text-fg"
                : "border-border bg-card text-muted hover:text-fg"
            )}
          >
            {MUSCLE_LABELS[id]}
          </button>
        );
      })}
    </div>
  );
}
