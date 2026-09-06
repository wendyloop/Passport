// Unit tests for pure _shared helpers. Run with:
//   deno test --allow-env supabase/functions/_shared/shared_test.ts
// (--allow-env because email.ts reads RESEND_API_KEY at module load.)

import { assertEquals } from "jsr:@std/assert@1";
import { jsonError, jsonResponse } from "./http.ts";
import { escapeHtml } from "./email.ts";
import { firstNameOf, guessFounderEmail, normalizeDomain } from "./contacts.ts";
import { buildPipelineRunRow } from "./pipeline_runs.ts";
import { buildPitchEmailContent, pitchSubject } from "./pitch_email.ts";
import { attachmentFilename } from "./email_attachments.ts";
import { founderProfileGateReason } from "./founder_eligibility.ts";
import { buildJobEmbeddingText, buildResumeEmbeddingText, mapSimilarityToScore } from "./matching.ts";
import { isSensitiveLabel, matchCanonical, normalizeCanonicalValue } from "./profile_fields.ts";
import {
  buildResumeHaystack,
  diffKeywords,
  haystackContains,
  normalizeText,
  rankMissing,
} from "./keyword_match.ts";
import { coverLetterLooksGeneric } from "./answer_prompts.ts";
import {
  applyOverrides,
  bulletKey,
  checkFabrication,
} from "./resume_tailor.ts";
import {
  ADAPT_FLOOR,
  enforceCharLimit,
  pickMode,
  REUSE_FLOOR,
  selectVoiceSamples,
  targetWordCount,
  truncate,
} from "./answer_prompts.ts";
import { decodeHtmlEntities, extractPageProps, htmlToText } from "./boards/workatastartup.ts";
import { parseCompensation, sanitizeCompensation } from "./ats/compensation.ts";
import { classifyApplyURL, computeDedupKey } from "./ats/classify.ts";
import { harvestFromApplyURLs } from "./ats/harvest.ts";
import { keepForEarlyCareerFeed } from "./ats/crawl_filter.ts";
import { extractSeedCompanies } from "./ats/seed_listings.ts";
import {
  boardNameMatches,
  leverCaseVariants,
  slugCandidates,
} from "./ats/slug_candidates.ts";
import { buildMatchIndex, groupPendingJobs } from "./ats/enrich_targets.ts";
import type { NormalizedJob } from "./ats/models.ts";
import { feedIsAuthoritative, selectVanishedJobIds } from "./ats/vanished.ts";
import { classifyGetroDetail, getroJobDetailURL } from "./boards/getro_detail.ts";

Deno.test("jsonResponse sets status, CORS, and content type", async () => {
  const res = jsonResponse({ ok: true }, 201);
  assertEquals(res.status, 201);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
  assertEquals(res.headers.get("Content-Type"), "application/json");
  assertEquals(await res.json(), { ok: true });
});

Deno.test("jsonError wraps the message", async () => {
  const res = jsonError("nope", 403);
  assertEquals(res.status, 403);
  assertEquals(await res.json(), { error: "nope" });
});

Deno.test("escapeHtml neutralizes markup and quotes", () => {
  assertEquals(
    escapeHtml(`<script>alert("x&y'z")</script>`),
    "&lt;script&gt;alert(&quot;x&amp;y&#39;z&quot;)&lt;/script&gt;",
  );
});

Deno.test("guessFounderEmail: plain name and domain", () => {
  assertEquals(guessFounderEmail("Jane Doe", "acme.io"), "jane@acme.io");
});

Deno.test("guessFounderEmail: honorific skipped, diacritics stripped, www removed", () => {
  assertEquals(guessFounderEmail("Dr. José Álvarez-Smith", "www.Acme.io"), "jose@acme.io");
});

Deno.test("guessFounderEmail: URL-shaped domain normalized", () => {
  assertEquals(guessFounderEmail("patrick collison", "https://stripe.com/about"), "patrick@stripe.com");
});

Deno.test("guessFounderEmail: bare honorific yields null", () => {
  assertEquals(guessFounderEmail("Dr.", "acme.io"), null);
});

Deno.test("guessFounderEmail: dotless domain yields null", () => {
  assertEquals(guessFounderEmail("Jane Doe", "localhost"), null);
});

Deno.test("guessFounderEmail: empty name yields null", () => {
  assertEquals(guessFounderEmail("", "acme.io"), null);
});

Deno.test("normalizeDomain strips scheme, path, and www", () => {
  assertEquals(normalizeDomain("https://www.Foo.Bar/baz?q=1"), "foo.bar");
  assertEquals(normalizeDomain("www.foo.bar"), "foo.bar");
  assertEquals(normalizeDomain(""), null);
});

Deno.test("firstNameOf returns the first token or null", () => {
  assertEquals(firstNameOf("Jane Doe"), "Jane");
  assertEquals(firstNameOf("   "), null);
});

import { classifyExperience, classifyTitle, classifyWorkMode } from "./title_classify.ts";

Deno.test("classifyTitle buckets common titles", () => {
  assertEquals(classifyTitle("Senior Software Engineer, Payments"), "engineering");
  assertEquals(classifyTitle("Account Executive - Mid Market"), "sales");
  assertEquals(classifyTitle("Underwater Basket Weaver"), null);
});

Deno.test("classifyExperience: intern beats seniority words", () => {
  assertEquals(classifyExperience("Senior Software Engineering Intern"), "intern");
});

Deno.test("classifyExperience: word boundaries (Internal ≠ intern)", () => {
  assertEquals(classifyExperience("Internal Audit Manager"), null);
  assertEquals(classifyExperience("International Tax Analyst"), null);
});

Deno.test("classifyExperience: entry + senior + unknown", () => {
  assertEquals(classifyExperience("New Grad Engineer, Software"), "entry");
  assertEquals(classifyExperience("Sr. Product Designer"), "senior");
  assertEquals(classifyExperience("Software Engineer"), null);
});

Deno.test("classifyWorkMode: from location string only", () => {
  assertEquals(classifyWorkMode("Remote - US"), "remote");
  assertEquals(classifyWorkMode("New York (Hybrid)"), "hybrid");
  assertEquals(classifyWorkMode("San Francisco, CA"), null);
  assertEquals(classifyWorkMode(null), null);
});

// ─── pipeline_runs.ts (DB-P1-9) ─────────────────────────────────────────────

Deno.test("buildPipelineRunRow shapes the run row", () => {
  const started = Date.parse("2026-07-13T06:00:00Z");
  const row = buildPipelineRunRow(
    "ingest-jobs",
    started,
    { event: "ingest_jobs_run", jobs_inserted: 12 },
    2,
    started + 45_000,
  );
  assertEquals(row.function_name, "ingest-jobs");
  assertEquals(row.started_at, "2026-07-13T06:00:00.000Z");
  assertEquals(row.duration_ms, 45_000);
  assertEquals(row.summary, { event: "ingest_jobs_run", jobs_inserted: 12 });
  assertEquals(row.error_count, 2);
});

Deno.test("buildPipelineRunRow clamps negative durations", () => {
  const now = Date.now();
  const row = buildPipelineRunRow("x", now + 5_000, {}, 0, now);
  assertEquals(row.duration_ms, 0);
});

// ─── application_email.ts (AUDIT P1-8 shared builder) ──────────────────────

Deno.test("founderProfileGateReason gate order and resume kill-switch", () => {
  const gate = (hasPitchVideo: boolean, hasResume: boolean, requireResume: boolean) =>
    founderProfileGateReason({ hasPitchVideo, hasResume, requireResume });
  // Video gate always comes first.
  assertEquals(gate(false, false, true), "pitch_video_required");
  assertEquals(gate(false, true, true), "pitch_video_required");
  // Resume gate only when the config flag requires it.
  assertEquals(gate(true, false, true), "resume_required");
  assertEquals(gate(true, false, false), null);
  // Fully equipped candidate passes.
  assertEquals(gate(true, true, true), null);
});

Deno.test("buildJobEmbeddingText tags quality by description presence", () => {
  const full = buildJobEmbeddingText({
    title: "Founding Engineer",
    job_function: "engineering",
    company_name: "Acme",
    company_stage: "seed",
    compensation_min_annual: 150000,
    compensation_max_annual: 200000,
    description: "Build the first product.",
  });
  assertEquals(full.quality, "full");
  assertEquals(full.text.includes("Founding Engineer"), true);
  assertEquals(full.text.includes("Build the first product."), true);

  const sparse = buildJobEmbeddingText({
    title: "Ops Lead",
    job_function: null,
    company_name: null,
    description: "   ",
  });
  assertEquals(sparse.quality, "title_only");
  assertEquals(sparse.text, "Ops Lead");
});

Deno.test("buildResumeEmbeddingText composes sections and skips empties", () => {
  const text = buildResumeEmbeddingText({
    current_title: "SWE Intern",
    current_company: "Stripe",
    years_experience: "1",
    employers: [{ company: "Stripe", title: "SWE Intern" }, { company: "", title: "" }],
    education: [{ school: "UC Berkeley", degree: "BS", field_of_study: "CS" }],
    skills: ["Swift", " ", "Go"],
  });
  assertEquals(text.includes("current: SWE Intern at Stripe"), true);
  assertEquals(text.includes("experience: SWE Intern at Stripe"), true);
  assertEquals(text.includes("education: BS CS UC Berkeley"), true);
  assertEquals(text.includes("skills: Swift, Go"), true);
  assertEquals(buildResumeEmbeddingText({}), "");
});

Deno.test("mapSimilarityToScore clamps and maps through floor/ceiling", () => {
  assertEquals(mapSimilarityToScore(0.2, 0.2, 0.75), 0);
  assertEquals(mapSimilarityToScore(0.75, 0.2, 0.75), 100);
  assertEquals(mapSimilarityToScore(0.475, 0.2, 0.75), 50);
  assertEquals(mapSimilarityToScore(0.1, 0.2, 0.75), 0);
  assertEquals(mapSimilarityToScore(0.9, 0.2, 0.75), 100);
  assertEquals(mapSimilarityToScore(0.5, 0.75, 0.2), 0);
});

Deno.test("pitchSubject is name-only — no credential hook (copy v6)", () => {
  assertEquals(
    pitchSubject({ candidateName: "Sam", jobTitle: "iOS Engineer" }),
    "Applicant for your iOS Engineer: Sam",
  );
});

Deno.test("buildPitchEmailContent renders facts, escapes HTML, and reflects attachments", () => {
  const content = buildPitchEmailContent({
    to: "founder@acme.io",
    recipientFirstName: "Jane",
    candidateName: "Sam <script>",
    candidateEmail: "sam@x.io",
    headline: "CS @ Berkeley",
    jobTitle: "Founding Engineer",
    companyName: "Acme <&> Co",
    note: "I love your product",
    facts: {
      years_experience: "2",
      employers: [{ company: "Stripe", title: "SWE Intern", start_date: "2025-06", is_current: true }],
      education: [{ school: "UC Berkeley", degree: "BS", field_of_study: "CS", graduation_year: "2026" }],
      skills: ["Swift", "Go", ""],
    },
    compensationRange: "$150k+",
    linkedInURL: "https://in/sam",
    videoAttached: true,
    resumeAttached: true,
  });
  assertEquals(content.text.includes("Hi Jane,"), true);
  assertEquals(content.text.includes("SWE Intern · Stripe (2025-06 – now)"), true);
  assertEquals(content.text.includes("Education: BS CS UC Berkeley (2026)"), true);
  assertEquals(content.text.includes("along with their resume"), true);
  // Copy v5 (2026-07-30): no skills list, no quoted note, no reply line.
  assertEquals(content.text.includes("Skills:"), false);
  assertEquals(content.text.includes("I love your product"), false);
  assertEquals(content.text.includes("Reply to this email"), false);
  // Copy v6 (2026-07-30): subject is name-only, one intro line for both
  // paths, new watch line + footer.
  assertEquals(content.subject, "Applicant for your Founding Engineer: Sam <script>");
  assertEquals(content.text.includes("I have an applicant for your Founding Engineer role"), true);
  assertEquals(content.text.includes("who picked out"), false);
  assertEquals(content.text.includes("Two minutes and you'll know if you want to meet them."), true);
  assertEquals(content.text.includes("scout22 — applications come with a video intro, so you meet the person, not just the resume."), true);
  assertEquals(content.html.includes("<script>"), false);
  assertEquals(content.html.includes("Sam &lt;script&gt;"), true);
});

Deno.test("buildPitchEmailContent falls back to links when not attached", () => {
  const content = buildPitchEmailContent({
    to: "jobs@acme.io",
    candidateName: "Sam",
    jobTitle: "PM",
    companyName: "Acme",
    videoAttached: false,
    resumeAttached: false,
    pitchVideoURL: "https://cdn/video.mp4",
    resumeSignedURL: "https://signed/resume.pdf",
  });
  assertEquals(content.text.includes("attached"), false);
  assertEquals(content.text.includes("Watch their video intro: https://cdn/video.mp4"), true);
  assertEquals(content.text.includes("Resume: https://signed/resume.pdf"), true);
  assertEquals(content.text.includes("Hi,"), true);
});

// The video went optional on 2026-08-22, so a resume-only application is a
// real state now: the footer must not claim a video intro that isn't there.
Deno.test("buildPitchEmailContent drops the video claim when there is no video", () => {
  const content = buildPitchEmailContent({
    to: "jobs@acme.io",
    candidateName: "Sam",
    jobTitle: "PM",
    companyName: "Acme",
    videoAttached: false,
    resumeAttached: true,
  });
  assertEquals(content.text.includes("video intro"), false);
  assertEquals(content.text.includes("scout22 — meet the person, not just the resume."), true);
  assertEquals(content.text.includes("Their resume is attached."), true);
});

Deno.test("attachmentFilename sanitizes names and extensions", () => {
  assertEquals(attachmentFilename("Wendy Shi", "Resume", "me/resume final.pdf", "pdf"), "Wendy_Shi_Resume.pdf");
  assertEquals(
    attachmentFilename("Sam", "Pitch", "https://cdn/videos/a/17-clip.MP4?token=x", "mp4"),
    "Sam_Pitch.mp4",
  );
  assertEquals(attachmentFilename("é!", "Pitch", "no-extension", "mp4"), "e_Pitch.mp4");
  assertEquals(attachmentFilename("", "Resume", "x.pdf", "pdf"), "Candidate_Resume.pdf");
});

Deno.test("classifyTitle v2 recovers previously unmapped titles", () => {
  assertEquals(classifyTitle("Forward Deployed Engineer"), "engineering");
  assertEquals(classifyTitle("Engineering Manager"), "engineering");
  assertEquals(classifyTitle("Web Developer"), "engineering");
  assertEquals(classifyTitle("Senior Accountant"), "finance");
  assertEquals(classifyTitle("Solutions Architect"), "support");
  assertEquals(classifyTitle("Solutions Consultant 2"), "support");
  assertEquals(classifyTitle("Account Development Representative I - DACH"), "sales");
  assertEquals(classifyTitle("Solar Appointment Setter"), "sales");
  assertEquals(classifyTitle("Research Scientist II"), "science");
  // Specific team rules still beat the generic engineer catch-all.
  assertEquals(classifyTitle("Sales Engineer"), "sales");
  assertEquals(classifyTitle("Solutions Engineer"), "support");
  // Non-startup-function roles stay unclassified (product decision pending).
  assertEquals(classifyTitle("Heavy Equipment CDL Driver"), null);
  assertEquals(classifyTitle("Stylist (Retail) (Part-time)"), null);
});

Deno.test("classifyTitle v3: program_management and clinical buckets", () => {
  assertEquals(classifyTitle("Program Manager"), "program_management");
  assertEquals(classifyTitle("Technical Program Manager"), "program_management");
  assertEquals(classifyTitle("Senior Project Manager"), "program_management");
  assertEquals(classifyTitle("Marketing Project Manager"), "program_management");
  assertEquals(classifyTitle("Product Manager"), "product");
  assertEquals(classifyTitle("Nurse Practitioner"), "clinical");
  assertEquals(classifyTitle("Registered Behavior Technician (RBT)"), "clinical");
  assertEquals(classifyTitle("Telehealth Endocrinologist"), "clinical");
  assertEquals(classifyTitle("Genetic Counselor"), "clinical");
  assertEquals(classifyTitle("General Counsel"), "legal");
  assertEquals(classifyTitle("Technical Architect"), "engineering");
  assertEquals(classifyTitle("Accounts Payable Specialist"), "finance");
  assertEquals(classifyTitle("Contracts Manager"), "legal");
  assertEquals(classifyTitle("Engagement Manager"), "support");
  assertEquals(classifyTitle("AI Deployment Strategist"), "support");
});

Deno.test("classifyTitle v4: product wins over tech keywords, production is ops", () => {
  // Product runs first — tech-flavored PM titles no longer leak to engineering.
  assertEquals(classifyTitle("Product Manager - Software"), "product");
  assertEquals(classifyTitle("Senior Software Product Manager"), "product");
  assertEquals(classifyTitle("Staff Product Manager, Infrastructure Platform"), "product");
  // Senior product-org titles now match.
  assertEquals(classifyTitle("Director of Product Management, Tableau AI"), "product");
  assertEquals(classifyTitle("VP of Product"), "product");
  assertEquals(classifyTitle("Director of Product, AI"), "product");
  assertEquals(classifyTitle("Chief Product Officer"), "product");
  assertEquals(classifyTitle("Head of Product, Regulatory Finance"), "product");
  // PMM/product design stay with their own teams via the exclusion.
  assertEquals(classifyTitle("Director of Product Marketing"), "marketing");
  assertEquals(classifyTitle("Product Marketing Manager"), "marketing");
  assertEquals(classifyTitle("Product Designer"), "design");
  // "ProductION" is manufacturing ops, not product (the old \b-less bug).
  assertEquals(classifyTitle("Head of Production, Missiles"), "operations");
  assertEquals(classifyTitle("2nd Shift Production Lead"), "operations");
  assertEquals(classifyTitle("Production Program Manager"), "program_management");
  // No PM-term → the engineering rules still claim these.
  assertEquals(classifyTitle("Product Security Engineer"), "engineering");
});

// EEO / protected-class answers must never reach application_fields or
// candidate_field_history: storing them makes those rows GDPR Art. 9
// special-category data and breaks EEO segregation. The client blocks
// capture; this is the server-side backstop.
Deno.test("isSensitiveLabel blocks EEO and protected-class labels", () => {
  for (
    const label of [
      "Race",
      "Race/Ethnicity",
      "Ethnicity",
      "Disability Status",
      "Do you have a disability?",
      "Veteran Status",
      "Protected Veteran Status",
      "Gender",
      "Sex",
      "Sexual Orientation",
      "Religion",
      "Political affiliation",
      "Trade union membership",
      "Genetic information",
      "Biometric data",
    ]
  ) {
    assertEquals(isSensitiveLabel(label), true, `${label} must be blocked`);
  }
});

// Word boundaries keep ordinary application fields storable — a denylist
// that ate "Essex" or "embrace" would silently break autofill.
Deno.test("isSensitiveLabel leaves ordinary labels alone", () => {
  for (
    const label of [
      "First Name",
      "Email",
      "Phone",
      "County (e.g. Essex)",
      "Why do you embrace our mission?",
      "Field of Study",
      "Work Authorization",
      "Desired Salary",
      "Pronouns",
      "",
      "   ",
    ]
  ) {
    assertEquals(isSensitiveLabel(label), false, `${label} should be storable`);
  }
});

// The canonical keys for gender/race/veteran/disability are gone, so a
// stray EEO label can no longer be promoted into the prefill cache.
Deno.test("matchCanonical no longer canonicalizes EEO labels", () => {
  assertEquals(matchCanonical("Gender"), null);
  assertEquals(matchCanonical("Race/Ethnicity"), null);
  assertEquals(matchCanonical("Veteran Status"), null);
  assertEquals(matchCanonical("Disability Status"), null);
  // Ordinary canonicalization still works.
  assertEquals(matchCanonical("First Name"), "first_name");
  assertEquals(matchCanonical("Pronouns"), "pronouns");
});

// ── Work at a Startup adapter parsing ────────────────────────────────
// Fixtures mirror the real page shape: WaaS renders its server props into
// a data-page attribute with HTML-escaped JSON.

Deno.test("extractPageProps decodes the WaaS data-page blob", () => {
  const html = `<div id="app" data-page="{&quot;props&quot;:{&quot;job&quot;:{&quot;id&quot;:72052,` +
    `&quot;title&quot;:&quot;Senior Engineer, Payments &amp; Risk&quot;,` +
    `&quot;descriptionHtml&quot;:&quot;&lt;p&gt;Build it&lt;/p&gt;&quot;}}}"></div>`;
  const props = extractPageProps(html);
  const job = props?.job as { id: number; title: string; descriptionHtml: string };
  assertEquals(job.id, 72052);
  assertEquals(job.title, "Senior Engineer, Payments & Risk");
  assertEquals(job.descriptionHtml, "<p>Build it</p>");
});

Deno.test("extractPageProps returns null on missing or malformed blobs", () => {
  assertEquals(extractPageProps("<html><body>login wall</body></html>"), null);
  assertEquals(extractPageProps(`<div data-page="{not json}"></div>`), null);
});

Deno.test("decodeHtmlEntities decodes ampersands last", () => {
  // &amp;quot; must survive as the literal text &quot;, not become a quote —
  // decoding & first would corrupt it and break JSON.parse.
  assertEquals(decodeHtmlEntities("&amp;quot;"), "&quot;");
  assertEquals(decodeHtmlEntities("R&amp;D &lt;team&gt;"), "R&D <team>");
});

Deno.test("htmlToText flattens JD markup into embedding-ready text", () => {
  const html = "<p>We are hiring.</p><ul><li>Rust</li><li>Postgres</li></ul>" +
    "<p>Comp:&nbsp;$150K&amp;up</p>";
  assertEquals(
    htmlToText(html),
    "We are hiring.\nRust\nPostgres\nComp: $150K&up",
  );
  assertEquals(htmlToText("<p></p>"), "");
});


Deno.test("sanitizeCompensation drops the PermitFlow-shaped annual typo", () => {
  // Getro reported 13000/16000 cents = $130/$160 a year; the employer meant
  // $130K/$160K. Publishing it rendered "$0k–$0k" on the carousel.
  assertEquals(
    sanitizeCompensation({ min_annual: 130, max_annual: 160, min_hourly: null, max_hourly: null }),
    { min_annual: null, max_annual: null, min_hourly: null, max_hourly: null },
  );
});

Deno.test("sanitizeCompensation keeps real annual ranges and open-ended ends", () => {
  assertEquals(
    sanitizeCompensation({ min_annual: 130000, max_annual: 160000, min_hourly: null, max_hourly: null }),
    { min_annual: 130000, max_annual: 160000, min_hourly: null, max_hourly: null },
  );
  // "Up to $160,000" — a null endpoint is legitimate, not a defect.
  assertEquals(
    sanitizeCompensation({ min_annual: null, max_annual: 160000, min_hourly: null, max_hourly: null }),
    { min_annual: null, max_annual: 160000, min_hourly: null, max_hourly: null },
  );
});

Deno.test("sanitizeCompensation poisons the whole pair when one end is bad", () => {
  // A zero min alongside a plausible max: one typo means the range is
  // untrustworthy, so the survivor is dropped rather than published alone.
  assertEquals(
    sanitizeCompensation({ min_annual: 0, max_annual: 160000, min_hourly: null, max_hourly: null }),
    { min_annual: null, max_annual: null, min_hourly: null, max_hourly: null },
  );
});

Deno.test("sanitizeCompensation rejects inverted ranges", () => {
  assertEquals(
    sanitizeCompensation({ min_annual: 200000, max_annual: 100000, min_hourly: null, max_hourly: null }),
    { min_annual: null, max_annual: null, min_hourly: null, max_hourly: null },
  );
});

Deno.test("sanitizeCompensation judges hourly separately from annual", () => {
  assertEquals(
    sanitizeCompensation({ min_annual: null, max_annual: null, min_hourly: 60, max_hourly: 80 }),
    { min_annual: null, max_annual: null, min_hourly: 60, max_hourly: 80 },
  );
  // $0.50/hr is a unit error, not an offer.
  assertEquals(
    sanitizeCompensation({ min_annual: null, max_annual: null, min_hourly: 0.5, max_hourly: 80 }),
    { min_annual: null, max_annual: null, min_hourly: null, max_hourly: null },
  );
});

Deno.test("parseCompensation still reads the common ATS shapes", () => {
  assertEquals(parseCompensation("$120,000 - $160,000"), {
    min_annual: 120000, max_annual: 160000, min_hourly: null, max_hourly: null,
  });
  assertEquals(parseCompensation("USD 120K - 160K"), {
    min_annual: 120000, max_annual: 160000, min_hourly: null, max_hourly: null,
  });
  assertEquals(parseCompensation("$60–$80 per hour"), {
    min_annual: null, max_annual: null, min_hourly: 60, max_hourly: 80,
  });
  // Single hourly figure: sixty dollars an hour, not sixty thousand.
  assertEquals(parseCompensation("$60/hour"), {
    min_annual: null, max_annual: null, min_hourly: 60, max_hourly: 60,
  });
  // Non-USD keeps compensation_text upstream but yields no structured range.
  assertEquals(parseCompensation("€90,000 - €110,000"), {
    min_annual: null, max_annual: null, min_hourly: null, max_hourly: null,
  });
});

// --- ATS classification + enrichment targeting -----------------------------

Deno.test("classifyApplyURL: EU-resident Greenhouse and Lever boards", () => {
  // Before: the `.greenhouse.io` subdomain branch read the token as
  // "job-boards.eu" and missed the id entirely.
  assertEquals(
    classifyApplyURL("https://job-boards.eu.greenhouse.io/audiomob/jobs/4928163101"),
    { ats_type: "greenhouse", ats_token: "audiomob", ats_external_id: "4928163101" },
  );
  // Before: unmatched host → ats_type null → never enrichable.
  assertEquals(
    classifyApplyURL("https://jobs.eu.lever.co/markt-pilot/4bbf64f9-20fd"),
    { ats_type: "lever", ats_token: "markt-pilot", ats_external_id: "4bbf64f9-20fd" },
  );
});

Deno.test("classifyApplyURL: percent-encoded board token is decoded once", () => {
  // Adapters encodeURIComponent the token; storing the raw segment yielded
  // "Hippocratic%2520AI" and a 404 from every ATS.
  const url = "https://jobs.ashbyhq.com/Hippocratic%20AI/99b1c932-91cf-445b-b37e-c21e14b41bb5";
  const resolved = classifyApplyURL(url);
  assertEquals(resolved?.ats_token, "Hippocratic AI");
  // The id is passed through untouched — it feeds dedup_key, and rewriting it
  // would strand every already-ingested row.
  assertEquals(resolved?.ats_external_id, "99b1c932-91cf-445b-b37e-c21e14b41bb5");
  assertEquals(
    computeDedupKey(url, resolved),
    "ashby:99b1c932-91cf-445b-b37e-c21e14b41bb5",
  );
});

function pending(id: string, ats_type: NormalizedJob["source_ats"], apply_url: string | null) {
  return { id, ats_type, ats_external_id: `ext-${id}`, apply_url };
}

Deno.test("groupPendingJobs: job coordinates beat a stale company row", () => {
  // Applied Intuition: company row still says greenhouse, every live job is
  // on ashby. The old company-driven filter dropped all 239.
  const { groups, unresolved } = groupPendingJobs(
    [
      pending("a", "ashby", "https://jobs.ashbyhq.com/applied/01e37ae0"),
      pending("b", "ashby", "https://jobs.ashbyhq.com/applied/b0f5bc4d"),
    ],
    { ats_type: "greenhouse", ats_token: "appliedintuition" },
  );
  assertEquals(unresolved.length, 0);
  assertEquals(groups.length, 1);
  assertEquals(groups[0].ats_type, "ashby");
  assertEquals(groups[0].ats_token, "applied");
  assertEquals(groups[0].jobs.length, 2);
});

Deno.test("groupPendingJobs: splits boards, largest first, null company row ok", () => {
  const { groups } = groupPendingJobs(
    [
      pending("a", "lever", "https://jobs.lever.co/small/1"),
      pending("b", "greenhouse", "https://boards.greenhouse.io/big/jobs/2"),
      pending("c", "greenhouse", "https://boards.greenhouse.io/big/jobs/3"),
    ],
    { ats_type: null, ats_token: null },
  );
  assertEquals(groups.map((g) => [g.ats_token, g.jobs.length]), [["big", 2], ["small", 1]]);
});

Deno.test("groupPendingJobs: falls back to the company token, decoding it", () => {
  // apply_url no longer classifies (company moved to a custom careers page),
  // but the company row still names the right board.
  const { groups, unresolved } = groupPendingJobs(
    [pending("a", "ashby", "https://careers.example.com/roles/42")],
    { ats_type: "ashby", ats_token: "Redesign%20Health" },
  );
  assertEquals(unresolved.length, 0);
  assertEquals(groups[0].ats_token, "Redesign Health");
});

Deno.test("groupPendingJobs: unresolvable when both sources disagree or are empty", () => {
  const { groups, unresolved } = groupPendingJobs(
    [pending("a", "lever", "https://careers.example.com/roles/42"), pending("b", "lever", null)],
    { ats_type: "greenhouse", ats_token: "somewhere" },
  );
  assertEquals(groups.length, 0);
  assertEquals(unresolved.map((j) => j.id), ["a", "b"]);
});

function normalized(external_id: string, listing_url: string | null): NormalizedJob {
  return {
    source_ats: "recruitee",
    external_id,
    title: "Engineer",
    listing_url,
    apply_url: listing_url,
    apply_flow: "ats_form",
    compensation_text: null,
    compensation: { min_annual: null, max_annual: null, min_hourly: null, max_hourly: null },
    location: null,
    category: null,
    employment_type: null,
    posted_at: null,
    description: "JD body",
    description_raw: null,
    contact_email_on_posting: null,
    content_hash: "hash",
  };
}

Deno.test("buildMatchIndex: Recruitee slug aliases the numeric offer id", () => {
  // The URL exposes /o/{slug} (which is what ats_external_id stores) while the
  // API returns a numeric id — every live Recruitee job missed on this.
  const index = buildMatchIndex([
    normalized("2145678", "https://matera.recruitee.com/o/senior-backend-engineer"),
  ]);
  assertEquals(index.get("2145678")?.description, "JD body");
  assertEquals(index.get("senior-backend-engineer")?.description, "JD body");
  assertEquals(index.get("unknown-slug"), undefined);
});

Deno.test("buildMatchIndex: a real API id is never displaced by an alias", () => {
  // Job two's slug collides with job one's API id; the API id must win.
  const index = buildMatchIndex([
    normalized("shared", "https://acme.recruitee.com/o/first"),
    normalized("second", "https://acme.recruitee.com/o/shared"),
  ]);
  assertEquals(index.get("shared")?.external_id, "shared");
  assertEquals(index.get("first")?.external_id, "shared");
});

// --- ATS vanished-posting detection (enrich-descriptions expiry) ---

const HOUR = 60 * 60 * 1000;
const NOW = Date.parse("2026-08-09T12:00:00Z");
const GRACE = 48 * HOUR;
const AGED = new Date(NOW - 30 * 24 * HOUR).toISOString();

Deno.test("selectVanishedJobIds picks only aged jobs absent from the board", () => {
  const ids = selectVanishedJobIds(
    [
      { id: "gone", ats_external_id: "111", created_at: AGED },
      { id: "live", ats_external_id: "222", created_at: AGED },
    ],
    new Set(["222", "333"]),
    { now: NOW, graceMs: GRACE },
  );
  assertEquals(ids, ["gone"]);
});

// The ingest→enrich race: the VC board can surface a posting before it shows
// up in a cached ATS response, so freshly-created rows are left alone.
Deno.test("selectVanishedJobIds spares jobs inside the grace window", () => {
  const jobs = [
    { id: "fresh", ats_external_id: "111", created_at: new Date(NOW - HOUR).toISOString() },
    { id: "edge", ats_external_id: "222", created_at: new Date(NOW - GRACE).toISOString() },
  ];
  assertEquals(selectVanishedJobIds(jobs, new Set(), { now: NOW, graceMs: GRACE }), ["edge"]);
});

// Fail safe: an unusable created_at means we cannot prove the grace window has
// elapsed, so the posting stays active rather than being hidden.
Deno.test("selectVanishedJobIds keeps jobs with an unusable created_at", () => {
  const jobs = [
    { id: "null-ts", ats_external_id: "111", created_at: null },
    { id: "junk-ts", ats_external_id: "222", created_at: "not a date" },
  ];
  assertEquals(selectVanishedJobIds(jobs, new Set(), { now: NOW, graceMs: GRACE }), []);
});

// A renamed or dead board token returns zero jobs, which must never be read as
// "every posting closed".
Deno.test("feedIsAuthoritative rejects an empty adapter result", () => {
  assertEquals(feedIsAuthoritative(0), false);
  assertEquals(feedIsAuthoritative(1), true);
});

// --- Getro per-job detail (board-sourced descriptions + liveness) ---------

const LONG_JD = "<p>" + "We are hiring a senior engineer to build things. ".repeat(4) + "</p>";

Deno.test("classifyGetroDetail: an open posting with a real JD is written", () => {
  const outcome = classifyGetroDetail({ status: "active", visibility: "visible", description: LONG_JD });
  assertEquals(outcome.kind, "describe");
  if (outcome.kind !== "describe") throw new Error("unreachable");
  assertEquals(outcome.description_raw, LONG_JD);
  // Stored text is stripped of markup, like every other description source.
  assertEquals(outcome.description.includes("<p>"), false);
  assertEquals(outcome.description.startsWith("We are hiring"), true);
});

Deno.test("classifyGetroDetail: closed postings expire and are never described", () => {
  // Each signal alone is enough — a JD present alongside it must not win,
  // or we would make a dead posting visible in the feed.
  for (
    const detail of [
      { status: "active", closed_at: "2026-08-01T00:00:00Z", description: LONG_JD },
      { status: "active", deactivated_at: "2026-08-01T00:00:00Z", description: LONG_JD },
      { status: "active", visibility: "not_visible", description: LONG_JD },
      { status: "deactivated", visibility: "visible", description: LONG_JD },
    ]
  ) {
    assertEquals(classifyGetroDetail(detail).kind, "expire");
  }
});

Deno.test("classifyGetroDetail: a stub description is not a JD", () => {
  assertEquals(
    classifyGetroDetail({ status: "active", description: "<p>Apply on our website.</p>" }).kind,
    "skip",
  );
  assertEquals(classifyGetroDetail({ status: "active", description: null }).kind, "skip");
});

Deno.test("classifyGetroDetail: an unrecognised payload skips rather than expires", () => {
  // If Getro changes its schema, degrade to doing nothing — never to closing
  // jobs we cannot prove are closed.
  assertEquals(classifyGetroDetail({}).kind, "skip");
  assertEquals(classifyGetroDetail({ description: LONG_JD }).kind, "skip");
});

Deno.test("getroJobDetailURL encodes both ids", () => {
  assertEquals(
    getroJobDetailURL("90361272", "8672"),
    "https://api.getro.com/api/v1/jobs/90361272?collection_id=8672",
  );
});

// Résumé headers are typeset in caps, so the parser stores "WENDY SHI" and
// autofill typed it into every form. De-capsing has to be surgical: several
// canonical fields are legitimately uppercase.
Deno.test("normalizeCanonicalValue de-capses names but spares real uppercase", () => {
  assertEquals(normalizeCanonicalValue("first_name", "WENDY"), "Wendy");
  assertEquals(normalizeCanonicalValue("last_name", "SHI"), "Shi");
  assertEquals(normalizeCanonicalValue("full_name", "WENDY B SHI"), "Wendy B Shi");
  assertEquals(normalizeCanonicalValue("city", "NEW YORK"), "New York");
  // Hyphens and apostrophes start new words too.
  assertEquals(normalizeCanonicalValue("last_name", "O'BRIEN-SMITH"), "O'Brien-Smith");
  // Already mixed case is never touched — McDonald must not become Mcdonald.
  assertEquals(normalizeCanonicalValue("last_name", "McDonald"), "McDonald");
  assertEquals(normalizeCanonicalValue("first_name", "Wendy"), "Wendy");
  // Keys that are legitimately uppercase are left alone.
  assertEquals(normalizeCanonicalValue("state", "NY"), "NY");
  assertEquals(normalizeCanonicalValue("highest_degree", "M.S."), "M.S.");
  assertEquals(normalizeCanonicalValue("current_company", "IBM"), "IBM");
  assertEquals(normalizeCanonicalValue("school", "UCLA"), "UCLA");
  // Initials stay as-is: too short to reconstruct meaningfully.
  assertEquals(normalizeCanonicalValue("first_name", "W"), "W");
  assertEquals(normalizeCanonicalValue("email", "WENDY@X.COM"), "WENDY@X.COM");
});

// ---------------------------------------------------------------------------
// S-1 — answer suggestion prompts
// ---------------------------------------------------------------------------

Deno.test("pickMode splits reuse / adapt / generate at the floors", () => {
  assertEquals(pickMode(0.99), "reuse");
  assertEquals(pickMode(REUSE_FLOOR), "reuse");
  // Just under the reuse floor must adapt, not reuse — the whole point of the
  // middle band is that a near-miss question needs rewriting, not verbatim
  // reuse of an answer to a different question.
  assertEquals(pickMode(REUSE_FLOOR - 0.001), "adapt");
  assertEquals(pickMode(ADAPT_FLOOR), "adapt");
  assertEquals(pickMode(ADAPT_FLOOR - 0.001), "generate");
  // No prior answer at all, or a malformed score, means cold generation.
  assertEquals(pickMode(null), "generate");
  assertEquals(pickMode(undefined), "generate");
  assertEquals(pickMode(NaN), "generate");
});

// THE anti-slop invariant. If model output is ever admitted as a voice sample,
// every future draft is shaped by the last draft and the corpus collapses to
// one synthetic voice. Only text the candidate wrote or corrected qualifies.
Deno.test("selectVoiceSamples admits only human and edited rows", () => {
  const long = (n: number) => "x".repeat(n);
  const rows = [
    { id: "1", question_text: "q1", answer: long(200), source: "generated", updated_at: "2026-09-01" },
    { id: "2", question_text: "q2", answer: long(200), source: "human",     updated_at: "2026-08-01" },
    { id: "3", question_text: "q3", answer: long(200), source: "edited",    updated_at: "2026-07-01" },
  ];
  const picked = selectVoiceSamples(rows);
  assertEquals(picked.map((p) => p.id), ["2", "3"]);
});

Deno.test("selectVoiceSamples filters by length, sorts newest first, caps at 3", () => {
  const long = (n: number) => "x".repeat(n);
  const rows = [
    // Too short to carry voice.
    { id: "short", question_text: "q", answer: long(10),   source: "human", updated_at: "2026-09-05" },
    // Too long — would crowd out the resume in the prompt.
    { id: "long",  question_text: "q", answer: long(5000), source: "human", updated_at: "2026-09-04" },
    { id: "a", question_text: "q", answer: long(200), source: "human", updated_at: "2026-09-03" },
    { id: "b", question_text: "q", answer: long(200), source: "human", updated_at: "2026-09-02" },
    { id: "c", question_text: "q", answer: long(200), source: "human", updated_at: "2026-09-01" },
    { id: "d", question_text: "q", answer: long(200), source: "human", updated_at: "2026-08-31" },
  ];
  assertEquals(selectVoiceSamples(rows).map((p) => p.id), ["a", "b", "c"]);
  // The prior answer being adapted is excluded so the model is not handed the
  // same text twice, once as source and once as style.
  assertEquals(selectVoiceSamples(rows, "a").map((p) => p.id), ["b", "c", "d"]);
  // A missing source column means legacy rows captured before S-1, which were
  // all candidate-typed.
  assertEquals(
    selectVoiceSamples([{ id: "z", question_text: "q", answer: long(200), updated_at: "2026-09-01" }])
      .map((p) => p.id),
    ["z"],
  );
});

Deno.test("targetWordCount leaves headroom under a hard char limit", () => {
  assertEquals(targetWordCount(null), 150);
  assertEquals(targetWordCount(0), 150);
  // 1200 chars * 0.9 / 6 chars-per-word
  assertEquals(targetWordCount(1200), 180);
  // Never asks for an unusably short answer.
  assertEquals(targetWordCount(60), 40);
});

Deno.test("enforceCharLimit trims to a sentence boundary, not mid-word", () => {
  const text = "First sentence here. Second sentence here. Third one.";
  assertEquals(enforceCharLimit(text, 1000), text);
  // Cuts back to the last full sentence that fits.
  assertEquals(enforceCharLimit(text, 45), "First sentence here. Second sentence here.");
  // With no sentence boundary in the back half, a hard cut is the only option.
  assertEquals(enforceCharLimit("x".repeat(100), 10), "x".repeat(10));
  assertEquals(enforceCharLimit("  padded  ", 100), "padded");
  assertEquals(enforceCharLimit("anything", null), "anything");
});

Deno.test("truncate marks the cut so the model knows the JD is partial", () => {
  assertEquals(truncate(null, 10), null);
  assertEquals(truncate("short", 10), "short");
  assertEquals(truncate("abcdefghijkl", 5), "abcde\n[truncated]");
});

// ---------------------------------------------------------------------------
// S-2 — resume <-> JD keyword gap
// ---------------------------------------------------------------------------

Deno.test("normalizeText survives the symbols that matter in skill names", () => {
  // Naive punctuation stripping collapses C++ and C# to "c", which then
  // matches any resume containing the letter c as a word.
  assertEquals(normalizeText("C++"), "cplusplus");
  assertEquals(normalizeText("C#"), "csharp");
  assertEquals(normalizeText(".NET"), "dotnet");
  assertEquals(normalizeText("Node.js"), "nodejs");
  assertEquals(normalizeText("React.js"), "reactjs");
  // ".NET" must not fuse into the word before it, or ASP.NET matches nothing.
  assertEquals(normalizeText("ASP.NET"), "asp dotnet");
  assertEquals(normalizeText(".NET"), "dotnet");
  assertEquals(normalizeText("CI/CD"), "ci cd");
  assertEquals(normalizeText("  Machine   Learning  "), "machine learning");
  assertEquals(normalizeText(null), "");
});

// THE false positive that makes these tools untrustworthy: counting "Java" as
// covered because the resume says "JavaScript".
Deno.test("haystackContains matches whole tokens, never substrings", () => {
  const haystack = buildResumeHaystack({ parsedText: "Built services in JavaScript and Go" });
  assertEquals(haystackContains(haystack, "JavaScript"), true);
  assertEquals(haystackContains(haystack, "Java"), false);
  assertEquals(haystackContains(haystack, "Go"), true);
  assertEquals(haystackContains(haystack, "Golang"), false);
});

Deno.test("haystackContains resolves aliases and simple plurals", () => {
  const haystack = buildResumeHaystack({ parsedText: "Postgres, k8s, AWS, and React" });
  assertEquals(haystackContains(haystack, "PostgreSQL"), true);
  assertEquals(haystackContains(haystack, "Kubernetes"), true);
  assertEquals(haystackContains(haystack, "Amazon Web Services"), true);
  assertEquals(haystackContains(haystack, "React.js"), true);
  assertEquals(haystackContains(haystack, "Kafka"), false);
});

Deno.test("buildResumeHaystack falls back to parsed_json when text is absent", () => {
  // Resumes parsed before parsed_text existed. Thin, but not nothing.
  const haystack = buildResumeHaystack({
    parsedText: null,
    parsedJson: {
      current_title: "Data Engineer",
      skills: ["Airflow", "Python"],
      employers: [{ title: "Analyst", company: "Stripe" }],
      education: [{ degree: "BS", field_of_study: "Statistics", school: "UCLA" }],
    },
  });
  assertEquals(haystackContains(haystack, "Airflow"), true);
  assertEquals(haystackContains(haystack, "Data Engineer"), true);
  assertEquals(haystackContains(haystack, "Statistics"), true);
  assertEquals(haystackContains(haystack, "Kubernetes"), false);
});

Deno.test("diffKeywords weights required above preferred", () => {
  const resume = { parsedText: "Python and SQL" };
  const gap = diffKeywords([
    { term: "Python", importance: "required" },
    { term: "SQL", importance: "required" },
    { term: "Rust", importance: "preferred" },
  ], resume);
  // 2+2 earned of 2+2+1 total.
  assertEquals(gap.coverage, 80);
  assertEquals(gap.requiredTotal, 2);
  assertEquals(gap.requiredCovered, 2);
  assertEquals(gap.missing.map((m) => m.term), ["Rust"]);

  // Missing a required term costs far more than missing a preferred one.
  const worse = diffKeywords([
    { term: "Python", importance: "required" },
    { term: "Rust", importance: "required" },
  ], resume);
  assertEquals(worse.coverage, 50);
});

Deno.test("diffKeywords dedupes terms that differ only in casing", () => {
  const gap = diffKeywords([
    { term: "Python", importance: "required" },
    { term: "python", importance: "required" },
  ], { parsedText: "Python" });
  assertEquals(gap.covered.length, 1);
  assertEquals(gap.coverage, 100);
});

Deno.test("diffKeywords reports 0 rather than dividing by zero", () => {
  const gap = diffKeywords([], { parsedText: "anything" });
  assertEquals(gap.coverage, 0);
  assertEquals(gap.covered.length, 0);
  assertEquals(gap.missing.length, 0);
});

Deno.test("rankMissing puts required gaps before preferred ones", () => {
  const ranked = rankMissing([
    { term: "Rust", importance: "preferred", covered: false },
    { term: "Kafka", importance: "required", covered: false },
    { term: "Airflow", importance: "required", covered: false },
  ]);
  assertEquals(ranked.map((r) => r.term), ["Airflow", "Kafka", "Rust"]);
});

// ---------------------------------------------------------------------------
// S-3 — cover letters
// ---------------------------------------------------------------------------

// The one failure this feature exists to avoid is a letter that could have
// been sent to anybody. Both tells are cheap to check and worth refusing on.
Deno.test("coverLetterLooksGeneric rejects the banned openers", () => {
  assertEquals(
    coverLetterLooksGeneric("I am writing to apply for the role at Ramp.", "Ramp"),
    true,
  );
  assertEquals(
    coverLetterLooksGeneric("To whom it may concern, Ramp is great.", "Ramp"),
    true,
  );
  assertEquals(
    coverLetterLooksGeneric("I am excited to apply to Ramp.", "Ramp"),
    true,
  );
  assertEquals(coverLetterLooksGeneric("", "Ramp"), true);
});

Deno.test("coverLetterLooksGeneric requires the company to be named", () => {
  // Three paragraphs that never say who they are addressed to.
  assertEquals(
    coverLetterLooksGeneric("Your payments platform caught my eye.", "Ramp"),
    true,
  );
  assertEquals(
    coverLetterLooksGeneric("Ramp's spend controls caught my eye.", "Ramp"),
    false,
  );
  // Case-insensitive, so a letter writing "RAMP" still passes.
  assertEquals(
    coverLetterLooksGeneric("RAMP's spend controls caught my eye.", "Ramp"),
    false,
  );
  // A very short or absent company name would match any text, so the check is
  // skipped rather than allowed to pass everything silently.
  assertEquals(coverLetterLooksGeneric("Some real opening line.", null), false);
  assertEquals(coverLetterLooksGeneric("Some real opening line.", "X"), false);
});

// ---------------------------------------------------------------------------
// S-4 — resume tailoring
// ---------------------------------------------------------------------------

Deno.test("bulletKey is stable across whitespace and casing", () => {
  const a = bulletKey("Built the ledger service");
  assertEquals(bulletKey("built  the   ledger service"), a);
  assertEquals(bulletKey("  Built the ledger service  "), a);
  assertEquals(bulletKey("BUILT THE LEDGER SERVICE"), a);
  // Different sentences must not collide into one override.
  assertEquals(bulletKey("Built the billing service") === a, false);
});

Deno.test("applyOverrides lets the candidate's own words win", () => {
  const resume = {
    employment: [{
      company: "Acme",
      title: "SWE",
      bullets: [
        { key: "k1", original: "Built X", tailored: "Spearheaded X" },
        { key: "k2", original: "Built Y", tailored: "Leveraged Y" },
      ],
    }],
  };
  const out = applyOverrides(resume, { k1: "Built X, which cut latency 40%" });
  assertEquals(out.employment[0].bullets[0].tailored, "Built X, which cut latency 40%");
  // Untouched bullets keep the model's rewrite.
  assertEquals(out.employment[0].bullets[1].tailored, "Leveraged Y");
  // A blank override is not an override.
  assertEquals(applyOverrides(resume, { k1: "   " }).employment[0].bullets[0].tailored, "Spearheaded X");
  assertEquals(applyOverrides(resume, null).employment[0].bullets[0].tailored, "Spearheaded X");
});

// This is the check that stands between the model and a document someone
// sends to an employer under their own name.
Deno.test("checkFabrication passes an honest rewrite", () => {
  const source = [{ company: "Acme", title: "SWE", bullets: ["Built the ledger"] }];
  const report = checkFabrication({
    employment: [{
      company: "Acme",
      title: "SWE",
      bullets: [{
        key: bulletKey("Built the ledger"),
        original: "Built the ledger",
        tailored: "Built the ledger service in Go",
      }],
    }],
  }, source);
  assertEquals(report.ok, true);
  assertEquals(report.inventedBullets.length, 0);
});

Deno.test("checkFabrication catches an invented employer", () => {
  const source = [{ company: "Acme", title: "SWE", bullets: ["Built the ledger"] }];
  const report = checkFabrication({
    employment: [{ company: "Google", title: "SWE", bullets: [] }],
  }, source);
  assertEquals(report.ok, false);
  assertEquals(report.addedEmployers, ["Google"]);
});

Deno.test("checkFabrication catches an inflated title", () => {
  const source = [{ company: "Acme", title: "Engineer", bullets: ["Built the ledger"] }];
  const report = checkFabrication({
    employment: [{ company: "Acme", title: "Senior Staff Engineer", bullets: [] }],
  }, source);
  assertEquals(report.ok, false);
  assertEquals(report.changedTitles.length, 1);
});

Deno.test("checkFabrication catches an invented bullet, even with a stolen key", () => {
  const source = [{ company: "Acme", title: "SWE", bullets: ["Built the ledger"] }];
  const realKey = bulletKey("Built the ledger");

  // A bullet whose `original` was never in the resume.
  const invented = checkFabrication({
    employment: [{
      company: "Acme",
      title: "SWE",
      bullets: [{
        key: bulletKey("Led a team of 12"),
        original: "Led a team of 12",
        tailored: "Led a team of 12 engineers",
      }],
    }],
  }, source);
  assertEquals(invented.ok, false);
  assertEquals(invented.inventedBullets.length, 1);

  // And one that copies a REAL key onto fabricated text: the key must match
  // the original it claims to hash, or it proves nothing.
  const stolen = checkFabrication({
    employment: [{
      company: "Acme",
      title: "SWE",
      bullets: [{
        key: realKey,
        original: "Led a team of 12",
        tailored: "Led a team of 12 engineers",
      }],
    }],
  }, source);
  assertEquals(stolen.ok, false);
});

Deno.test("checkFabrication allows dropping a role but reports it", () => {
  const source = [
    { company: "Acme", title: "SWE", bullets: ["Built the ledger"] },
    { company: "Oldco", title: "Intern", bullets: ["Made coffee"] },
  ];
  const report = checkFabrication({
    employment: [{
      company: "Acme",
      title: "SWE",
      bullets: [{
        key: bulletKey("Built the ledger"),
        original: "Built the ledger",
        tailored: "Built the ledger",
      }],
    }],
  }, source);
  // Omitting an irrelevant job is a legitimate tailoring move, not fabrication.
  assertEquals(report.ok, true);
  assertEquals(report.droppedEmployers, ["oldco"]);
});

// The override loop is the reason S-4 is worth having: an edit made once must
// survive every later tailoring. These pin the two halves of that contract.
Deno.test("an override keyed off the original survives a rewrite", () => {
  const original = "Built the ledger";
  const key = bulletKey(original);

  // First tailoring: the model rephrases, the candidate corrects it.
  const first = applyOverrides({
    employment: [{
      company: "Acme",
      title: "SWE",
      bullets: [{ key, original, tailored: "Spearheaded ledger initiatives" }],
    }],
  }, { [key]: "Built the ledger, cutting settlement time in half" });
  assertEquals(
    first.employment[0].bullets[0].tailored,
    "Built the ledger, cutting settlement time in half",
  );

  // A LATER tailoring for a different job phrases it differently again. The
  // key comes from the same source sentence, so the correction still lands —
  // this is what stops the candidate re-fixing the same line per application.
  const second = applyOverrides({
    employment: [{
      company: "Acme",
      title: "SWE",
      bullets: [{ key, original, tailored: "Leveraged ledger systems" }],
    }],
  }, { [key]: "Built the ledger, cutting settlement time in half" });
  assertEquals(
    second.employment[0].bullets[0].tailored,
    "Built the ledger, cutting settlement time in half",
  );
});

Deno.test("an override does not smuggle a claim past the fabrication check", () => {
  const original = "Built the ledger";
  const source = [{ company: "Acme", title: "SWE", bullets: [original] }];
  const tailored = {
    employment: [{
      company: "Acme",
      title: "SWE",
      bullets: [{ key: bulletKey(original), original, tailored: "Built the ledger in Go" }],
    }],
  };
  // checkFabrication runs on the model's output, BEFORE overrides are applied,
  // so a refusal cannot be dodged by having an override in place.
  assertEquals(checkFabrication(tailored, source).ok, true);
  const overridden = applyOverrides(tailored, { [bulletKey(original)]: "Ran the whole company" });
  // The override is the candidate's own words about their own history, so it
  // is not policed — but it is still traceable to a real source bullet.
  assertEquals(overridden.employment[0].bullets[0].original, original);
});

// ---------------------------------------------------------------------------
// C-1 — harvesting ATS coordinates from a company's own job URLs
// ---------------------------------------------------------------------------

Deno.test("harvestFromApplyURLs resolves a company posting on one board", () => {
  // Real stragglers found in production: companies that came through a VC
  // board with no ATS hint, whose jobs carried the answer all along.
  const verdict = harvestFromApplyURLs([
    "https://boards.greenhouse.io/coalition/jobs/4665925005",
    "https://boards.greenhouse.io/coalition/jobs/4665925006",
  ]);
  assertEquals(verdict.kind, "resolved");
  if (verdict.kind === "resolved") {
    assertEquals(verdict.resolution.ats_type, "greenhouse");
    assertEquals(verdict.resolution.ats_token, "coalition");
  }
});

Deno.test("harvestFromApplyURLs handles the EU shards and dotted tokens", () => {
  const lever = harvestFromApplyURLs([
    "https://jobs.eu.lever.co/silverfin/2a14dba0-4da4-40d7-bcf4-59b88db565c9",
  ]);
  assertEquals(lever.kind, "resolved");
  if (lever.kind === "resolved") assertEquals(lever.resolution.ats_token, "silverfin");

  // Ashby tokens are sometimes a full domain. Stripping the dot would query a
  // board that does not exist.
  const ashby = harvestFromApplyURLs([
    "https://jobs.ashbyhq.com/datasnipper.com/02a36783-68f6-4499-b7bb-a79ff41f05e6",
  ]);
  assertEquals(ashby.kind, "resolved");
  if (ashby.kind === "resolved") assertEquals(ashby.resolution.ats_token, "datasnipper.com");
});

Deno.test("harvestFromApplyURLs ignores tracking params on the same board", () => {
  // Observed in production: a Lever URL decorated with a Sequoia source param.
  const verdict = harvestFromApplyURLs([
    "https://jobs.eu.lever.co/xentral/464c91df?lever-source%5B%5D=jobs.sequoiacap.com",
    "https://jobs.eu.lever.co/xentral/aaaaaaaa",
  ]);
  assertEquals(verdict.kind, "resolved");
  if (verdict.kind === "resolved") assertEquals(verdict.resolution.ats_token, "xentral");
});

// THE failure that matters. Writing a token a company does not own points the
// per-company crawler at someone else's board, and every posting it returns is
// attributed to the wrong employer.
Deno.test("harvestFromApplyURLs refuses to guess when boards disagree", () => {
  assertEquals(
    harvestFromApplyURLs([
      "https://boards.greenhouse.io/acme/jobs/1",
      "https://jobs.lever.co/othercorp/abc",
    ]).kind,
    "ambiguous",
  );
  // Same provider, different token, is just as wrong.
  assertEquals(
    harvestFromApplyURLs([
      "https://boards.greenhouse.io/acme/jobs/1",
      "https://boards.greenhouse.io/acquired-sub/jobs/2",
    ]).kind,
    "ambiguous",
  );
});

Deno.test("harvestFromApplyURLs reports unresolved rather than resolving to nothing", () => {
  assertEquals(harvestFromApplyURLs([]).kind, "unresolved");
  assertEquals(harvestFromApplyURLs([null, undefined, ""]).kind, "unresolved");
  // Bespoke careers sites and adapter-less ATS are unresolved, NOT ambiguous —
  // the caller counts those separately and they are not a data problem.
  assertEquals(
    harvestFromApplyURLs([
      "https://careers.acme.com/jobs/123",
      "https://acme.wd5.myworkdayjobs.com/en-US/careers/job/123",
    ]).kind,
    "unresolved",
  );
});

// An unrecognised URL alongside a recognised one must not block the harvest:
// plenty of companies have one bespoke listing among their ATS postings.
Deno.test("harvestFromApplyURLs resolves through unrecognised noise", () => {
  const verdict = harvestFromApplyURLs([
    "https://careers.acme.com/apply",
    "https://boards.greenhouse.io/acme/jobs/1",
  ]);
  assertEquals(verdict.kind, "resolved");
  if (verdict.kind === "resolved") assertEquals(verdict.resolution.ats_token, "acme");
});

// ---------------------------------------------------------------------------
// C-2 — ATS slug probing
// ---------------------------------------------------------------------------

Deno.test("slugCandidates puts domain-derived guesses first", () => {
  const out = slugCandidates("Stripe, Inc.", "stripe.com");
  // Domain stem leads: a board at a company's own domain stem is almost
  // certainly that company, and the prober trusts provenance "domain" alone.
  assertEquals(out[0], { slug: "stripe", provenance: "domain" });
  assertEquals(out.map((c) => c.slug).includes("stripe.com"), true);
  assertEquals(out.every((c) => c.slug.length >= 2), true);
});

Deno.test("slugCandidates covers the shapes seen in production", () => {
  // Ashby registers some boards under the FULL domain —
  // jobs.ashbyhq.com/datasnipper.com/... — so the dot must survive.
  const ds = slugCandidates("DataSnipper", "datasnipper.com").map((c) => c.slug);
  assertEquals(ds.includes("datasnipper.com"), true);
  assertEquals(ds.includes("datasnipper"), true);

  // And 1stdibs' real Greenhouse token is the domain with the dot removed.
  const dibs = slugCandidates("1stdibs", "1stdibs.com").map((c) => c.slug);
  assertEquals(dibs.includes("1stdibscom"), true);

  // Multi-word names give both joined and hyphenated forms.
  const apfm = slugCandidates("A Place for Mom", null).map((c) => c.slug);
  assertEquals(apfm.includes("aplaceformom"), true);
  assertEquals(apfm.includes("a-place-for-mom"), true);
});

Deno.test("slugCandidates strips legal suffixes but keeps real trailing words", () => {
  assertEquals(slugCandidates("Shift Technology, Inc.", null)[0].slug, "shifttechnology");
  assertEquals(slugCandidates("Acme LLC", null)[0].slug, "acme");
  // "Co" is a suffix, but a one-word name must never be stripped to nothing.
  assertEquals(slugCandidates("Co", null).length, 0);
  assertEquals(slugCandidates(null, null), []);
});

Deno.test("slugCandidates dedupes and tags provenance", () => {
  const out = slugCandidates("Stripe", "stripe.com");
  assertEquals(new Set(out.map((c) => c.slug)).size, out.length);
  // "stripe" is reachable from both domain and name; the stronger provenance
  // wins because it is generated first and dedup keeps the first.
  assertEquals(out.find((c) => c.slug === "stripe")?.provenance, "domain");
});

// Lever is case-sensitive — verified live: api.lever.co/v0/postings/Kyverna
// returns 200, /kyverna returns 404. Lowercasing everything, which is the
// obvious thing to do, would miss every capitalised Lever board.
Deno.test("leverCaseVariants adds the capitalised form for one-word names", () => {
  const [candidate] = slugCandidates("Kyverna", null);
  const variants = leverCaseVariants(candidate, "Kyverna");
  assertEquals(variants.includes("kyverna"), true);
  assertEquals(variants.includes("Kyverna"), true);
});

Deno.test("leverCaseVariants stays quiet for multi-word names", () => {
  const [candidate] = slugCandidates("Shift Technology", null);
  // "Shifttechnology" is not a shape Lever boards take; generating it would
  // just double the request count for nothing.
  assertEquals(leverCaseVariants(candidate, "Shift Technology"), ["shifttechnology"]);
});

// The safety check. Greenhouse is the only supported ATS that names the board
// owner, so this is the strongest confirmation available that a 200 belongs to
// the company we were actually probing for.
Deno.test("boardNameMatches confirms a real hit", () => {
  assertEquals(boardNameMatches("Stripe", "Stripe, Inc."), true);
  assertEquals(boardNameMatches("Shift Technology", "Shift Technology"), true);
  // A display name that is really a domain still matches its bare form.
  assertEquals(boardNameMatches("1stDibs.com", "1stdibs"), true);
});

Deno.test("boardNameMatches rejects somebody else's board", () => {
  assertEquals(boardNameMatches("Acme Robotics", "Acme Financial"), false);
  assertEquals(boardNameMatches("Coalition Technologies", "Coalition"), false);
  // Same shape, and probably the SAME company — but nothing in the strings
  // says so, and the cost of being wrong is one-sided. Missing is the choice.
  assertEquals(boardNameMatches("Stripe Payments", "Stripe"), false);
  assertEquals(boardNameMatches(null, "Stripe"), false);
  assertEquals(boardNameMatches("Stripe", ""), false);
  // Short names must not prefix-match their way into another company: "Go"
  // would otherwise match "Google", "GoCardless" and "GoodRx".
  assertEquals(boardNameMatches("Go", "Google"), false);
});

// ---------------------------------------------------------------------------
// C-8 — the early-career write filter
// ---------------------------------------------------------------------------

function crawledJob(title: string) {
  // Only `title` is read; the rest satisfies NormalizedJob.
  return {
    source_ats: "greenhouse" as const,
    external_id: "1",
    title,
    listing_url: null,
    apply_url: null,
    apply_flow: "ats_form" as const,
    compensation_text: null,
    compensation: { min_annual: null, max_annual: null, min_hourly: null, max_hourly: null },
    location: null,
    category: null,
    employment_type: null,
    posted_at: null,
    description: null,
    description_raw: null,
    contact_email_on_posting: null,
    content_hash: "h",
  };
}

Deno.test("keepForEarlyCareerFeed keeps what classifyExperience can bucket", () => {
  assertEquals(keepForEarlyCareerFeed(crawledJob("Software Engineering Intern")), true);
  assertEquals(keepForEarlyCareerFeed(crawledJob("Junior Data Analyst")), true);
  assertEquals(keepForEarlyCareerFeed(crawledJob("New Grad Software Engineer")), true);
  // Ordering inside classifyExperience puts intern markers ahead of seniority
  // words, so this is an internship, not a senior role.
  assertEquals(keepForEarlyCareerFeed(crawledJob("Senior Software Engineering Intern")), true);
});

// This is what keeps the crawl affordable. Every kept job costs an LLM
// carousel and an embedding, so a filter that leaks mid/senior defeats the
// purpose of filtering at write time at all.
Deno.test("keepForEarlyCareerFeed drops everything above early career", () => {
  for (const title of [
    "Staff Software Engineer",
    "Senior Product Manager",
    "VP of Engineering",
    "Director, Data Science",
    "Software Engineer II",
  ]) {
    assertEquals(keepForEarlyCareerFeed(crawledJob(title)), false, title);
  }
});

// Enterprise early-career programmes rarely say "intern" or "junior" — they
// say "2027 Summer Analyst Program". classifyExperience returns null for
// those, and without the hint list the whole enterprise population would be
// filtered away, which is exactly the population the pivot needs.
Deno.test("keepForEarlyCareerFeed catches enterprise programme phrasing", () => {
  for (const title of [
    "2027 Summer Analyst Program",
    "Campus Recruiting — Technology",
    "Rotational Development Program",
    "Graduate Scheme, Engineering",
    "Co-op Student, Hardware",
  ]) {
    assertEquals(keepForEarlyCareerFeed(crawledJob(title)), true, title);
  }
});

// The hint list only runs when classifyExperience is UNSURE. A confident
// non-early classification is a rejection, or "Senior Engineer, Student
// Products" would be kept on the word "student".
Deno.test("keepForEarlyCareerFeed does not let hints override a confident level", () => {
  assertEquals(keepForEarlyCareerFeed(crawledJob("Senior Engineer, Student Products")), false);
  assertEquals(keepForEarlyCareerFeed(crawledJob("Director of Campus Recruiting")), false);
  assertEquals(keepForEarlyCareerFeed(crawledJob("Senior Analyst, Risk")), false);
  // Kept, but by classifyExperience rather than by a hint: its intern marker
  // deliberately beats seniority words so "Senior SWE Intern" reads right.
  // The cost is that a genuinely senior role ABOUT interns slips through.
  // Pre-existing behaviour, rare, and not worth loosening that rule over.
  assertEquals(keepForEarlyCareerFeed(crawledJob("Principal Engineer, Intern Tooling")), true);
});

// Found by dry-running against Stripe's and Anthropic's live boards: a plain
// substring hint list returned 24 "early-career" jobs and all 24 were
// Internal/International false positives. Word boundaries are the fix, and
// this test is what stops them being lost again.
Deno.test("keepForEarlyCareerFeed does not read Internal as intern", () => {
  for (const title of [
    "Internal Auditor - APAC Regulatory",
    "Internal Audit - Treasury",
    "International Indirect Tax, VAT/GST",
    "Internal Communications Manager, Tech",
    "Internal Product Engineer, Developer Productivity",
  ]) {
    assertEquals(keepForEarlyCareerFeed(crawledJob(title)), false, title);
  }
  // The real word still matches, with or without the plural.
  assertEquals(keepForEarlyCareerFeed(crawledJob("Product Intern")), true);
  assertEquals(keepForEarlyCareerFeed(crawledJob("Engineering Interns, Summer")), true);
});

Deno.test("keepForEarlyCareerFeed refuses untitled postings", () => {
  assertEquals(keepForEarlyCareerFeed(crawledJob("")), false);
  assertEquals(keepForEarlyCareerFeed(crawledJob("   ")), false);
});

// ---------------------------------------------------------------------------
// C-9 — early-career company seed
// ---------------------------------------------------------------------------

Deno.test("extractSeedCompanies takes identity only, keyed by board", () => {
  // Shapes lifted from a real public listings file.
  const out = extractSeedCompanies([
    { company_name: "Lucid Motors", url: "https://job-boards.greenhouse.io/lucidmotors/jobs/4964060007" },
    { company_name: "Mechanize", url: "https://jobs.ashbyhq.com/mechanize/1ef28bb2/application" },
  ]);
  assertEquals(out.companies.length, 2);
  assertEquals(out.companies[0], {
    name: "Lucid Motors",
    ats_type: "greenhouse",
    ats_token: "lucidmotors",
  });
  // Nothing but name and coordinates crosses over — no title, no location,
  // no id. The postings themselves come from the company's own ATS later.
  assertEquals(Object.keys(out.companies[0]).sort(), ["ats_token", "ats_type", "name"]);
});

// Two records can spell one company differently while pointing at the same
// board. Keying on the board — which is also what companies_ats_unique
// dedupes on — means the insert cannot collide with itself.
Deno.test("extractSeedCompanies dedupes on the board, not the name", () => {
  const out = extractSeedCompanies([
    { company_name: "1stdibs", url: "https://boards.greenhouse.io/1stdibscom/jobs/1" },
    { company_name: "1stDibs.com", url: "https://boards.greenhouse.io/1stdibscom/jobs/2" },
    { company_name: "1stdibs", url: "https://boards.greenhouse.io/1stdibscom/jobs/3" },
  ]);
  assertEquals(out.companies.length, 1);
  assertEquals(out.companies[0].name, "1stdibs");   // first spelling wins
  assertEquals(out.stats.distinctCompanyNames, 2);
});

// Unsupported hosts are TALLIED, not silently dropped: that count is the size
// of the prize for the Workday and Oracle adapters, measured on the exact
// market the pivot targets.
Deno.test("extractSeedCompanies tallies what no adapter can reach yet", () => {
  const out = extractSeedCompanies([
    { company_name: "RBC", url: "https://rbc.wd3.myworkdayjobs.com/en-US/careers/job/1" },
    { company_name: "Boeing", url: "https://boeing.wd1.myworkdayjobs.com/job/2" },
    { company_name: "Kaiser", url: "https://kp.taleo.net/careersection/external/jobdetail.ftl?job=1" },
    { company_name: "TikTok", url: "https://lifeattiktok.com/search/123" },
    { company_name: "Stripe", url: "https://boards.greenhouse.io/stripe/jobs/9" },
  ]);
  assertEquals(out.companies.length, 1);
  assertEquals(out.stats.unsupportedByHost["workday"], 2);
  assertEquals(out.stats.unsupportedByHost["oracle/taleo"], 1);
  assertEquals(out.stats.unsupportedByHost["other"], 1);
});

Deno.test("extractSeedCompanies skips records it cannot identify", () => {
  const out = extractSeedCompanies([
    { company_name: "", url: "https://boards.greenhouse.io/acme/jobs/1" },
    { company_name: "Acme", url: "" },
    { company_name: "Acme", url: null },
    {},
  ]);
  assertEquals(out.companies.length, 0);
  assertEquals(out.stats.records, 4);
});

// Greenhouse's application widget lives at boards.greenhouse.io/embed/job_app
// ?token=<job id>. The first path segment is Greenhouse's own route, not a
// customer board, and no board token is recoverable from it. Read naively it
// became a company token: a public early-career list had 14 distinct
// employers — Cerebras, Coinbase, Databricks, Dropbox among them — collapsing
// onto "embed", and boards-api 404s for it, so the crawler would have chased
// a board that does not exist.
Deno.test("classifyApplyURL refuses Greenhouse's own reserved routes", () => {
  assertEquals(classifyApplyURL("https://boards.greenhouse.io/embed/job_app?token=6099883"), null);
  assertEquals(classifyApplyURL("https://job-boards.greenhouse.io/embed/job_app?token=1"), null);
  assertEquals(classifyApplyURL("https://boards.greenhouse.io/api/whatever"), null);
  // A real board is untouched.
  const real = classifyApplyURL("https://boards.greenhouse.io/stripe/jobs/123");
  assertEquals(real?.ats_token, "stripe");
});

Deno.test("extractSeedCompanies drops aggregator boards, keeps spelling variants", () => {
  const board = (token: string, name: string) => ({
    company_name: name,
    url: `https://boards.greenhouse.io/${token}/jobs/1`,
  });

  // Two spellings of one employer is normal and must survive — real examples
  // from the lists: Match Group / Tinder, PlayStation / Sony Interactive.
  const variants = extractSeedCompanies([
    board("matchgroup", "Match Group"),
    board("matchgroup", "Tinder"),
  ]);
  assertEquals(variants.companies.length, 1);
  assertEquals(variants.aggregatorsDropped, []);

  // Three or more distinct employers on one board is an aggregator. Keeping
  // it would file other companies' postings under whichever name arrived
  // first.
  const aggregator = extractSeedCompanies([
    board("sharedlist", "Cerebras"),
    board("sharedlist", "Coinbase"),
    board("sharedlist", "Databricks"),
  ]);
  assertEquals(aggregator.companies.length, 0);
  assertEquals(aggregator.aggregatorsDropped, ["greenhouse:sharedlist"]);
});
