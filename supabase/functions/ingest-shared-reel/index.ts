import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";

// ─── Same classification logic as process-apify-results ───────────────────────

const VALID_JOB_FUNCTIONS = [
  "engineering", "design", "product", "science",
  "sales", "marketing", "support", "operations",
  "hr", "finance", "legal",
];
const VALID_EMPLOYMENT_TYPES = ["full_time", "part_time", "contract"];

const CLASSIFICATION_SYSTEM_PROMPT = `You are a structured data extractor for job postings scraped from social media. Given a post caption, extract the following fields and return ONLY valid JSON with no extra text:

{
  "location": string | null,
  "job_function": string | null,
  "employment_type": string | null,
  "compensation_min_annual": number | null,
  "compensation_max_annual": number | null,
  "compensation_min_hourly": number | null,
  "compensation_max_hourly": number | null
}

Rules:
- location: city/state or "Remote". null if not mentioned.
- job_function: one of exactly: engineering, design, product, science, sales, marketing, support, operations, hr, finance, legal. null if unclear.
- employment_type: one of: full_time, part_time, contract. null if not mentioned.
- Pay: convert "k" notation ($80k → 80000). Single number → set min = max.
- Equity-only or "competitive" → leave pay null.`;

interface Classification {
  location: string | null;
  job_function: string | null;
  employment_type: string | null;
  compensation_min_annual: number | null;
  compensation_max_annual: number | null;
  compensation_min_hourly: number | null;
  compensation_max_hourly: number | null;
}

const emptyClassification: Classification = {
  location: null, job_function: null, employment_type: null,
  compensation_min_annual: null, compensation_max_annual: null,
  compensation_min_hourly: null, compensation_max_hourly: null,
};

async function classifyCaption(caption: string): Promise<Classification> {
  if (!ANTHROPIC_API_KEY || !caption.trim()) return emptyClassification;
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
    if (!resp.ok) return emptyClassification;
    const data = await resp.json();
    const text: string = data.content?.[0]?.text ?? "";
    const jsonText = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();
    const parsed = JSON.parse(jsonText) as Record<string, unknown>;
    const toInt = (v: unknown) =>
      typeof v === "number" && Number.isFinite(v) ? Math.round(v) : null;
    return {
      location: typeof parsed.location === "string" ? parsed.location.trim() || null : null,
      job_function: VALID_JOB_FUNCTIONS.includes(parsed.job_function as string) ? (parsed.job_function as string) : null,
      employment_type: VALID_EMPLOYMENT_TYPES.includes(parsed.employment_type as string) ? (parsed.employment_type as string) : null,
      compensation_min_annual: toInt(parsed.compensation_min_annual),
      compensation_max_annual: toInt(parsed.compensation_max_annual),
      compensation_min_hourly: toInt(parsed.compensation_min_hourly),
      compensation_max_hourly: toInt(parsed.compensation_max_hourly),
    };
  } catch {
    return emptyClassification;
  }
}

function extractEmail(text: string): string | null {
  return text.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i)?.[0]?.toLowerCase() ?? null;
}

// ─── oEmbed fetching ───────────────────────────────────────────────────────────

interface OEmbedResult {
  caption: string | null;
  authorName: string | null;
  authorHandle: string | null;
  thumbnailURL: string | null;
}

async function fetchTikTokOEmbed(url: string): Promise<OEmbedResult> {
  try {
    const resp = await fetch(`https://www.tiktok.com/oembed?url=${encodeURIComponent(url)}`);
    if (!resp.ok) return { caption: null, authorName: null, authorHandle: null, thumbnailURL: null };
    const data = await resp.json();
    const authorURL: string = data.author_url ?? "";
    const handle = authorURL.split("/@")[1]?.split("?")[0] ?? null;
    return {
      caption: typeof data.title === "string" ? data.title : null,
      authorName: typeof data.author_name === "string" ? data.author_name : null,
      authorHandle: handle,
      thumbnailURL: typeof data.thumbnail_url === "string" ? data.thumbnail_url : null,
    };
  } catch {
    return { caption: null, authorName: null, authorHandle: null, thumbnailURL: null };
  }
}

// ─── URL normalisation ─────────────────────────────────────────────────────────

interface NormalisedReel {
  platform: "tiktok" | "instagram";
  sourceURL: string;
  videoURL: string;
}

function normaliseURL(raw: string): NormalisedReel | null {
  let url: URL;
  try { url = new URL(raw); } catch { return null; }
  const host = url.hostname.toLowerCase();

  if (host.includes("tiktok.com")) {
    const videoId = raw.split("/video/")[1]?.split(/[?#/]/)[0];
    const embedURL = videoId
      ? `https://www.tiktok.com/player/v1/${videoId}?autoplay=1&loop=1&controls=1`
      : raw;
    return { platform: "tiktok", sourceURL: raw, videoURL: embedURL };
  }

  if (host.includes("instagram.com")) {
    const parts = url.pathname.split("/").filter(Boolean);
    const typeIdx = parts.findIndex((p) => ["p", "reel", "tv"].includes(p));
    const shortCode = typeIdx >= 0 ? parts[typeIdx + 1] : null;
    const embedURL = shortCode
      ? `https://www.instagram.com/p/${shortCode}/embed/`
      : raw;
    return { platform: "instagram", sourceURL: raw, videoURL: embedURL };
  }

  return null;
}

// ─── Handler ───────────────────────────────────────────────────────────────────

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing auth" }), {
      status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const userClient = createUserClient(authHeader);
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const adminClient = createAdminClient();
  const { data: profile, error: profileError } = await adminClient
    .from("profiles").select("role").eq("id", user.id).single();

  if (profileError) {
    console.error("ingest-shared-reel profile lookup error:", profileError.message);
    return new Response(JSON.stringify({ error: profileError.message }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (profile?.role !== "admin") {
    return new Response(JSON.stringify({ error: "Admin only" }), {
      status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let body: { url?: string };
  try { body = await request.json(); }
  catch { return new Response(JSON.stringify({ error: "Invalid JSON" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }); }

  if (!body.url) {
    return new Response(JSON.stringify({ error: "url is required" }), {
      status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const reel = normaliseURL(body.url);
  if (!reel) {
    return new Response(JSON.stringify({ error: "URL must be a TikTok or Instagram link" }), {
      status: 422, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Deduplicate
  const { data: existing } = await adminClient
    .from("jobs").select("id").eq("source_url", reel.sourceURL).maybeSingle();
  if (existing) {
    return new Response(JSON.stringify({ error: "Already in JobTok", id: existing.id }), {
      status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Fetch caption + author via oEmbed (TikTok only; Instagram oEmbed requires FB token)
  const oembed = reel.platform === "tiktok"
    ? await fetchTikTokOEmbed(reel.sourceURL)
    : { caption: null, authorName: null, authorHandle: null, thumbnailURL: null };

  const caption = oembed.caption ?? "";

  // Run the same classification + email extraction as the scraper pipeline
  const [cls] = await Promise.all([classifyCaption(caption)]);
  const applicationEmail = extractEmail(caption);

  const creatorHandle = oembed.authorHandle;
  const creatorName   = oembed.authorName ?? creatorHandle;
  const creatorURL    = creatorHandle
    ? (reel.platform === "tiktok"
        ? `https://www.tiktok.com/@${creatorHandle}`
        : `https://www.instagram.com/${creatorHandle}/`)
    : null;

  const title = creatorName
    ? `${creatorName} is hiring`
    : `${reel.platform === "tiktok" ? "TikTok" : "Instagram"} hiring post`;

  const { data: job, error: insertError } = await adminClient
    .from("jobs")
    .insert({
      title,
      company_name:              creatorName ?? (reel.platform === "tiktok" ? "TikTok" : "Instagram"),
      description:               caption || null,
      video_url:                 reel.videoURL,
      source_url:                reel.sourceURL,
      source_platform:           reel.platform,
      source_creator_name:       creatorName,
      source_creator_url:        creatorURL,
      source_thumbnail_url:      oembed.thumbnailURL,
      source_caption:            caption || null,
      source_caption_raw:        caption || null,
      application_email:         applicationEmail,
      source_apply_email_extracted: applicationEmail,
      is_published:              true,
      posted_by_profile_id:      null,
      employer_profile_id:       null,
      // LLM-classified fields (same as scraper pathway)
      location:                  cls.location,
      job_function:              cls.job_function,
      employment_type:           cls.employment_type,
      compensation_min_annual:   cls.compensation_min_annual,
      compensation_max_annual:   cls.compensation_max_annual,
      compensation_min_hourly:   cls.compensation_min_hourly,
      compensation_max_hourly:   cls.compensation_max_hourly,
    })
    .select("id, title")
    .single();

  if (insertError) {
    console.error("ingest-shared-reel insert error:", insertError.message);
    return new Response(JSON.stringify({ error: insertError.message }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  console.log(JSON.stringify({
    event: "reel_ingested",
    platform: reel.platform,
    jobId: job?.id,
    hasCaption: !!caption,
    jobFunction: cls.job_function,
    addedBy: user.id,
  }));

  return new Response(JSON.stringify({ id: job?.id, title: job?.title }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
