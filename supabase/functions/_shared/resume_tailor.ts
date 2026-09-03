// S-4: the pure half of resume tailoring — bullet identity, override
// application, and the fabrication check.
//
// The model call lives in tailor-resume. Everything here is deterministic and
// covered by shared_test.ts, because this is the code that decides whether a
// claim the candidate never made ends up on a resume they send to an employer.

export type TailoredBullet = {
  key: string;
  original: string;
  tailored: string;
  keywords_added?: string[];
};

export type TailoredEmployer = {
  company: string;
  title: string;
  dates?: string;
  bullets: TailoredBullet[];
};

export type TailoredResume = {
  summary?: string;
  skills_ordered?: string[];
  employment: TailoredEmployer[];
  keywords_covered?: string[];
  keywords_still_missing?: string[];
};

// ---------------------------------------------------------------------------
// Bullet identity
// ---------------------------------------------------------------------------

// A bullet's key is derived from its ORIGINAL text, so it survives being
// rewritten — which is the whole point. An override recorded against "Built
// the ledger service" still applies after the model rephrases that line for a
// different job, because both tailorings hash the same source sentence.
//
// Whitespace and case are normalized out; the parser is told to copy bullets
// verbatim, but a stray double space must not orphan someone's edit.
//
// FNV-1a rather than SHA-256: this runs over every bullet on every tailoring,
// needs no cryptographic property, and crypto.subtle is async, which would
// make every caller here async for no reason.
export function bulletKey(original: string): string {
  const normalized = (original ?? "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
  let hash = 0x811c9dc5;
  for (let i = 0; i < normalized.length; i++) {
    hash ^= normalized.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

// ---------------------------------------------------------------------------
// Overrides
// ---------------------------------------------------------------------------

// The candidate's own rewrite always wins over the model's. Applied AFTER
// generation rather than by prompting, so an override cannot be ignored,
// paraphrased, or "improved" by the next tailoring pass.
export function applyOverrides(
  resume: TailoredResume,
  overrides: Record<string, string> | null | undefined,
): TailoredResume {
  if (!overrides || Object.keys(overrides).length === 0) return resume;
  return {
    ...resume,
    employment: resume.employment.map((employer) => ({
      ...employer,
      bullets: employer.bullets.map((bullet) => {
        const override = overrides[bullet.key];
        if (typeof override !== "string" || !override.trim()) return bullet;
        return { ...bullet, tailored: override.trim() };
      }),
    })),
  };
}

// ---------------------------------------------------------------------------
// Fabrication check
// ---------------------------------------------------------------------------

export type FabricationReport = {
  ok: boolean;
  droppedEmployers: string[];
  addedEmployers: string[];
  changedTitles: Array<{ company: string; before: string; after: string }>;
  inventedBullets: string[];
};

export type SourceEmployer = {
  company?: string | null;
  title?: string | null;
  bullets?: string[] | null;
};

function key(value: string | null | undefined): string {
  return (value ?? "").toLowerCase().replace(/\s+/g, " ").trim();
}

// The model is instructed never to add or change an employer, a title, or a
// bullet's underlying claim. Instructions are not a guarantee, and this is a
// document a person sends to an employer under their own name — so the output
// is checked against the source rather than trusted.
//
// Rephrasing IS allowed, so bullets are verified by identity (every tailored
// bullet must trace to a real source bullet through its key), not by text
// comparison. Dropping a bullet is fine: omission is a legitimate tailoring
// move. Inventing one is not.
export function checkFabrication(
  tailored: TailoredResume,
  source: SourceEmployer[],
): FabricationReport {
  const sourceByCompany = new Map<string, SourceEmployer>();
  const sourceKeys = new Set<string>();
  for (const employer of source) {
    sourceByCompany.set(key(employer.company), employer);
    for (const bullet of employer.bullets ?? []) {
      if (bullet?.trim()) sourceKeys.add(bulletKey(bullet));
    }
  }

  const seenCompanies = new Set<string>();
  const addedEmployers: string[] = [];
  const changedTitles: Array<{ company: string; before: string; after: string }> = [];
  const inventedBullets: string[] = [];

  for (const employer of tailored.employment ?? []) {
    const companyKey = key(employer.company);
    seenCompanies.add(companyKey);

    const original = sourceByCompany.get(companyKey);
    if (!original) {
      addedEmployers.push(employer.company);
      continue;
    }
    if (key(employer.title) !== key(original.title)) {
      changedTitles.push({
        company: employer.company,
        before: original.title ?? "",
        after: employer.title,
      });
    }
    for (const bullet of employer.bullets ?? []) {
      // Trust the key only if it actually matches the original text it claims
      // to come from — otherwise a fabricated bullet could ship with a valid
      // key copied off a real one.
      if (bulletKey(bullet.original) !== bullet.key || !sourceKeys.has(bullet.key)) {
        inventedBullets.push(bullet.tailored || bullet.original);
      }
    }
  }

  // Dropping a whole role is reported but does not fail the check: omitting an
  // irrelevant job is a normal, legitimate tailoring decision.
  const droppedEmployers = [...sourceByCompany.keys()]
    .filter((c) => c && !seenCompanies.has(c));

  return {
    ok: addedEmployers.length === 0
      && changedTitles.length === 0
      && inventedBullets.length === 0,
    droppedEmployers,
    addedEmployers,
    changedTitles,
    inventedBullets,
  };
}

// ---------------------------------------------------------------------------
// Prompt
// ---------------------------------------------------------------------------

export function tailorSystemPrompt(): string {
  return `Tailor this resume to the job description.

YOU MAY: reorder bullets and roles, rephrase bullets, omit bullets, reorder the
skills list, and write a short summary.

YOU MAY NOT: add or remove an employer, change a job title, change any date,
change any number or metric, or add a skill the resume does not already
evidence.

Every tailored bullet must be a faithful re-expression of its original: the
same accomplishment, the same numbers, the same scope. Return the original text
and its key unchanged alongside your rewrite. If a bullet cannot be improved
without changing what it claims, return it unchanged.

Surface keywords from the job description ONLY where the original bullet
already supports them. If the posting requires something the resume does not
evidence anywhere, list it in keywords_still_missing. Do not manufacture
coverage — a resume that claims a skill the candidate lacks fails at the
interview instead of the filter, which is worse for them.

Write plainly. No "spearheaded", "leveraged", "synergy". Lead each bullet with
what was done, not with an adjective.`;
}

export const TAILOR_SCHEMA: Record<string, unknown> = {
  type: "object",
  additionalProperties: false,
  required: ["summary", "skills_ordered", "employment", "keywords_covered", "keywords_still_missing"],
  properties: {
    summary: { type: "string" },
    skills_ordered: { type: "array", items: { type: "string" } },
    employment: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["company", "title", "dates", "bullets"],
        properties: {
          company: { type: "string" },
          title: { type: "string" },
          dates: { type: "string" },
          bullets: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: ["key", "original", "tailored", "keywords_added"],
              properties: {
                key: { type: "string" },
                original: { type: "string" },
                tailored: { type: "string" },
                keywords_added: { type: "array", items: { type: "string" } },
              },
            },
          },
        },
      },
    },
    keywords_covered: { type: "array", items: { type: "string" } },
    keywords_still_missing: { type: "array", items: { type: "string" } },
  },
};
