import { corsHeaders } from "../_shared/cors.ts";
import { requireCronSecret } from "../_shared/cron_auth.ts";

const APIFY_API_TOKEN = Deno.env.get("APIFY_API_TOKEN") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const APIFY_WEBHOOK_SECRET = Deno.env.get("APIFY_WEBHOOK_SECRET") ?? "";

// ─── Actor IDs ────────────────────────────────────────────────────────────────
// SCRAPER: TikTok — clockworks/tiktok-scraper (currently disabled, see runs below)
const TIKTOK_ACTOR_ID = "clockworks~tiktok-scraper";
// SCRAPER: Instagram — apify/instagram-scraper ($2.70/1,000 results, active)
const INSTAGRAM_ACTOR_ID = "apify~instagram-scraper";

// ─── TikTok hashtags (10 active) ─────────────────────────────────────────────
const TIKTOK_HASHTAGS = [
  "wearehiring",
  "nowhiring",
  "hiringnow",
  "hiring",
  "jobalert",
  "jobopening",
  "jobopportunity",
  "recruiting",
  // "jointheteam",
  "joinourteam",
  // "remotejobs",
  // "remotehiring",
  "remotework",
  // "techcareers",
  // "techhiring",
  // "devjobs",
  // "startupjobs",
  // "startuplife",
];

// ─── TikTok keyword search queries (10 active) ───────────────────────────────
const TIKTOK_SEARCH_QUERIES = [
  "we are hiring",
  "we're hiring",
  "now hiring",
  "currently hiring",
  "actively hiring",
  "we are looking for",
  // "we're looking for",
  // "growing our team",
  // "expanding our team",
  "join our team",
  // "open position",
  // "open role",
  // "job opening",
  // "job opportunity",
  "apply now hiring",
  "send your resume",
  "building our team",
];

// ─── Instagram hashtag URLs (18 active) ──────────────────────────────────────
// apify/instagram-scraper takes full URLs, not bare hashtag names.
const INSTAGRAM_HASHTAG_URLS = [
  "https://www.instagram.com/explore/tags/wearehiring/",
  "https://www.instagram.com/explore/tags/nowhiring/",
  "https://www.instagram.com/explore/tags/hiringnow/",
  "https://www.instagram.com/explore/tags/hiring/",
  "https://www.instagram.com/explore/tags/jobalert/",
  "https://www.instagram.com/explore/tags/jobopening/",
  "https://www.instagram.com/explore/tags/jobopenings/",
  "https://www.instagram.com/explore/tags/jobopportunity/",
  "https://www.instagram.com/explore/tags/recruiting/",
  // "https://www.instagram.com/explore/tags/recruitment/",
  // "https://www.instagram.com/explore/tags/jointheteam/",
  "https://www.instagram.com/explore/tags/joinourteam/",
  // "https://www.instagram.com/explore/tags/careers/",
  "https://www.instagram.com/explore/tags/remotejobs/",
  // "https://www.instagram.com/explore/tags/remotehiring/",
  // "https://www.instagram.com/explore/tags/remotework/",
  // "https://www.instagram.com/explore/tags/workfromhome/",
  // "https://www.instagram.com/explore/tags/hybridjobs/",
  "https://www.instagram.com/explore/tags/techjobs/",
  "https://www.instagram.com/explore/tags/techcareers/",
  "https://www.instagram.com/explore/tags/techhiring/",
  "https://www.instagram.com/explore/tags/engineeringjobs/",
  // "https://www.instagram.com/explore/tags/devjobs/",
  // "https://www.instagram.com/explore/tags/designjobs/",
  // "https://www.instagram.com/explore/tags/uxjobs/",
  "https://www.instagram.com/explore/tags/productjobs/",
  // "https://www.instagram.com/explore/tags/productdesign/",
  "https://www.instagram.com/explore/tags/startupjobs/",
  // "https://www.instagram.com/explore/tags/entryleveljobs/",
  // "https://www.instagram.com/explore/tags/entrylevel/",
  // "https://www.instagram.com/explore/tags/marketingjobs/",
  // "https://www.instagram.com/explore/tags/marketingcareers/",
  // "https://www.instagram.com/explore/tags/salesjobs/",
  // "https://www.instagram.com/explore/tags/salescareers/",
  // "https://www.instagram.com/explore/tags/datajobs/",
  // "https://www.instagram.com/explore/tags/datasciencejobs/",
  "https://www.instagram.com/explore/tags/aijobs/",
  // "https://www.instagram.com/explore/tags/cybersecurityjobs/",
  // "https://www.instagram.com/explore/tags/fintechjobs/",
];

// ─── Instagram keyword search queries (13 active) ────────────────────────────
// apify/instagram-scraper accepts comma-separated search terms in the `search`
// field and runs each term as its own query. Catches posts that describe a role
// without using a specific hiring hashtag.
const INSTAGRAM_KEYWORDS_CSV = [
  "we are hiring",
  "we're hiring",
  "now hiring",
  "currently hiring",
  "actively hiring",
  "we are looking for",
  // "we're looking for",
  // "we are growing",
  // "growing our team",
  // "expanding our team",
  // "building our team",
  "join our team",
  // "join the team",
  // "be part of our team",
  // "come work with us",
  // "come join us",
  // "open position",
  // "open role",
  // "open positions",
  "open roles",
  // "job opening",
  // "job opportunity",
  // "career opportunity",
  // "seeking a",
  // "looking for a",
  "apply now",
  "apply below",
  // "tap link in bio to apply",
  "send your resume",
  "email your resume",
  // "submit your resume",
  "send us your cv",
].join(", ");

// Results fetched per URL / per keyword term.
// Instagram hashtag run:  50 URLs  × 20 = up to 1,000 posts → ~$0.027 per run
// Instagram keyword run:  32 terms × 20 = up to  640 posts  → ~$0.017 per run
// TikTok run:             35 tags  × 20 = up to  700 posts  → ~$0.01  per run
// Daily total: ~2,340 raw posts, ~$0.05/day → ~$1.50/month well within free tier.
const RESULTS_PER_QUERY = 10;

async function startRun(
  actorId: string,
  input: Record<string, unknown>,
  label: string,
): Promise<string> {
  // Secret travels in a header, not the URL — request URLs are visible in
  // the Apify console and run logs.
  const webhookURL =
    `${SUPABASE_URL}/functions/v1/process-apify-results?platform=${label}`;

  const webhooksParam = btoa(JSON.stringify([{
    eventTypes: ["ACTOR.RUN.SUCCEEDED", "ACTOR.RUN.FAILED"],
    requestUrl: webhookURL,
    headersTemplate: JSON.stringify({
      "x-apify-webhook-secret": APIFY_WEBHOOK_SECRET,
    }),
  }]));

  const response = await fetch(
    `https://api.apify.com/v2/acts/${actorId}/runs?token=${APIFY_API_TOKEN}&memory=512&webhooks=${encodeURIComponent(webhooksParam)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(input),
    },
  );

  if (!response.ok) {
    const text = await response.text().catch(() => "");
    throw new Error(`Apify [${label}] run failed to start (${response.status}): ${text}`);
  }

  const json = await response.json();
  return json.data?.id ?? "unknown";
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const unauthorized = requireCronSecret(request);
  if (unauthorized) return unauthorized;

  if (!APIFY_API_TOKEN) {
    return new Response(
      JSON.stringify({ error: "APIFY_API_TOKEN not set" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  try {
    const [
      // tiktokHashtagRunId,
      // tiktokKeywordRunId,
      instagramHashtagRunId,
      instagramKeywordRunId,
    ] = await Promise.all([

      // // TikTok — hashtag search (latest posts, not top/viral)
      // startRun(TIKTOK_ACTOR_ID, {
      //   hashtags: TIKTOK_HASHTAGS,
      //   resultsPerPage: RESULTS_PER_QUERY,
      //   maxResults: RESULTS_PER_QUERY,
      //   sortType: "latest",
      // }, "tiktok"),

      // // TikTok — keyword search (latest posts, not top/viral)
      // startRun(TIKTOK_ACTOR_ID, {
      //   searchQueries: TIKTOK_SEARCH_QUERIES,
      //   resultsPerPage: RESULTS_PER_QUERY,
      //   maxResults: RESULTS_PER_QUERY,
      //   sortType: "latest",
      // }, "tiktok"),

      // Instagram — hashtag URLs (directUrls mode)
      // "URLs always take priority over search queries"
      startRun(INSTAGRAM_ACTOR_ID, {
        directUrls: INSTAGRAM_HASHTAG_URLS,
        resultsLimit: RESULTS_PER_QUERY,
      }, "instagram"),

      // Instagram — keyword search (search field mode)
      // Comma-separated terms; actor runs each as a separate query.
      startRun(INSTAGRAM_ACTOR_ID, {
        search: INSTAGRAM_KEYWORDS_CSV,
        resultsLimit: RESULTS_PER_QUERY,
      }, "instagram"),

    ]);

    console.log(JSON.stringify({
      event: "apify_scrape_triggered",
      counts: {
        // tiktokHashtags: TIKTOK_HASHTAGS.length,
        // tiktokKeywords: TIKTOK_SEARCH_QUERIES.length,
        instagramHashtagURLs: INSTAGRAM_HASHTAG_URLS.length,
        instagramKeywordTerms: INSTAGRAM_KEYWORDS_CSV.split(",").length,
      },
      // tiktokHashtagRunId,
      // tiktokKeywordRunId,
      instagramHashtagRunId,
      instagramKeywordRunId,
    }));

    return new Response(
      JSON.stringify({ instagramHashtagRunId, instagramKeywordRunId }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    console.error("trigger-apify-scrape error:", message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
