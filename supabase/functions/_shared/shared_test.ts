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
import { isSensitiveLabel, matchCanonical } from "./profile_fields.ts";
import { decodeHtmlEntities, extractPageProps, htmlToText } from "./boards/workatastartup.ts";
import { parseCompensation, sanitizeCompensation } from "./ats/compensation.ts";

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
