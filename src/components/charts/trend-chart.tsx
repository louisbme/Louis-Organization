"use client";

import * as React from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { formatDecimal, formatVolume, formatWeight } from "@/lib/utils/format";
import type { WeightUnit } from "@/lib/supabase/types";

export interface TrendPoint {
  x: string;
  label: string;
  y: number;
  extra?: string;
}

/**
 * Serialisierbare Formatangabe – damit auch Server Components die Chart-Komponente
 * nutzen können (Funktionen dürfen nicht an Client Components übergeben werden).
 */
export type ValueFormat =
  | { kind: "volume"; unit: WeightUnit }
  | { kind: "weight"; unit: WeightUnit }
  | { kind: "decimal"; suffix?: string }
  | { kind: "integer"; suffix?: string }
  | { kind: "count"; singular: string; plural: string };

function makeFormatter(format: ValueFormat | undefined, unit: string): (v: number) => string {
  if (!format) return (v) => `${Math.round(v)}${unit ? ` ${unit}` : ""}`;
  switch (format.kind) {
    case "volume":
      return (v) => formatVolume(v, format.unit);
    case "weight":
      return (v) => formatWeight(v, format.unit);
    case "decimal":
      return (v) => `${formatDecimal(v)}${format.suffix ? ` ${format.suffix}` : ""}`;
    case "integer":
      return (v) => `${Math.round(v)}${format.suffix ? ` ${format.suffix}` : ""}`;
    case "count":
      return (v) => `${Math.round(v)} ${Math.round(v) === 1 ? format.singular : format.plural}`;
  }
}

interface TrendChartProps {
  data: TrendPoint[];
  type?: "bar" | "line";
  unit?: string;
  height?: number;
  color?: string;
  /** Serialisierbar, auch aus Server Components nutzbar */
  format?: ValueFormat;
  /** Nur aus Client Components (Funktion) */
  formatValue?: (v: number) => string;
  emptyLabel?: string;
}

export function TrendChart({
  data,
  type = "bar",
  unit = "",
  height = 180,
  color = "var(--chart-1)",
  format,
  formatValue,
  emptyLabel = "Noch keine Daten",
}: TrendChartProps) {
  const fmt = formatValue ?? makeFormatter(format, unit);

  if (data.length === 0) {
    return (
      <div className="flex items-center justify-center text-sm text-faint" style={{ height }}>
        {emptyLabel}
      </div>
    );
  }

  const axisProps = {
    tickLine: false,
    axisLine: false,
    tick: { fill: "var(--fg-subtle)", fontSize: 11 },
  };

  const tooltip = (
    <Tooltip
      cursor={{ fill: "var(--bg-hover)", stroke: "var(--border-strong)" }}
      content={({ active, payload }) => {
        if (!active || !payload || payload.length === 0) return null;
        const p = payload[0].payload as TrendPoint;
        return (
          <div className="rounded-lg border border-border bg-card px-3 py-2 text-xs shadow-lg">
            <p className="text-faint">{p.label}</p>
            <p className="tnum mt-0.5 font-semibold text-fg">{fmt(p.y)}</p>
            {p.extra ? <p className="text-muted">{p.extra}</p> : null}
          </div>
        );
      }}
    />
  );

  return (
    <ResponsiveContainer width="100%" height={height}>
      {type === "bar" ? (
        <BarChart data={data} margin={{ top: 8, right: 4, left: -18, bottom: 0 }} barCategoryGap="28%">
          <CartesianGrid vertical={false} stroke="var(--border)" />
          <XAxis dataKey="x" {...axisProps} interval="preserveStartEnd" minTickGap={24} />
          <YAxis {...axisProps} width={56} tickFormatter={(v: number) => compact(v)} />
          {tooltip}
          <Bar dataKey="y" fill={color} radius={[4, 4, 0, 0]} maxBarSize={36} isAnimationActive animationDuration={600} animationEasing="ease-out" />
        </BarChart>
      ) : (
        <LineChart data={data} margin={{ top: 8, right: 8, left: -18, bottom: 0 }}>
          <CartesianGrid vertical={false} stroke="var(--border)" />
          <XAxis dataKey="x" {...axisProps} interval="preserveStartEnd" minTickGap={24} />
          <YAxis {...axisProps} width={56} domain={["auto", "auto"]} tickFormatter={(v: number) => compact(v)} />
          {tooltip}
          <Line
            type="monotone"
            dataKey="y"
            stroke={color}
            strokeWidth={2}
            dot={{ r: 3, fill: color, strokeWidth: 0 }}
            activeDot={{ r: 5 }}
            isAnimationActive
            animationDuration={700}
            animationEasing="ease-out"
          />
        </LineChart>
      )}
    </ResponsiveContainer>
  );
}

function compact(v: number): string {
  if (Math.abs(v) >= 1000) return `${(v / 1000).toFixed(v >= 10000 ? 0 : 1).replace(".", ",")}k`;
  return String(Math.round(v * 10) / 10).replace(".", ",");
}
