// Carousel theme registry.
//
// Themes are visual bundles (palette, typography, motif) defined in the
// iOS app. The backend only knows the theme IDs and uses them as a
// deterministic, industry-aware selection set. Keep this list in sync
// with the app's theme bundle — adding a theme means: register the ID
// here, ship it in the app, and (optionally) tag it into a group.

export const THEME_IDS = [
  // Cool / minimalist — fintech, dev tools, infra
  "indigo-grid",
  "slate-gradient",
  "midnight-mono",
  // Warm / human — consumer, marketplace, healthcare
  "sunset-paper",
  "coral-soft",
  "amber-glow",
  // Earthy / organic — climate, agtech, biotech
  "moss-grain",
  "clay-edge",
  // Playful / bold — gaming, social, creator tools
  "neon-pop",
  "bubble-pastel",
] as const;

export type ThemeId = (typeof THEME_IDS)[number];

// Industry → theme group bias. Picks within the named subset so a
// fintech company doesn't land on a bubblegum theme. Unmatched
// industries fall through to the full set.
const INDUSTRY_GROUPS: Record<string, ThemeId[]> = {
  fintech: ["indigo-grid", "slate-gradient", "midnight-mono"],
  finance: ["indigo-grid", "slate-gradient", "midnight-mono"],
  "dev tools": ["indigo-grid", "slate-gradient", "midnight-mono"],
  infrastructure: ["indigo-grid", "slate-gradient", "midnight-mono"],
  saas: ["indigo-grid", "slate-gradient", "sunset-paper"],
  consumer: ["sunset-paper", "coral-soft", "amber-glow"],
  marketplace: ["sunset-paper", "coral-soft", "amber-glow"],
  healthcare: ["sunset-paper", "coral-soft", "moss-grain"],
  "health care": ["sunset-paper", "coral-soft", "moss-grain"],
  health: ["sunset-paper", "coral-soft", "moss-grain"],
  climate: ["moss-grain", "clay-edge", "amber-glow"],
  agtech: ["moss-grain", "clay-edge"],
  biotech: ["moss-grain", "clay-edge", "sunset-paper"],
  gaming: ["neon-pop", "bubble-pastel"],
  social: ["neon-pop", "bubble-pastel", "coral-soft"],
  creator: ["neon-pop", "bubble-pastel", "coral-soft"],
  ai: ["indigo-grid", "midnight-mono", "neon-pop"],
};

// Deterministic pick: same (company_id, industry) always yields the same
// theme. Uses a fast 32-bit hash of the company UUID so the choice is
// stable across runs without persisting anything extra.
export function pickTheme(companyId: string, industry: string | null): ThemeId {
  const pool = bucketForIndustry(industry) ?? THEME_IDS;
  const h = hashString(companyId);
  return pool[h % pool.length];
}

function bucketForIndustry(industry: string | null): ThemeId[] | null {
  if (!industry) return null;
  const key = industry.trim().toLowerCase();
  if (INDUSTRY_GROUPS[key]) return INDUSTRY_GROUPS[key];
  // Loose contains-match for compound labels like "Fintech / Payments".
  for (const k of Object.keys(INDUSTRY_GROUPS)) {
    if (key.includes(k)) return INDUSTRY_GROUPS[k];
  }
  return null;
}

// FNV-1a 32-bit. Plenty for theme bucketing — we only need uniform
// distribution mod N where N ≤ ~10.
function hashString(input: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = (hash + ((hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24))) >>> 0;
  }
  return hash >>> 0;
}
