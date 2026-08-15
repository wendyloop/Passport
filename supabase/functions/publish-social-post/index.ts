// Publishes queued carousel cards to Instagram.
//
// The iOS admin Social tab renders each job's slides to 1080×1350 JPEGs, puts
// them in the public `social-cards` bucket, and writes a `social_posts` row
// with status 'rendered'. This function drains that queue.
//
// There is no human approval step by design — the quality bar lives in
// get_jobs_needing_social_post (see 20260815110000_social_posts.sql), which
// applies identically whether a person or this cron does the posting.
//
// Instagram's Content Publishing API is a three-step dance:
//   1. one container per image (is_carousel_item=true)
//   2. one CAROUSEL container listing those children + the caption
//   3. media_publish on the carousel container
// Containers are asynchronous, so step 3 waits for the carousel to report
// FINISHED. Images must be JPEGs at publicly fetchable URLs — Meta's fetcher
// is unauthenticated, which is why the bucket is public.
//
// Auth: x-pitch-cron-secret (pg_net carries no JWT), so this function needs a
// `[functions.publish-social-post] verify_jwt = false` entry in config.toml —
// without it the next bare deploy re-enables gateway JWT checks and every
// cron call 401s.
//
// TikTok is deliberately absent: an unaudited client's posts stay
// self-visible only, so those go out by hand from the admin tab until the
// Content Posting API audit clears.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/client.ts";
import { jsonError, jsonResponse } from "../_shared/http.ts";
import { requireCronSecret } from "../_shared/cron_auth.ts";
import { recordPipelineRun } from "../_shared/pipeline_runs.ts";

const IG_ACCESS_TOKEN = Deno.env.get("IG_ACCESS_TOKEN") ?? "";
const IG_USER_ID = Deno.env.get("IG_USER_ID") ?? "";
const GRAPH_VERSION = Deno.env.get("IG_GRAPH_VERSION") ?? "v21.0";
const GRAPH = `https://graph.facebook.com/${GRAPH_VERSION}`;

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const BUCKET = "social-cards";

// One post per invocation. Instagram allows 50/24h, but a job feed wants a
// steady trickle, not a burst — schedule this a few times a day.
const MAX_PER_RUN = Number(Deno.env.get("SOCIAL_MAX_PER_RUN") ?? "1");
// Containers usually finish in seconds; give up rather than hold the worker.
const CONTAINER_POLL_ATTEMPTS = 10;
const CONTAINER_POLL_MS = 2_000;
const HTTP_TIMEOUT_MS = 20_000;

type SocialPostRow = {
  id: string;
  job_id: string;
  platform: string;
  image_paths: string[];
  caption: string;
  hashtags: string[];
  attempt_count: number;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const unauthorized = requireCronSecret(request);
  if (unauthorized) return unauthorized;

  const admin = createAdminClient();
  const startedAt = Date.now();

  const { data: queued, error: queueError } = await admin
    .from("social_posts")
    .select("id, job_id, platform, image_paths, caption, hashtags, attempt_count")
    .eq("platform", "instagram")
    .eq("status", "rendered")
    .lt("attempt_count", 3)
    .order("created_at", { ascending: true })
    .limit(MAX_PER_RUN);
  if (queueError) return jsonError(`load queue failed: ${queueError.message}`);

  const rows = (queued ?? []) as SocialPostRow[];
  if (rows.length === 0) {
    const summary = { event: "publish_social_post_run", published: 0, failed: 0, skipped: 0, reason: "queue empty" };
    console.log(JSON.stringify(summary));
    return jsonResponse({ summary, outcomes: [] });
  }

  // Credentials are checked only once there is something to post, so the
  // cron stays silent between setting up this function and configuring
  // Instagram rather than logging a failure three times a day.
  if (!IG_ACCESS_TOKEN || !IG_USER_ID) {
    return jsonError("IG_ACCESS_TOKEN / IG_USER_ID not configured", 500);
  }

  // Meta enforces 50 posts per rolling 24h. Blowing through it gets the
  // whole app rate-limited, so check before spending any work.
  const remaining = await publishingHeadroom();
  if (remaining !== null && remaining <= 0) {
    const summary = { event: "publish_social_post_run", published: 0, failed: 0, skipped: rows.length, reason: "daily quota exhausted" };
    console.log(JSON.stringify(summary));
    return jsonResponse({ summary, outcomes: [] });
  }

  const outcomes: Array<Record<string, unknown>> = [];
  let published = 0;
  let failed = 0;

  for (const row of rows) {
    try {
      const permalink = await publishCarousel(row);
      await admin
        .from("social_posts")
        .update({
          status: "posted",
          permalink: permalink.permalink,
          external_post_id: permalink.mediaId,
          posted_at: new Date().toISOString(),
          error: null,
        })
        .eq("id", row.id);
      published += 1;
      outcomes.push({ id: row.id, job_id: row.job_id, status: "posted", media_id: permalink.mediaId });
    } catch (error) {
      const message = (error as Error).message.slice(0, 500);
      const attempts = row.attempt_count + 1;
      await admin
        .from("social_posts")
        .update({
          // Three strikes, then park it as failed so the queue keeps moving.
          status: attempts >= 3 ? "failed" : "rendered",
          attempt_count: attempts,
          error: message,
        })
        .eq("id", row.id);
      failed += 1;
      outcomes.push({ id: row.id, job_id: row.job_id, status: "error", error: message });
    }
  }

  const summary = {
    event: "publish_social_post_run",
    published,
    failed,
    skipped: 0,
    duration_ms: Date.now() - startedAt,
  };
  console.log(JSON.stringify(summary));
  await recordPipelineRun(admin, "publish-social-post", startedAt, summary, failed);

  return jsonResponse({ summary, outcomes });
});

// ---------------------------------------------------------------------------

function publicImageURL(path: string): string {
  return `${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/${path}`;
}

function fullCaption(row: SocialPostRow): string {
  const tags = (row.hashtags ?? []).map((t) => `#${t}`).join(" ");
  return tags ? `${row.caption}\n\n${tags}` : row.caption;
}

async function graphFetch(
  url: string,
  init: RequestInit = {},
): Promise<Record<string, unknown>> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), HTTP_TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const detail = (payload as { error?: { message?: string } })?.error?.message ??
      JSON.stringify(payload).slice(0, 200);
    throw new Error(`Graph ${response.status}: ${detail}`);
  }
  return payload as Record<string, unknown>;
}

/// Posts left in the rolling 24h window, or null if the check itself fails
/// (in which case we let the publish attempt proceed and surface the real
/// error from Meta rather than silently stalling the queue).
async function publishingHeadroom(): Promise<number | null> {
  try {
    const payload = await graphFetch(
      `${GRAPH}/${IG_USER_ID}/content_publishing_limit?fields=quota_usage,config&access_token=${IG_ACCESS_TOKEN}`,
    );
    const entry = (payload.data as Array<Record<string, unknown>> | undefined)?.[0];
    if (!entry) return null;
    const used = Number(entry.quota_usage ?? 0);
    const total = Number((entry.config as { quota_total?: number } | undefined)?.quota_total ?? 50);
    return total - used;
  } catch (error) {
    console.error(JSON.stringify({
      event: "publishing_limit_check_failed",
      error: (error as Error).message,
    }));
    return null;
  }
}

async function publishCarousel(row: SocialPostRow): Promise<{ mediaId: string; permalink: string | null }> {
  const paths = row.image_paths ?? [];
  if (paths.length < 2) throw new Error(`carousel needs 2+ images, got ${paths.length}`);
  if (paths.length > 10) throw new Error(`carousel accepts at most 10 images, got ${paths.length}`);

  // 1. One container per image.
  const childIds: string[] = [];
  for (const path of paths) {
    const params = new URLSearchParams({
      image_url: publicImageURL(path),
      is_carousel_item: "true",
      access_token: IG_ACCESS_TOKEN,
    });
    const created = await graphFetch(`${GRAPH}/${IG_USER_ID}/media`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: params.toString(),
    });
    const id = created.id as string | undefined;
    if (!id) throw new Error(`no container id for ${path}`);
    childIds.push(id);
  }

  // 2. The carousel container that ties them together.
  const carouselParams = new URLSearchParams({
    media_type: "CAROUSEL",
    children: childIds.join(","),
    caption: fullCaption(row),
    access_token: IG_ACCESS_TOKEN,
  });
  const carousel = await graphFetch(`${GRAPH}/${IG_USER_ID}/media`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: carouselParams.toString(),
  });
  const creationId = carousel.id as string | undefined;
  if (!creationId) throw new Error("no carousel container id");

  await waitForContainer(creationId);

  // 3. Publish.
  const publishParams = new URLSearchParams({
    creation_id: creationId,
    access_token: IG_ACCESS_TOKEN,
  });
  const publishedMedia = await graphFetch(`${GRAPH}/${IG_USER_ID}/media_publish`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: publishParams.toString(),
  });
  const mediaId = publishedMedia.id as string | undefined;
  if (!mediaId) throw new Error("publish returned no media id");

  let permalink: string | null = null;
  try {
    const detail = await graphFetch(
      `${GRAPH}/${mediaId}?fields=permalink&access_token=${IG_ACCESS_TOKEN}`,
    );
    permalink = (detail.permalink as string | undefined) ?? null;
  } catch {
    // Cosmetic only — the post is already live.
  }

  return { mediaId, permalink };
}

/// Containers are processed asynchronously; publishing an unfinished one
/// fails. ERROR carries the real reason (usually an unreachable image URL).
async function waitForContainer(containerId: string): Promise<void> {
  for (let attempt = 0; attempt < CONTAINER_POLL_ATTEMPTS; attempt++) {
    const payload = await graphFetch(
      `${GRAPH}/${containerId}?fields=status_code,status&access_token=${IG_ACCESS_TOKEN}`,
    );
    const status = payload.status_code as string | undefined;
    if (status === "FINISHED") return;
    if (status === "ERROR" || status === "EXPIRED") {
      throw new Error(`container ${status}: ${payload.status ?? "no detail"}`);
    }
    await new Promise((resolve) => setTimeout(resolve, CONTAINER_POLL_MS));
  }
  throw new Error("container did not finish in time");
}
