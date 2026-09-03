// C-2: guessing a company's ATS board slug from what we already know.
//
// Pure and tested. The generation half is cheap; the expensive and dangerous
// half is what the prober does with these — see probe-ats-tokens, which will
// not accept a name-derived guess without corroboration, because
// `greenhouse.io/acme` is very probably somebody else's Acme.

export type SlugProvenance =
  // Derived from the company's own domain. Strong: a board living at a
  // company's own domain stem is almost certainly that company.
  | "domain"
  // Derived from the display name. Weak on its own — plenty of companies
  // share a first word.
  | "name";

export type SlugCandidate = {
  slug: string;
  provenance: SlugProvenance;
};

// Legal suffixes carried in display names but almost never in board slugs.
const LEGAL_SUFFIXES = [
  "inc", "llc", "ltd", "limited", "corp", "corporation", "co", "company",
  "gmbh", "bv", "nv", "sa", "ab", "oy", "as", "plc", "pty", "srl", "spa",
];

function stripLegalSuffix(words: string[]): string[] {
  const out = [...words];
  while (out.length > 1 && LEGAL_SUFFIXES.includes(out[out.length - 1])) {
    out.pop();
  }
  // A name that is ONLY a legal suffix ("Co", "Ltd") is not a usable slug.
  // Probing greenhouse.io/co is the archetypal over-broad guess.
  if (out.length === 1 && LEGAL_SUFFIXES.includes(out[0])) return [];
  return out;
}

// Trailing TLD words left behind when a display name is really a domain:
// "1stDibs.com" squashes to "1stdibscom" and would otherwise never equal
// "1stdibs".
const TLD_WORDS = ["com", "io", "ai", "co", "net", "org", "app", "dev", "xyz"];

function stripTLDWord(words: string[]): string[] {
  const out = [...words];
  if (out.length > 1 && TLD_WORDS.includes(out[out.length - 1])) out.pop();
  return out;
}

function nameWords(name: string): string[] {
  return name
    .toLowerCase()
    .replace(/[’'`]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
}

/// Bare host, no scheme, no www, no path.
function cleanDomain(domain: string): string {
  return domain
    .toLowerCase()
    .replace(/^https?:\/\//, "")
    .replace(/^www\./, "")
    .split("/")[0]
    .trim();
}

/// Ordered best-guess first, deduped. Kept deliberately short: every extra
/// candidate multiplies out across five ATS (six, counting Lever's EU shard),
/// and the marginal candidates are the ones most likely to hit a DIFFERENT
/// company's board.
export function slugCandidates(
  name: string | null | undefined,
  domain: string | null | undefined,
): SlugCandidate[] {
  const out: SlugCandidate[] = [];
  const seen = new Set<string>();
  const push = (slug: string, provenance: SlugProvenance) => {
    const cleaned = slug.trim();
    if (!cleaned || cleaned.length < 2 || seen.has(cleaned)) return;
    seen.add(cleaned);
    out.push({ slug: cleaned, provenance });
  };

  const host = domain ? cleanDomain(domain) : "";
  if (host) {
    const stem = host.split(".")[0];
    push(stem, "domain");
    // Ashby boards are sometimes registered under the full domain —
    // production has jobs.ashbyhq.com/datasnipper.com/... — so the dot is
    // meaningful and must not be stripped away here.
    push(host, "domain");
    // And sometimes the dots are simply removed: 1stdibs.com -> 1stdibscom,
    // which is a real Greenhouse token in this database.
    push(host.replace(/\./g, ""), "domain");
  }

  if (name) {
    const words = stripLegalSuffix(nameWords(name));
    if (words.length) {
      push(words.join(""), "name");
      push(words.join("-"), "name");
    }
  }

  return out;
}

/// Lever is CASE-SENSITIVE: api.lever.co/v0/postings/Kyverna returns 200 and
/// /kyverna returns 404, and production holds boards under both shapes. Every
/// other supported ATS is case-insensitive, so this variant is generated only
/// where it can matter.
export function leverCaseVariants(
  candidate: SlugCandidate,
  name: string | null | undefined,
): string[] {
  const variants = [candidate.slug];
  const words = name ? stripLegalSuffix(nameWords(name)) : [];
  if (words.length === 1) {
    const capitalised = words[0][0].toUpperCase() + words[0].slice(1);
    if (capitalised !== candidate.slug) variants.push(capitalised);
  }
  return variants;
}

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

/// Does the name a board reports match the company we were probing for?
///
/// Greenhouse is the only supported ATS that returns a company name, and it is
/// the strongest confirmation available: `boards-api.greenhouse.io/v1/boards/
/// stripe` answers {"name":"Stripe"}. Compared on squashed alphanumerics so
/// "1stdibs" matches "1stDibs.com" and "Shift Technology" matches "Shift
/// Technology, Inc."
export function boardNameMatches(
  boardName: string | null | undefined,
  companyName: string | null | undefined,
): boolean {
  const squash = (v: string | null | undefined) =>
    stripTLDWord(stripLegalSuffix(nameWords(v ?? ""))).join("");
  const a = squash(boardName);
  const b = squash(companyName);
  if (!a || !b) return false;
  // EXACT equality, deliberately. A prefix rule reads well on "Stripe" vs
  // "Stripe Payments" and then quietly accepts "Coalition" for a board named
  // "Coalition Technologies", which is a different company. Nothing in the
  // strings distinguishes those two cases, so the ambiguity is resolved in
  // favour of missing: an unconfirmed probe just leaves the company unresolved
  // and costs one more crawl attempt later, while a false positive attributes
  // another employer's entire job board to them.
  return a === b;
}
