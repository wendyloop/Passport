// Canonical profile-field vocabulary.
//
// Three consumers share this file:
//   - parse-resume:           writes canonical fields after LLM extraction.
//   - store-application-fields: maps an ATS form label → canonical key when
//                              it can, otherwise stores the raw label as-is.
//   - get-prefill-profile:    returns canonical fields to the iOS WebView
//                              so the bridge can prefill matched inputs.
//
// All canonical labels live in candidate_field_history.field_label with the
// CANON_PREFIX so we never collide with raw ATS labels. The prefix matters:
// `canon:first_name` and `First name` are *different* rows, and the canonical
// row is the autoritative one that survives across applications.

export const CANON_PREFIX = "canon:";

export type CanonicalKey =
  | "first_name"
  | "last_name"
  | "full_name"
  | "email"
  | "phone"
  | "city"
  | "state"
  | "country"
  | "postal_code"
  | "linkedin_url"
  | "github_url"
  | "portfolio_url"
  | "personal_website"
  | "twitter_url"
  | "current_title"
  | "current_company"
  | "years_experience"
  | "highest_degree"
  | "school"
  | "graduation_year"
  | "field_of_study"
  | "work_authorization"
  | "requires_sponsorship"
  | "salary_expectation"
  | "available_start_date"
  | "preferred_location"
  | "willing_to_relocate"
  | "remote_preference"
  | "commute_ok"
  | "pronouns"
  | "referral_source"
  | "how_did_you_hear";

// EEO / protected-class labels are never stored. They used to have canonical
// keys here (gender, race_ethnicity, veteran_status, disability_status), which
// meant an answer given once was written to candidate_field_history and then
// prefilled into every later application. Storing them makes those rows GDPR
// Art. 9 special-category data and breaks the segregation EEO reporting
// depends on. The client blocks them at capture (ATSAutofillPolicy); this is
// the server-side backstop for any client that doesn't.
const SENSITIVE_LABEL_PATTERNS: RegExp[] = [
  /\brace\b/i,
  /ethnic/i,
  /disab/i,
  /\bveteran\b/i,
  /\bgender\b/i,
  /\bsex\b/i,
  /sexual/i,
  /pregnan/i,
  /religio/i,
  /politic/i,
  /trade union/i,
  /genetic/i,
  /biometric/i,
];

export function isSensitiveLabel(rawLabel: string): boolean {
  const cleaned = rawLabel.trim();
  if (!cleaned) return false;
  return SENSITIVE_LABEL_PATTERNS.some((p) => p.test(cleaned));
}

export type CanonicalLabel = `${typeof CANON_PREFIX}${CanonicalKey}`;

export function canonLabel(key: CanonicalKey): CanonicalLabel {
  return `${CANON_PREFIX}${key}`;
}

// Heuristic matcher: for an ATS label like "Where do you live?" return
// the canonical key it most likely corresponds to, or null. Kept simple on
// purpose — high-precision matchers live in _shared/ats/ per provider.
const ALIASES: Record<CanonicalKey, RegExp[]> = {
  first_name:          [/^first[\s_-]?name$/i, /^given[\s_-]?name$/i],
  last_name:           [/^last[\s_-]?name$/i, /^surname$/i, /^family[\s_-]?name$/i],
  full_name:           [/^(full[\s_-]?)?name$/i, /^your[\s_-]?name$/i],
  email:               [/^e[\s_-]?mail( address)?$/i],
  phone:               [/^(phone|mobile|cell)( number)?$/i, /^tel(ephone)?$/i],
  city:                [/^city$/i, /^town$/i],
  state:               [/^(state|province|region)$/i],
  country:             [/^country$/i],
  postal_code:         [/^(zip|postal)[\s_-]?(code)?$/i],
  linkedin_url:        [/linkedin/i],
  github_url:          [/github/i],
  portfolio_url:       [/portfolio/i],
  personal_website:    [/^website$/i, /personal[\s_-]?site/i],
  twitter_url:         [/twitter/i, /^x[\s_-]?(handle|profile)?$/i],
  current_title:       [/^current[\s_-]?(job[\s_-]?)?title$/i, /^job[\s_-]?title$/i],
  current_company:     [/^current[\s_-]?(employer|company)$/i, /^employer$/i],
  years_experience:    [/years[\s_-]?of[\s_-]?experience/i, /^experience[\s_-]?\(years\)$/i],
  highest_degree:      [/highest[\s_-]?(level[\s_-]?of[\s_-]?)?(education|degree)/i, /^degree$/i],
  school:              [/^(school|university|college|institution)$/i],
  graduation_year:     [/grad(uation)?[\s_-]?year/i],
  field_of_study:      [/(major|field[\s_-]?of[\s_-]?study|concentration)/i],
  work_authorization:  [/work[\s_-]?(authoriz|eligibility)/i, /authoriz(ed|ation) to work/i],
  requires_sponsorship:[/sponsor(ship)?/i, /visa[\s_-]?sponsor/i],
  salary_expectation:  [/(salary|compensation|comp)[\s_-]?(expectation|requirement|range)/i, /desired[\s_-]?(salary|comp)/i],
  available_start_date:[/start[\s_-]?date/i, /available(_| to start)/i],
  preferred_location:  [/preferred[\s_-]?location/i, /where would you like to work/i],
  willing_to_relocate: [/relocat(e|ion)/i],
  remote_preference:   [/remote/i, /work[\s_-]?from[\s_-]?home/i],
  // "Are you able to commute to our SF office?" is asked by almost every
  // hybrid role, phrased differently each time — worth a canonical key so the
  // answer survives across ATS.
  commute_ok:          [/commut(e|ing)/i, /\bon[\s_-]?site\b/i, /\bin[\s_-]?office\b/i, /\bhybrid\b/i],
  pronouns:            [/pronouns?/i],
  referral_source:     [/referr(ed|al)/i, /who referred you/i],
  how_did_you_hear:    [/how (did|do) you hear/i],
};

export function matchCanonical(rawLabel: string): CanonicalKey | null {
  const cleaned = rawLabel.trim();
  if (!cleaned) return null;
  for (const [key, patterns] of Object.entries(ALIASES) as [CanonicalKey, RegExp[]][]) {
    if (patterns.some((p) => p.test(cleaned))) return key;
  }
  return null;
}
