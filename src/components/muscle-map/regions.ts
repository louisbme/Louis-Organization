/**
 * Stilisierte Muskelkarte (SVG). Alle Pfade beziehen sich auf die linke Körperhälfte
 * eines 200×420-Koordinatensystems und werden für die rechte Seite gespiegelt.
 * Zentrale (nicht gespiegelte) Regionen sind mit `mirror: false` gekennzeichnet.
 */

export type View = "front" | "back";

export interface Region {
  id: string;
  d: string;
  mirror: boolean;
}

/** Körpersilhouette (Basis, beide Ansichten gleich) */
export const SILHOUETTE: Region[] = [
  { id: "head", d: "M100,13 C112,13 120,23 120,37 C120,51 112,60 100,60 C88,60 80,51 80,37 C80,23 88,13 100,13 Z", mirror: false },
  { id: "neck", d: "M90,56 L110,56 L111,74 L89,74 Z", mirror: false },
  {
    id: "torso",
    d: "M100,72 L60,78 C50,80 44,88 44,98 L46,124 C48,150 54,170 56,190 C58,204 60,212 64,220 L100,224 Z",
    mirror: true,
  },
  { id: "upper_arm", d: "M44,92 C36,92 30,98 29,106 L24,160 C23,168 30,172 38,170 L50,164 L58,112 C58,100 52,92 44,92 Z", mirror: true },
  { id: "forearm", d: "M24,162 L48,164 L40,226 C38,232 22,232 20,226 Z", mirror: true },
  { id: "hand", d: "M20,226 L40,226 C42,238 36,250 30,250 C24,250 18,238 20,226 Z", mirror: true },
  { id: "thigh", d: "M64,218 L98,222 L98,322 L62,324 C58,300 58,250 64,218 Z", mirror: true },
  { id: "lower_leg", d: "M62,324 L98,322 L94,404 L66,406 Z", mirror: true },
  { id: "foot", d: "M66,404 L94,402 C96,412 90,420 80,420 L68,420 C62,418 62,410 66,404 Z", mirror: true },
];

/** Vorderansicht – Muskelregionen */
export const FRONT_REGIONS: Region[] = [
  { id: "delt_outer", d: "M46,85 C37,85 31,91 31,98 C31,105 37,110 46,110 Z", mirror: true },
  { id: "delt_inner", d: "M46,85 C55,85 61,91 61,98 C61,105 55,110 46,110 Z", mirror: true },
  { id: "upper_chest", d: "M98,80 L64,86 C60,91 59,97 60,103 L98,101 Z", mirror: true },
  { id: "chest", d: "M98,101 L60,103 C60,115 64,127 74,133 C84,136 94,135 98,131 Z", mirror: true },
  { id: "biceps", d: "M44,98 C52,100 56,108 54,118 L48,150 C46,156 38,156 36,150 L38,110 C38,103 40,98 44,98 Z", mirror: true },
  { id: "forearm", d: "M30,164 C38,162 46,166 46,172 L38,220 C36,226 26,226 24,220 L26,174 C26,168 27,164 30,164 Z", mirror: true },
  { id: "abs", d: "M86,134 L114,134 C118,134 120,137 120,141 L118,194 C118,199 115,202 110,202 L90,202 C85,202 82,199 82,194 L80,141 C80,137 82,134 86,134 Z", mirror: false },
  { id: "obliques", d: "M70,136 C76,136 80,140 80,146 L82,196 C82,203 76,207 70,205 C66,190 64,160 70,136 Z", mirror: true },
  { id: "quads", d: "M66,226 C80,222 92,226 96,232 L95,306 C92,314 72,318 66,310 C62,290 62,250 66,226 Z", mirror: true },
  { id: "calves_front", d: "M66,330 C76,328 90,330 92,336 L90,390 C88,396 70,398 68,392 C64,370 63,350 66,330 Z", mirror: true },
];

/** Rückansicht – Muskelregionen */
export const BACK_REGIONS: Region[] = [
  { id: "delt_outer", d: "M46,85 C37,85 31,91 31,98 C31,105 37,110 46,110 Z", mirror: true },
  { id: "delt_inner", d: "M46,85 C55,85 61,91 61,98 C61,105 55,110 46,110 Z", mirror: true },
  { id: "traps", d: "M100,60 L64,86 L76,98 L100,140 L124,98 L136,86 Z", mirror: false },
  { id: "upper_back", d: "M62,100 L76,100 L98,138 L86,140 L68,138 C62,130 60,114 62,100 Z", mirror: true },
  { id: "lats", d: "M62,142 L86,144 L94,150 L94,186 C84,190 72,188 66,180 C60,166 58,154 62,142 Z", mirror: true },
  { id: "mid_back", d: "M100,142 L95,150 L95,186 L105,186 L105,150 Z", mirror: false },
  { id: "lower_back", d: "M100,188 L88,192 C86,202 88,212 94,217 L100,219 L106,217 C112,212 114,202 112,192 Z", mirror: false },
  { id: "triceps", d: "M42,98 C50,98 55,105 54,114 L48,150 C46,156 38,156 36,150 L37,110 C37,103 39,98 42,98 Z", mirror: true },
  { id: "forearm", d: "M30,164 C38,162 46,166 46,172 L38,220 C36,226 26,226 24,220 L26,174 C26,168 27,164 30,164 Z", mirror: true },
  { id: "glutes", d: "M66,222 C80,218 96,222 98,234 L98,258 C96,266 80,270 68,264 C62,252 62,234 66,222 Z", mirror: true },
  { id: "hamstrings", d: "M66,268 C78,266 92,268 96,272 L95,312 C92,318 72,320 66,314 C62,298 62,282 66,268 Z", mirror: true },
  { id: "calves", d: "M66,328 C78,326 92,328 94,334 L92,382 C90,390 72,392 68,384 C64,368 62,342 66,328 Z", mirror: true },
];

/** Welche Regionen je Ansicht eine Muskelgruppe repräsentieren */
export const MUSCLE_REGIONS: Record<string, { front: string[]; back: string[] }> = {
  chest: { front: ["chest"], back: [] },
  upper_chest: { front: ["upper_chest"], back: [] },
  front_delts: { front: ["delt_inner"], back: [] },
  side_delts: { front: ["delt_outer"], back: ["delt_outer"] },
  rear_delts: { front: [], back: ["delt_inner"] },
  traps: { front: [], back: ["traps"] },
  lats: { front: [], back: ["lats"] },
  upper_back: { front: [], back: ["upper_back"] },
  mid_back: { front: [], back: ["mid_back"] },
  lower_back: { front: [], back: ["lower_back"] },
  biceps: { front: ["biceps"], back: [] },
  triceps: { front: [], back: ["triceps"] },
  forearms: { front: ["forearm"], back: ["forearm"] },
  abs: { front: ["abs"], back: [] },
  obliques: { front: ["obliques"], back: [] },
  quads: { front: ["quads"], back: [] },
  hamstrings: { front: [], back: ["hamstrings"] },
  glutes: { front: [], back: ["glutes"] },
  calves: { front: ["calves_front"], back: ["calves"] },
};
