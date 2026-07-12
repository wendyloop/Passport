import { createAdminClient } from "../_shared/client.ts";

const APIFY_API_TOKEN = Deno.env.get("APIFY_API_TOKEN") ?? "";
const APIFY_WEBHOOK_SECRET = Deno.env.get("APIFY_WEBHOOK_SECRET") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";

// ─── Screening algorithm ───────────────────────────────────────────────────────
//
// Two-pass filter applied to every post caption:
//
// Pass 1 — NEGATIVE filter (job seekers, not employers)
//   Rejects posts where the author is clearly a candidate looking for work,
//   not a company posting a role. These are the most common false positives
//   from broad hashtags like #hiring and #remotejobs.
//
// Pass 2 — POSITIVE filter (employer hiring signals)
//   Requires at least one phrase that signals an employer is actively posting
//   a role. The positive list is intentionally specific to reduce noise.
//
// A post must PASS both filters to be inserted into the review queue.

const NEGATIVE_KEYWORDS = [
  // Job seeker self-descriptions
  "looking for a job",
  "looking for work",
  "i'm looking for",
  "im looking for",
  "i am looking for",
  "need a job",
  "need work",
  "seeking employment",
  "seeking a position",
  "seeking a role",
  "seeking a job",
  "hire me",
  "please hire me",
  "i need a job",
  "i'm available",
  "im available",
  "open to work",
  "open to opportunities",
  "open to new opportunities",
  "#opentowork",
  "would love to work",
  "hoping to find",
  "anyone hiring",
  "does anyone know",
  "let me know if you're hiring",
  "let me know if you are hiring",
  "any companies hiring",
  "resume drop",
  // Motivational / non-hiring use of hiring words
  "god is hiring",
  "heaven is hiring",
  "universe is hiring",
];

const POSITIVE_KEYWORDS = [
  // Direct employer statements
  "we're hiring",
  "we are hiring",
  "now hiring",
  "currently hiring",
  "actively hiring",
  "we're looking for",
  "we are looking for",
  // Team growth signals
  "join our team",
  "join the team",
  "be part of our team",
  "come work with us",
  "come join us",
  "growing our team",
  "expanding our team",
  "building our team",
  "we are growing",
  "we're growing",
  // Role signals
  "open position",
  "open role",
  "open roles",
  "open positions",
  "job opening",
  "job opportunity",
  "career opportunity",
  "we have an opening",
  "new opening",
  // Application instructions (strong employer signal)
  "apply now",
  "apply below",
  "apply via",
  "apply at",
  "apply through",
  "apply on our website",
  "apply here",
  "apply today",
  "link in bio to apply",
  "tap the link to apply",
  "tap link in bio",
  "send your resume",
  "send us your resume",
  "send resume to",
  "email your resume",
  "submit your resume",
  "send us your cv",
  "dm us your resume",
  "drop your resume",
];

function screenPost(caption: string): "pass" | "noise" {
  if (!caption || caption.trim().length < 20) return "noise";
  const lower = caption.toLowerCase();

  // Pass 1: reject job seekers
  if (NEGATIVE_KEYWORDS.some((kw) => lower.includes(kw))) return "noise";

  // Pass 2: require at least one employer signal
  if (POSITIVE_KEYWORDS.some((kw) => lower.includes(kw))) return "pass";

  return "noise";
}

function extractEmail(text: string): string | null {
  const match = text.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i);
  return match?.[0]?.toLowerCase() ?? null;
}

// ─── LLM classification ────────────────────────────────────────────────────────

interface Classification {
  location: string | null;
  job_function: string | null;
  employment_type: string | null;
  compensation_min_annual: number | null;
  compensation_max_annual: number | null;
  compensation_min_hourly: number | null;
  compensation_max_hourly: number | null;
}

const VALID_JOB_FUNCTIONS = [
  "engineering", "design", "product", "science",
  "sales", "marketing", "support", "operations",
  "hr", "finance", "legal",
];

const VALID_EMPLOYMENT_TYPES = ["full_time", "part_time", "contract"];

const CLASSIFICATION_SYSTEM_PROMPT = `You are a structured data extractor for job postings scraped from social media. Given a post caption, extract the following fields and return ONLY valid JSON with no extra text:

{
  "location": string | null,          // City/state or country (e.g. "New York, NY", "London, UK", "Austin, TX"). Use "Remote" for remote-only. null if not mentioned.
  "job_function": string | null,      // One of: engineering, design, product, science, sales, marketing, support, operations, hr, finance, legal. null if unclear.
  "employment_type": string | null,   // One of: full_time, part_time, contract. null if not mentioned.
  "compensation_min_annual": number | null,  // Annual salary minimum in USD as integer (e.g. 80000). null if not annual pay or not mentioned.
  "compensation_max_annual": number | null,  // Annual salary maximum in USD as integer. null if not annual pay or not mentioned.
  "compensation_min_hourly": number | null,  // Hourly rate minimum in USD as integer (e.g. 25). null if not hourly pay or not mentioned.
  "compensation_max_hourly": number | null   // Hourly rate maximum in USD as integer. null if not hourly pay or not mentioned.
}

Rules:
- location must be a real city/country or "Remote" — never invent one.
- job_function must be one of the listed values exactly as written, never make up new categories.
- Pay: if a single number is given (not a range), set min = max = that number.
- Pay amounts: convert "k" notation (e.g. "$80k" → 80000).
- If pay is mentioned as equity-only or "competitive", leave pay fields null.`;

async function classifyPost(caption: string): Promise<Classification> {
  const empty: Classification = {
    location: null,
    job_function: null,
    employment_type: null,
    compensation_min_annual: null,
    compensation_max_annual: null,
    compensation_min_hourly: null,
    compensation_max_hourly: null,
  };

  if (!ANTHROPIC_API_KEY) return empty;

  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 256,
        system: CLASSIFICATION_SYSTEM_PROMPT,
        messages: [{ role: "user", content: caption.slice(0, 2000) }],
      }),
    });

    if (!resp.ok) return empty;
    const data = await resp.json();
    const text: string = data.content?.[0]?.text ?? "";

    // Strip markdown code fences if present
    const jsonText = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();
    const parsed = JSON.parse(jsonText) as Record<string, unknown>;

    const toIntOrNull = (v: unknown) =>
      typeof v === "number" && Number.isFinite(v) ? Math.round(v) : null;

    return {
      location: typeof parsed.location === "string" ? parsed.location.trim() || null : null,
      job_function: VALID_JOB_FUNCTIONS.includes(parsed.job_function as string)
        ? (parsed.job_function as string)
        : null,
      employment_type: VALID_EMPLOYMENT_TYPES.includes(parsed.employment_type as string)
        ? (parsed.employment_type as string)
        : null,
      compensation_min_annual: toIntOrNull(parsed.compensation_min_annual),
      compensation_max_annual: toIntOrNull(parsed.compensation_max_annual),
      compensation_min_hourly: toIntOrNull(parsed.compensation_min_hourly),
      compensation_max_hourly: toIntOrNull(parsed.compensation_max_hourly),
    };
  } catch {
    return empty;
  }
}

// ─── Per-query stat tracking ───────────────────────────────────────────────────

interface QueryStat {
  query: string;
  queryType: "hashtag" | "keyword";
  totalPulled: number;
  passedScreening: number;
  rejectedNoise: number;
  rejectedDuplicate: number;
  inserted: number;
  oldestPostAt: Date | null;
  newestPostAt: Date | null;
}

function makeQueryStat(query: string, queryType: "hashtag" | "keyword"): QueryStat {
  return { query, queryType, totalPulled: 0, passedScreening: 0, rejectedNoise: 0, rejectedDuplicate: 0, inserted: 0, oldestPostAt: null, newestPostAt: null };
}

function updateDateRange(stat: QueryStat, postDate: Date | null) {
  if (!postDate || isNaN(postDate.getTime())) return;
  if (!stat.oldestPostAt || postDate < stat.oldestPostAt) stat.oldestPostAt = postDate;
  if (!stat.newestPostAt || postDate > stat.newestPostAt) stat.newestPostAt = postDate;
}

// ─── Platform normalisation ────────────────────────────────────────────────────

interface NormalisedPost {
  sourceURL: string;
  videoURL: string;
  caption: string;
  creatorName: string | null;
  creatorHandle: string | null;
  thumbnailURL: string | null;
  postDate: Date | null;
  sourceQuery: string | null;   // which hashtag/keyword produced this result
  platform: "tiktok" | "instagram";
}

function normaliseTikTok(item: Record<string, unknown>): NormalisedPost | null {
  const webVideoUrl = typeof item.webVideoUrl === "string" ? item.webVideoUrl : null;
  if (!webVideoUrl) return null;

  const caption = typeof item.text === "string" ? item.text : "";

  // clockworks scraper returns flat dot-notation keys e.g. "authorMeta.name"
  const creatorHandle = typeof item["authorMeta.name"] === "string" ? item["authorMeta.name"] : null;
  const creatorName = typeof item["authorMeta.nickName"] === "string"
    ? item["authorMeta.nickName"]
    : creatorHandle; // fall back to handle if no display name
  const avatarUrl = typeof item["authorMeta.avatar"] === "string" ? item["authorMeta.avatar"] : null;

  // videoMeta.coverUrl or videoMeta.cover is the thumbnail when present
  const thumbnailURL = typeof item["videoMeta.coverUrl"] === "string" ? item["videoMeta.coverUrl"]
    : typeof item["videoMeta.cover"] === "string" ? item["videoMeta.cover"]
    : avatarUrl; // fall back to avatar

  // createTimeISO preferred; fall back to createTime (Unix seconds)
  let postDate: Date | null = null;
  if (typeof item.createTimeISO === "string") {
    postDate = new Date(item.createTimeISO);
  } else if (typeof item.createTime === "number") {
    postDate = new Date(item.createTime * 1000);
  }

  // clockworks scraper includes `hashtag` or `searchQuery` to indicate source
  const sourceQuery = typeof item.hashtag === "string" ? item.hashtag
    : typeof item.searchQuery === "string" ? item.searchQuery
    : null;

  return { sourceURL: webVideoUrl, videoURL: webVideoUrl, caption, creatorName, creatorHandle, thumbnailURL, postDate, sourceQuery, platform: "tiktok" };
}

function normaliseInstagram(item: Record<string, unknown>): NormalisedPost | null {
  const shortCode = typeof item.shortCode === "string" ? item.shortCode : null;
  const url = typeof item.url === "string" ? item.url
    : shortCode ? `https://www.instagram.com/p/${shortCode}/` : null;
  if (!url) return null;

  const caption = typeof item.caption === "string" ? item.caption : "";
  const creatorName = typeof item.ownerFullName === "string" && item.ownerFullName
    ? item.ownerFullName
    : typeof item.ownerUsername === "string" ? item.ownerUsername
    : null;
  const creatorHandle = typeof item.ownerUsername === "string" ? item.ownerUsername : null;
  const thumbnailURL = typeof item.displayUrl === "string" ? item.displayUrl : null;
  const directVideoUrl = typeof item.videoUrl === "string" && item.videoUrl ? item.videoUrl : null;

  // Only process video/reel posts — skip photos and carousels
  const mediaType = typeof item.type === "string" ? item.type.toLowerCase() : "";
  if (!directVideoUrl && mediaType !== "video") return null;

  let postDate: Date | null = null;
  if (typeof item.timestamp === "string") postDate = new Date(item.timestamp);
  else if (typeof item.timestamp === "number") postDate = new Date(item.timestamp * 1000);

  // apify/instagram-scraper includes `inputUrl` or `searchQuery` for source tracking
  const sourceQuery = typeof item.inputUrl === "string" ? item.inputUrl
    : typeof item.searchQuery === "string" ? item.searchQuery
    : null;

  return { sourceURL: url, videoURL: directVideoUrl ?? url, caption, creatorName, creatorHandle, thumbnailURL, postDate, sourceQuery, platform: "instagram" };
}

function normalise(item: Record<string, unknown>, platform: string): NormalisedPost | null {
  if (platform === "tiktok") return normaliseTikTok(item);
  if (platform === "instagram") return normaliseInstagram(item);
  return null;
}

// Derive a clean display label from a raw query string (hashtag URL or bare keyword)
function queryLabel(raw: string | null): string {
  if (!raw) return "unknown";
  // Instagram hashtag URL → bare tag name
  const tagMatch = raw.match(/explore\/tags\/([^/]+)/);
  if (tagMatch) return `#${tagMatch[1]}`;
  return raw.trim();
}

function queryType(raw: string | null): "hashtag" | "keyword" {
  if (!raw) return "keyword";
  return raw.includes("explore/tags/") || raw.startsWith("#") ? "hashtag" : "keyword";
}

// ─── Handler ───────────────────────────────────────────────────────────────────

Deno.serve(async (request) => {
  const url = new URL(request.url);
  // Header is the current channel; the query param is a transition fallback
  // for webhooks registered before the header switch (drop once a
  // post-switch run has landed and the secret is rotated). Fail closed when
  // the secret is unset.
  const providedSecret = request.headers.get("x-apify-webhook-secret") ??
    url.searchParams.get("secret");
  if (!APIFY_WEBHOOK_SECRET || providedSecret !== APIFY_WEBHOOK_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  const platform = url.searchParams.get("platform") ?? "";
  const runDate = new Date().toISOString().slice(0, 10); // YYYY-MM-DD

  try {
    const payload = await request.json().catch(() => ({})) as Record<string, unknown>;
    const resource = payload.resource as Record<string, unknown> | undefined;
    const datasetId = typeof resource?.defaultDatasetId === "string" ? resource.defaultDatasetId : null;
    const runId = typeof resource?.id === "string" ? resource.id : "unknown";

    if (!datasetId) {
      console.warn(JSON.stringify({ event: "apify_no_dataset", platform, eventType: payload.eventType }));
      return new Response("No dataset", { status: 200 });
    }

    const datasetResp = await fetch(
      `https://api.apify.com/v2/datasets/${datasetId}/items?token=${APIFY_API_TOKEN}&format=json&limit=500`,
    );
    if (!datasetResp.ok) throw new Error(`Dataset fetch failed: ${datasetResp.status}`);
    const items = await datasetResp.json() as Record<string, unknown>[];

    const adminClient = createAdminClient();

    // Load existing source URLs for deduplication
    // T3: existence check scoped to THIS batch's URLs — no more loading the
    // entire jobs.source_url column into memory (unbounded as jobs grows).
    const batchURLs = items
      .map((item) => normalise(item, platform)?.sourceURL)
      .filter((u): u is string => Boolean(u));
    const existingURLs = new Set<string>();
    // .in() has practical URL-length limits; chunk defensively.
    for (let i = 0; i < batchURLs.length; i += 200) {
      const { data: existing } = await adminClient
        .from("jobs")
        .select("source_url")
        .in("source_url", batchURLs.slice(i, i + 200));
      for (const row of existing ?? []) existingURLs.add(row.source_url as string);
    }

    // Per-query stat map keyed by display label
    const statMap = new Map<string, QueryStat>();

    // ── Pass 1: normalise + screen + deduplicate → collect candidates ──────────
    interface Candidate {
      post: NormalisedPost;
      stat: QueryStat;
    }
    const candidates: Candidate[] = [];

    for (const item of items) {
      const post = normalise(item, platform);
      if (!post) continue;

      const label = queryLabel(post.sourceQuery);
      const qType = queryType(post.sourceQuery);
      if (!statMap.has(label)) statMap.set(label, makeQueryStat(label, qType));
      const stat = statMap.get(label)!;

      stat.totalPulled++;
      updateDateRange(stat, post.postDate);

      if (screenPost(post.caption) === "noise") {
        stat.rejectedNoise++;
        continue;
      }
      stat.passedScreening++;

      if (existingURLs.has(post.sourceURL)) {
        stat.rejectedDuplicate++;
        continue;
      }
      existingURLs.add(post.sourceURL);

      candidates.push({ post, stat });
    }

    // ── Pass 2: classify all candidates in parallel via LLM ───────────────────
    const classifications = await Promise.all(
      candidates.map((c) => classifyPost(c.post.caption)),
    );

    // ── Pass 3: build all rows, then one bulk insert (T3) ─────────────────────
    const rows: Record<string, unknown>[] = [];
    for (let i = 0; i < candidates.length; i++) {
      const { post } = candidates[i];
      const cls = classifications[i];

      const applicationEmail = extractEmail(post.caption);
      const creatorURL = post.creatorHandle
        ? (post.platform === "tiktok"
          ? `https://www.tiktok.com/@${post.creatorHandle}`
          : `https://www.instagram.com/${post.creatorHandle}/`)
        : null;
      const title = post.creatorName ? `${post.creatorName} is hiring` : `${post.platform === "tiktok" ? "TikTok" : "Instagram"} hiring post`;

      rows.push({
        title,
        company_name: post.creatorName ?? (post.platform === "tiktok" ? "TikTok" : "Instagram"),
        description: post.caption || null,
        video_url: post.videoURL,
        source_url: post.sourceURL,
        source_platform: post.platform,
        source_creator_name: post.creatorName,
        source_creator_url: creatorURL,
        source_thumbnail_url: post.thumbnailURL,
        source_caption: post.caption || null,
        source_caption_raw: post.caption || null,
        source_posted_at: post.postDate?.toISOString() ?? null,
        source_apply_email_extracted: applicationEmail,
        application_email: applicationEmail,
        is_published: false,
        employer_profile_id: null,
        posted_by_profile_id: null,
        // LLM-classified fields
        location: cls.location,
        job_function: cls.job_function,
        employment_type: cls.employment_type,
        compensation_min_annual: cls.compensation_min_annual,
        compensation_max_annual: cls.compensation_max_annual,
        compensation_min_hourly: cls.compensation_min_hourly,
        compensation_max_hourly: cls.compensation_max_hourly,
      });
    }

    if (rows.length > 0) {
      // upsert + ignoreDuplicates = ON CONFLICT DO NOTHING on source_url, so
      // a race with another run can't fail the whole batch.
      const { error } = await adminClient
        .from("jobs")
        .upsert(rows, { onConflict: "source_url", ignoreDuplicates: true });
      if (error) {
        console.error("Bulk insert error:", error.message);
      } else {
        for (const { stat } of candidates) stat.inserted++;
      }
    }

    // Write per-query stats to DB
    const statsRows = [...statMap.values()].map((s) => ({
      run_id:              runId,
      run_date:            runDate,
      platform,
      query_type:          s.queryType,
      query:               s.query,
      total_pulled:        s.totalPulled,
      passed_screening:    s.passedScreening,
      rejected_noise:      s.rejectedNoise,
      rejected_duplicate:  s.rejectedDuplicate,
      inserted:            s.inserted,
      oldest_post_at:      s.oldestPostAt?.toISOString() ?? null,
      newest_post_at:      s.newestPostAt?.toISOString() ?? null,
    }));

    if (statsRows.length > 0) {
      const { error: statsError } = await adminClient.from("scrape_query_stats").insert(statsRows);
      if (statsError) console.error("Stats insert error:", statsError.message);
    }

    const totals = statsRows.reduce(
      (acc, r) => ({
        pulled: acc.pulled + r.total_pulled,
        passed: acc.passed + r.passed_screening,
        noise: acc.noise + r.rejected_noise,
        dupes: acc.dupes + r.rejected_duplicate,
        inserted: acc.inserted + r.inserted,
      }),
      { pulled: 0, passed: 0, noise: 0, dupes: 0, inserted: 0 },
    );

    console.log(JSON.stringify({
      event: "apify_ingest_complete",
      platform,
      runId,
      runDate,
      queries: statsRows.length,
      candidates: candidates.length,
      ...totals,
      accuracyPct: totals.pulled > 0 ? Math.round((totals.passed / totals.pulled) * 100) : 0,
    }));

    return new Response(JSON.stringify({ ...totals, queries: statsRows.length }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    console.error("process-apify-results error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
