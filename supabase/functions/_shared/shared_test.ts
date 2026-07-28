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

Deno.test("pitchSubject picks the strongest hook", () => {
  assertEquals(
    pitchSubject({ candidateName: "Sam", jobTitle: "iOS Engineer", headline: "CS @ Berkeley" }),
    "Sam — video pitch for iOS Engineer (CS @ Berkeley)",
  );
  assertEquals(
    pitchSubject({ candidateName: "Sam", jobTitle: "PM", previousEmployers: ["Stripe"] }),
    "Sam — video pitch for PM (ex-Stripe)",
  );
  assertEquals(
    pitchSubject({ candidateName: "Sam", jobTitle: "PM" }),
    "Sam — video pitch for PM",
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
  assertEquals(content.text.includes("Skills: Swift, Go"), true);
  assertEquals(content.text.includes("Their pitch video and resume are attached."), true);
  assertEquals(content.text.includes("goes straight to Sam <script> (sam@x.io)"), true);
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
  assertEquals(content.text.includes("Watch their pitch: https://cdn/video.mp4"), true);
  assertEquals(content.text.includes("Resume: https://signed/resume.pdf"), true);
  assertEquals(content.text.includes("Hi,"), true);
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
