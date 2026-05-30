import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";

type ParseRequest = {
  sourceURL?: string;
};

type LLMExtraction = {
  company: string | null;
  title: string | null;
  location: string | null;
  compensation: string | null;
  how_to_apply: string | null;
  application_email: string | null;
  posted_date: string | null;
};

const openAIAPIKey = Deno.env.get("OPENAI_API_KEY") ?? "";
const openAIModel = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";

function detectPlatform(sourceURL: string | null) {
  if (!sourceURL) return null;
  const lower = sourceURL.toLowerCase();
  if (lower.includes("tiktok.com")) return "tiktok";
  if (lower.includes("instagram.com")) return "instagram";
  return "other";
}

function normalizeText(value?: string | null) {
  return value?.trim() ?? "";
}

function normalizeUnicodeText(value: string) {
  return value
    .normalize("NFKC")
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/\u00A0/g, " ");
}

function decodeHtmlEntities(value: string) {
  return normalizeUnicodeText(
    value
      .replace(/&#(\d+);/g, (_, numeric) => {
        const codePoint = Number.parseInt(numeric, 10);
        return Number.isFinite(codePoint) ? String.fromCodePoint(codePoint) : _;
      })
      .replace(/&#x([0-9a-f]+);/gi, (_, hex) => {
        const codePoint = Number.parseInt(hex, 16);
        return Number.isFinite(codePoint) ? String.fromCodePoint(codePoint) : _;
      })
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">"),
  );
}

function stripTags(value: string) {
  return decodeHtmlEntities(
    value
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<[^>]+>/g, " "),
  )
    .replace(/\s+/g, " ")
    .trim();
}

function guessTitle(text: string) {
  const lines = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  const candidate = lines.find((line) =>
    !line.includes("@") &&
    !line.includes("http://") &&
    !line.includes("https://") &&
    line.length >= 8
  );

  if (!candidate) return null;
  return candidate.length > 90 ? `${candidate.slice(0, 87).trim()}...` : candidate;
}

function guessLocation(text: string) {
  const normalized = text.replace(/\s+/g, " ");
  const remoteMatch = normalized.match(/\b(remote|hybrid|on[\s-]?site)\b/i);
  if (remoteMatch) {
    return remoteMatch[1].replace(/\b\w/g, (value) => value.toUpperCase());
  }

  const cityStateMatch = normalized.match(/\b([A-Z][a-z]+(?:\s[A-Z][a-z]+)*,\s?[A-Z]{2})\b/);
  if (cityStateMatch) return cityStateMatch[1];

  return null;
}

function guessCreatorName(title: string | null, description: string | null, sourcePlatform: string | null) {
  const normalizedTitle = title?.trim() ?? "";
  if (sourcePlatform === "instagram") {
    const instagramTitleMatch = normalizedTitle.match(/^(.+?)\s+on Instagram[:\s]/i);
    if (instagramTitleMatch?.[1]) return instagramTitleMatch[1].trim();
  }

  if (sourcePlatform === "tiktok") {
    const tiktokTitleMatch = normalizedTitle.match(/^(.+?)\s+on TikTok/i);
    if (tiktokTitleMatch?.[1]) return tiktokTitleMatch[1].trim();
  }

  const descriptionMatch = description?.match(/(?:by|from)\s+@?([A-Za-z0-9._]+)/i);
  if (descriptionMatch?.[1]) return descriptionMatch[1].trim();

  return null;
}

// Swift's iso8601 DateDecodingStrategy does not accept milliseconds (.000Z).
// Always strip them before returning dates to the client.
function toISO(date: Date): string {
  return date.toISOString().replace(/\.\d+Z$/, "Z");
}

// Sanitize any date string (including LLM output) into a Swift-safe ISO string, or null.
function sanitizeDate(value: string | null | undefined): string | null {
  if (!value) return null;
  // Already a full ISO with or without ms — parse and reformat.
  const d = new Date(value);
  if (!Number.isNaN(d.getTime())) return toISO(d);
  // Try bare date YYYY-MM-DD.
  const bare = value.match(/^(\d{4}-\d{2}-\d{2})$/);
  if (bare) {
    const d2 = new Date(`${bare[1]}T00:00:00Z`);
    if (!Number.isNaN(d2.getTime())) return toISO(d2);
  }
  return null;
}

function guessPostedAt(text: string) {
  const isoTimestampMatch = text.match(/\b(20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)\b/);
  if (isoTimestampMatch) {
    const parsed = new Date(isoTimestampMatch[1]);
    if (!Number.isNaN(parsed.getTime())) return toISO(parsed);
  }

  const isoMatch = text.match(/\b(20\d{2}-\d{2}-\d{2})\b/);
  if (isoMatch) {
    const parsed = new Date(`${isoMatch[1]}T00:00:00Z`);
    if (!Number.isNaN(parsed.getTime())) return toISO(parsed);
  }

  const slashMatch = text.match(/\b(\d{1,2})\/(\d{1,2})\/(\d{2,4})\b/);
  if (slashMatch) {
    const month = slashMatch[1].padStart(2, "0");
    const day = slashMatch[2].padStart(2, "0");
    const year = slashMatch[3].length === 2 ? `20${slashMatch[3]}` : slashMatch[3];
    const parsed = new Date(`${year}-${month}-${day}T00:00:00Z`);
    if (!Number.isNaN(parsed.getTime())) return toISO(parsed);
  }

  const monthMatch = text.match(
    /\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}(?:,\s*20\d{2})?\b/i,
  );
  if (monthMatch) {
    const parsed = new Date(monthMatch[0]);
    if (!Number.isNaN(parsed.getTime())) return toISO(parsed);
  }

  return null;
}

function extractApplicationEmail(text: string) {
  const normalized = normalizeUnicodeText(text);

  // Pass 1: direct email in the source text
  const directMatch = normalized.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i);
  if (directMatch) return directMatch[0].toLowerCase();

  // Pass 2: bracketed obfuscation only — [at] (at) {at}, [dot] (dot) {dot}
  const debracketed = normalized
    .replace(/\s*[\[(\{]\s*at\s*[\])\}]\s*/gi, "@")
    .replace(/\s*[\[(\{]\s*dot\s*[\])\}]\s*/gi, ".")
    .replace(/[＠﹫]/g, "@")
    .replace(/[。｡]/g, ".")
    .replace(/\s*@\s*/g, "@")
    .replace(/\s*\.\s*/g, ".");
  const debracketedMatch = debracketed.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i);
  if (debracketedMatch) return debracketedMatch[0].toLowerCase();

  // Pass 3: bare "word at domain dot tld" obfuscation (no brackets)
  const bareDeobfuscated = normalized
    .replace(/(\w+)\s+at\s+(\w+(?:\s+dot\s+\w+)+)/gi, (_m, local, domain) =>
      `${local}@${domain.replace(/\s+dot\s+/gi, ".")}`
    )
    .replace(/(\w+)\s+at\s+(\w+\.\w{2,})/gi, "$1@$2");
  const bareMatch = bareDeobfuscated.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i);
  return bareMatch?.[0]?.toLowerCase() ?? null;
}

function extractMetaContent(html: string, key: string) {
  const patterns = [
    new RegExp(`<meta[^>]+property=["']${key}["'][^>]+content="([^"]*)"`, "i"),
    new RegExp(`<meta[^>]+content="([^"]*)"[^>]+property=["']${key}["']`, "i"),
    new RegExp(`<meta[^>]+property=["']${key}["'][^>]+content='([^']*)'`, "i"),
    new RegExp(`<meta[^>]+content='([^']*)'[^>]+property=["']${key}["']`, "i"),
    new RegExp(`<meta[^>]+name=["']${key}["'][^>]+content="([^"]*)"`, "i"),
    new RegExp(`<meta[^>]+content="([^"]*)"[^>]+name=["']${key}["']`, "i"),
    new RegExp(`<meta[^>]+name=["']${key}["'][^>]+content='([^']*)'`, "i"),
    new RegExp(`<meta[^>]+content='([^']*)'[^>]+name=["']${key}["']`, "i"),
  ];

  for (const pattern of patterns) {
    const match = html.match(pattern);
    if (match?.[1]?.trim()) return decodeHtmlEntities(match[1].trim());
  }

  return null;
}

function extractJsonLd(html: string): string | null {
  const pattern = /<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let match;
  while ((match = pattern.exec(html)) !== null) {
    try {
      const data = JSON.parse(match[1]);
      const items = Array.isArray(data) ? data : [data];
      for (const item of items) {
        const desc = item?.description ?? item?.articleBody ?? null;
        if (typeof desc === "string" && desc.trim().length > 10) return desc.trim();
      }
    } catch { /* skip */ }
  }
  return null;
}

type TikTokData = {
  caption: string | null;
  videoPlayURL: string | null;
  thumbnailURL: string | null;
  authorNickname: string | null;
  authorHandle: string | null;
  createTime: number | null;
  bioLink: string | null;
};

function extractTikTokData(html: string): TikTokData {
  const empty: TikTokData = { caption: null, videoPlayURL: null, thumbnailURL: null, authorNickname: null, authorHandle: null, createTime: null, bioLink: null };
  const scriptMatch = html.match(
    /<script[^>]+id=["']__UNIVERSAL_DATA_FOR_REHYDRATION__["'][^>]*>([\s\S]*?)<\/script>/i,
  );
  if (!scriptMatch) return empty;
  try {
    const data = JSON.parse(scriptMatch[1]);
    const item = data?.["__DEFAULT_SCOPE__"]?.["webapp.video-detail"]?.itemInfo?.itemStruct;
    if (!item) return empty;

    const caption = typeof item.desc === "string" && item.desc.trim() ? item.desc.trim() : null;
    // playAddr is the direct CDN video URL — lets AVPlayer play it natively
    const videoPlayURL = typeof item.video?.playAddr === "string" && item.video.playAddr ? item.video.playAddr : null;
    const thumbnailURL = typeof item.video?.cover === "string" ? item.video.cover : (typeof item.video?.originCover === "string" ? item.video.originCover : null);
    const authorNickname = typeof item.author?.nickname === "string" ? item.author.nickname : null;
    const authorHandle = typeof item.author?.uniqueId === "string" ? item.author.uniqueId : null;
    const createTime = typeof item.createTime === "number" ? item.createTime : null;
    // bioLink — the link-in-bio URL where many creators put job application links
    const bioLink = typeof item.author?.bioLink?.link === "string" ? item.author.bioLink.link : null;

    return { caption, videoPlayURL, thumbnailURL, authorNickname, authorHandle, createTime, bioLink };
  } catch {
    return empty;
  }
}

function extractTitleTag(html: string) {
  const match = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (!match?.[1]) return null;
  return stripTags(match[1]);
}

function extractCanonicalURL(html: string) {
  const match = html.match(/<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)["'][^>]*>/i);
  return match?.[1] ? decodeHtmlEntities(match[1].trim()) : null;
}

async function fetchPageHTML(sourceURL: string) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch(sourceURL, {
      signal: controller.signal,
      headers: {
        "user-agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "accept-language": "en-US,en;q=0.9",
        "sec-fetch-dest": "document",
        "sec-fetch-mode": "navigate",
        "sec-fetch-site": "none",
      },
      redirect: "follow",
    });

    const contentType = response.headers.get("content-type") ?? "";
    if (!response.ok) {
      return { html: null, contentType, status: response.status };
    }
    if (!contentType.includes("text/html")) {
      return { html: null, contentType, status: response.status };
    }
    return {
      html: await response.text().catch(() => null),
      contentType,
      status: response.status,
    };
  } catch {
    return { html: null, contentType: "", status: 0 };
  } finally {
    clearTimeout(timeoutId);
  }
}

async function extractSourceText(sourceURL: string, sourcePlatform: string | null) {
  const fetchResult = await fetchPageHTML(sourceURL);
  const html = fetchResult?.html ?? null;
  const ogDescription = html ? extractMetaContent(html, "og:description") : null;
  const description = html ? extractMetaContent(html, "description") : null;
  const twitterDescription = html ? extractMetaContent(html, "twitter:description") : null;
  const ogTitle = html ? extractMetaContent(html, "og:title") : null;
  const twitterTitle = html ? extractMetaContent(html, "twitter:title") : null;
  const ogImage = html ? extractMetaContent(html, "og:image") : null;
  const twitterImage = html ? extractMetaContent(html, "twitter:image") : null;
  const articlePublishedAt = html ? extractMetaContent(html, "article:published_time") : null;
  const canonicalURL = html ? extractCanonicalURL(html) : null;
  const titleTag = html ? extractTitleTag(html) : null;
  const jsonLdDescription = html ? extractJsonLd(html) : null;
  const tiktokData = (html && sourcePlatform === "tiktok") ? extractTikTokData(html) : null;
  const instagramCaption = (html && sourcePlatform === "instagram") ? extractInstagramCaption(html) : null;

  // For Instagram, also fetch the /embed/captioned/ sub-page which is server-rendered with actual content
  let instagramEmbedCaption: string | null = null;
  let instagramEmbedOgDescription: string | null = null;
  let instagramEmbedOgTitle: string | null = null;
  let instagramEmbedOgImage: string | null = null;
  if (sourcePlatform === "instagram") {
    const embedHtml = await fetchInstagramEmbedPage(sourceURL);
    if (embedHtml) {
      instagramEmbedCaption = extractCaptionFromInstagramEmbed(embedHtml);
      instagramEmbedOgDescription = extractMetaContent(embedHtml, "og:description");
      instagramEmbedOgTitle = extractMetaContent(embedHtml, "og:title");
      instagramEmbedOgImage = extractMetaContent(embedHtml, "og:image") ?? extractMetaContent(embedHtml, "twitter:image");
    }
  }

  const visibleText = html ? stripTags(html).slice(0, 4000) : "";

  const tiktokAuthorHandle = tiktokData?.authorHandle ?? null;
  const tiktokAuthorURL = tiktokAuthorHandle ? `https://www.tiktok.com/@${tiktokAuthorHandle}` : null;

  let instagramOEmbedTitle: string | null = null;
  let instagramAuthorName: string | null = null;
  let instagramThumbnailURL: string | null = null;
  if (sourcePlatform === "instagram") {
    const oembed = await fetchInstagramOEmbed(sourceURL);
    instagramOEmbedTitle = oembed.title;
    instagramAuthorName = oembed.author_name;
    instagramThumbnailURL = oembed.thumbnail_url;
  }

  const textParts = [
    instagramEmbedOgTitle,
    ogTitle,
    twitterTitle,
    titleTag,
    tiktokData?.caption,
    tiktokData?.bioLink,
    instagramOEmbedTitle,
    instagramEmbedCaption,
    instagramEmbedOgDescription,
    instagramCaption,
    ogDescription,
    description,
    twitterDescription,
    jsonLdDescription,
    visibleText,
  ].filter((value): value is string => Boolean(value && value.trim()));

  const mergedText = textParts.join("\n").trim();
  const derivedCreatorName = tiktokData?.authorNickname ?? instagramAuthorName ?? guessCreatorName(ogTitle ?? twitterTitle ?? titleTag, ogDescription ?? description ?? twitterDescription, sourcePlatform);
  const derivedCreatorURL = tiktokAuthorURL ?? canonicalURL ?? null;
  const derivedThumbnailURL = tiktokData?.thumbnailURL ?? instagramThumbnailURL ?? instagramEmbedOgImage ?? ogImage ?? twitterImage ?? null;
  const derivedPostedAt = (tiktokData?.createTime != null)
    ? toISO(new Date(tiktokData.createTime * 1000))
    : (articlePublishedAt && !Number.isNaN(new Date(articlePublishedAt).getTime())
        ? toISO(new Date(articlePublishedAt))
        : guessPostedAt(mergedText));
  const extractedEmail = extractApplicationEmail(mergedText);

  return {
    sourceText: mergedText,
    videoPlayURL: tiktokData?.videoPlayURL ?? null,
    derivedTitle: guessTitle(mergedText) ?? ogTitle ?? titleTag ?? tiktokData?.caption ?? instagramOEmbedTitle,
    derivedCreatorName,
    derivedCreatorURL,
    derivedThumbnailURL,
    derivedPostedAt,
    extractedEmail,
    fetchStatus: fetchResult?.status ?? null,
    fetchContentType: fetchResult?.contentType ?? null,
    htmlLength: html?.length ?? 0,
    scrapedMetadata: {
      og_title: ogTitle,
      twitter_title: twitterTitle,
      title_tag: titleTag,
      og_description: ogDescription,
      description,
      twitter_description: twitterDescription,
      canonical_url: canonicalURL,
      og_image: ogImage,
      twitter_image: twitterImage,
      article_published_at: articlePublishedAt,
      tiktok_caption: tiktokData?.caption ?? null,
      tiktok_author_name: tiktokData?.authorNickname ?? null,
      tiktok_author_url: tiktokAuthorURL,
      tiktok_thumbnail_url: tiktokData?.thumbnailURL ?? null,
      tiktok_video_play_url: tiktokData?.videoPlayURL ?? null,
      tiktok_bio_link: tiktokData?.bioLink ?? null,
      json_ld_description: jsonLdDescription,
      instagram_caption: instagramCaption,
      instagram_oembed_title: instagramOEmbedTitle,
      instagram_author_name: instagramAuthorName,
      instagram_embed_caption: instagramEmbedCaption,
      instagram_embed_og_description: instagramEmbedOgDescription,
      instagram_embed_og_title: instagramEmbedOgTitle,
    },
  };
}

async function fetchTikTokOEmbed(sourceURL: string) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 5000);
  try {
    const endpoint = `https://www.tiktok.com/oembed?url=${encodeURIComponent(sourceURL)}`;
    const response = await fetch(endpoint, { signal: controller.signal });
    if (!response.ok) return null;
    return await response.json().catch(() => null);
  } catch {
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
}

async function fetchInstagramEmbedPage(sourceURL: string): Promise<string | null> {
  // Instagram's /embed/ sub-path is server-rendered with actual post content (unlike the main URL which is a JS shell)
  try {
    const url = new URL(sourceURL);
    // Normalize to /p/{shortcode}/ or /reel/{shortcode}/ then append embed/
    const embedURL = url.origin + url.pathname.replace(/\/?$/, "/") + "embed/captioned/";
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 8000);
    try {
      const response = await fetch(embedURL, {
        signal: controller.signal,
        headers: {
          "user-agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
          "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          "accept-language": "en-US,en;q=0.9",
          "referer": "https://www.instagram.com/",
        },
        redirect: "follow",
      });
      if (!response.ok) return null;
      return await response.text().catch(() => null);
    } finally {
      clearTimeout(timeoutId);
    }
  } catch {
    return null;
  }
}

function extractCaptionFromInstagramEmbed(embedHtml: string): string | null {
  // The embed page has the caption in a <div class="Caption"> or <span class="Caption"> element
  // Also try extracting from the PostBody div and CaptionText spans
  const patterns = [
    // Standard caption div
    /<div[^>]+class="[^"]*Caption[^"]*"[^>]*>([\s\S]*?)<\/div>/i,
    // Span with caption text
    /<span[^>]+class="[^"]*Caption[^"]*"[^>]*>([\s\S]*?)<\/span>/i,
    // PostBody which wraps the caption on some embed formats
    /<div[^>]+class="[^"]*PostBody[^"]*"[^>]*>([\s\S]*?)<\/div>/i,
  ];

  for (const pattern of patterns) {
    const match = embedHtml.match(pattern);
    if (match?.[1]) {
      const text = stripTags(match[1]).trim();
      if (text.length > 5) return text;
    }
  }

  // Also try og:description from the embed page (embed pages often have these)
  const ogDesc = extractMetaContent(embedHtml, "og:description");
  if (ogDesc && ogDesc.length > 5) return ogDesc;

  // Try the JSON-LD on the embed page
  const jsonLd = extractJsonLd(embedHtml);
  if (jsonLd && jsonLd.length > 5) return jsonLd;

  // Try extractInstagramCaption patterns on the embed HTML too
  return extractInstagramCaption(embedHtml);
}

async function fetchInstagramOEmbed(sourceURL: string): Promise<{ title: string | null; author_name: string | null; thumbnail_url: string | null }> {
  const empty = { title: null, author_name: null, thumbnail_url: null };
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 5000);
  try {
    const endpoint = `https://www.instagram.com/oembed?url=${encodeURIComponent(sourceURL)}`;
    const response = await fetch(endpoint, {
      signal: controller.signal,
      headers: {
        "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "accept": "application/json",
      },
    });
    if (!response.ok) return empty;
    const data = await response.json().catch(() => null);
    if (!data) return empty;
    return {
      title: typeof data.title === "string" ? data.title : null,
      author_name: typeof data.author_name === "string" ? data.author_name : null,
      thumbnail_url: typeof data.thumbnail_url === "string" ? data.thumbnail_url : null,
    };
  } catch {
    return empty;
  } finally {
    clearTimeout(timeoutId);
  }
}

function extractInstagramCaption(html: string): string | null {
  // Pattern 1: edge_media_to_caption embedded in GraphQL JSON
  const edgeMatch = html.match(
    /"edge_media_to_caption"\s*:\s*\{\s*"edges"\s*:\s*\[\s*\{\s*"node"\s*:\s*\{\s*"text"\s*:\s*"((?:[^"\\]|\\[\s\S])*)"/,
  );
  if (edgeMatch?.[1]) {
    try { return JSON.parse(`"${edgeMatch[1]}"`); } catch { return edgeMatch[1]; }
  }

  // Pattern 2: window._sharedData (older Instagram pages)
  const sharedDataMatch = html.match(/window\._sharedData\s*=\s*(\{[\s\S]*?\});\s*<\/script>/i);
  if (sharedDataMatch) {
    try {
      const data = JSON.parse(sharedDataMatch[1]);
      const text = data?.entry_data?.PostPage?.[0]?.graphql?.shortcode_media
        ?.edge_media_to_caption?.edges?.[0]?.node?.text;
      if (typeof text === "string" && text.trim()) return text.trim();
    } catch {}
  }

  // Pattern 3: __additionalDataLoaded
  const addlMatch = html.match(
    /window\.__additionalDataLoaded\s*\(\s*['"][^'"]+['"]\s*,\s*(\{[\s\S]*?\})\s*\)\s*;/,
  );
  if (addlMatch) {
    try {
      const data = JSON.parse(addlMatch[1]);
      const text = data?.graphql?.shortcode_media?.edge_media_to_caption?.edges?.[0]?.node?.text;
      if (typeof text === "string" && text.trim()) return text.trim();
    } catch {}
  }

  // Pattern 4: accessibility_caption in any script blob
  const accessibilityMatch = html.match(/"accessibility_caption"\s*:\s*"((?:[^"\\]|\\[\s\S])*)"/);
  if (accessibilityMatch?.[1]) {
    try { return JSON.parse(`"${accessibilityMatch[1]}"`); } catch { return accessibilityMatch[1]; }
  }

  return null;
}

function extractionSchema() {
  return {
    type: "object",
    additionalProperties: false,
    required: [
      "company",
      "title",
      "location",
      "compensation",
      "how_to_apply",
      "application_email",
      "posted_date",
    ],
    properties: {
      company: { anyOf: [{ type: "string" }, { type: "null" }] },
      title: { anyOf: [{ type: "string" }, { type: "null" }] },
      location: { anyOf: [{ type: "string" }, { type: "null" }] },
      compensation: { anyOf: [{ type: "string" }, { type: "null" }] },
      how_to_apply: { anyOf: [{ type: "string" }, { type: "null" }] },
      application_email: { anyOf: [{ type: "string" }, { type: "null" }] },
      posted_date: { anyOf: [{ type: "string" }, { type: "null" }] },
    },
  };
}

function parseResponseOutputText(payload: Record<string, unknown>) {
  if (typeof payload.output_text === "string" && payload.output_text.trim()) {
    return payload.output_text;
  }

  const output = Array.isArray(payload.output) ? payload.output : [];
  for (const item of output) {
    if (!item || typeof item !== "object") continue;
    const content = Array.isArray((item as Record<string, unknown>).content)
      ? (item as Record<string, unknown>).content as Array<Record<string, unknown>>
      : [];

    for (const contentItem of content) {
      if (typeof contentItem?.text === "string" && contentItem.text.trim()) {
        return contentItem.text;
      }
    }
  }

  return null;
}

async function extractWithLLM(params: {
  sourceURL: string;
  sourcePlatform: string | null;
  rawText: string;
  metadata: Record<string, unknown>;
}): Promise<LLMExtraction | null> {
  if (!openAIAPIKey || !params.rawText.trim()) return null;

  const systemPrompt = [
    "You extract structured job-post information from scraped social media metadata.",
    "It is okay for any field to be null if the source does not clearly provide it.",
    "Do not guess or hallucinate missing values.",
    "Only return a value when there is evidence in the source text or scraped metadata.",
    "Return posted_date as ISO-8601 when known, otherwise null.",
    "Keep how_to_apply as the plain application instruction text if present.",
    "Normalize application_email into a standard email string if present.",
  ].join(" ");

  const userPrompt = JSON.stringify({
    source_url: params.sourceURL,
    source_platform: params.sourcePlatform,
    scraped_metadata: params.metadata,
    combined_source_text: params.rawText,
  });

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAIAPIKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: openAIModel,
      input: [
        {
          role: "system",
          content: [{ type: "input_text", text: systemPrompt }],
        },
        {
          role: "user",
          content: [{ type: "input_text", text: userPrompt }],
        },
      ],
      max_output_tokens: 800,
      text: {
        format: {
          type: "json_schema",
          name: "job_import_extraction",
          strict: true,
          schema: extractionSchema(),
        },
      },
    }),
  });

  if (!response.ok) return null;

  const payload = await response.json().catch(() => null);
  if (!payload || typeof payload !== "object") return null;

  const outputText = parseResponseOutputText(payload as Record<string, unknown>);
  if (!outputText) return null;

  try {
    return JSON.parse(outputText) as LLMExtraction;
  } catch {
    return null;
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    const userClient = createUserClient(authHeader);
    const adminClient = createAdminClient();
    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: profile, error: profileError } = await adminClient
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    if (profileError || profile?.role !== "admin") {
      return new Response(JSON.stringify({ error: "Admin access required" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = (await request.json().catch(() => ({}))) as ParseRequest;
    const sourceURL = normalizeText(body.sourceURL) || "";
    const sourcePlatform = detectPlatform(sourceURL);
    const { sourceText, videoPlayURL, derivedTitle, derivedCreatorName, derivedCreatorURL, derivedThumbnailURL, derivedPostedAt, extractedEmail, scrapedMetadata, fetchStatus, fetchContentType, htmlLength } = sourceURL
      ? await extractSourceText(sourceURL, sourcePlatform)
      : {
        sourceText: "",
        derivedTitle: null,
        derivedCreatorName: null,
        derivedCreatorURL: null,
        derivedThumbnailURL: null,
        videoPlayURL: null,
        derivedPostedAt: null,
        extractedEmail: null,
        fetchStatus: null,
        fetchContentType: null,
        htmlLength: 0,
        scrapedMetadata: {},
      };

    const llmExtraction = await extractWithLLM({
      sourceURL,
      sourcePlatform,
      rawText: sourceText,
      metadata: scrapedMetadata,
    });

    const resolvedApplicationEmail = llmExtraction?.application_email ?? extractedEmail;
    const resolvedPostedAt = sanitizeDate(llmExtraction?.posted_date) ?? sanitizeDate(derivedPostedAt);
    const diagnostics = {
      fetch_status: fetchStatus,
      fetch_content_type: fetchContentType,
      html_length: htmlLength,
      source_text_length: sourceText.length,
      metadata_keys_with_values: Object.entries(scrapedMetadata).filter(([, value]) => Boolean(value)).map(([key]) => key),
      openai_enabled: Boolean(openAIAPIKey),
      llm_used: Boolean(llmExtraction),
      scraped_metadata: Object.fromEntries(
        Object.entries(scrapedMetadata).map(([k, v]) => [k, v ?? ""])
      ) as Record<string, string>,
    };

    console.log(JSON.stringify({
      event: "parse_shared_job_posting_diagnostics",
      source_url: sourceURL,
      source_platform: sourcePlatform,
      ...diagnostics,
      extracted_company: llmExtraction?.company ?? null,
      extracted_title: llmExtraction?.title ?? derivedTitle,
      extracted_location: llmExtraction?.location ?? guessLocation(sourceText),
      extracted_application_email: resolvedApplicationEmail,
      extracted_posted_date: resolvedPostedAt,
    }));

    const suggestion = {
      source_platform: sourcePlatform,
      source_url: sourceURL,
      source_creator_name: derivedCreatorName,
      source_creator_url: derivedCreatorURL,
      source_thumbnail_url: derivedThumbnailURL,
      source_caption: sourceText,
      source_caption_raw: sourceText,
      source_posted_at: resolvedPostedAt,
      source_apply_email_extracted: resolvedApplicationEmail,
      company: llmExtraction?.company ?? null,
      title: llmExtraction?.title ?? derivedTitle,
      location: llmExtraction?.location ?? guessLocation(sourceText),
      compensation: llmExtraction?.compensation ?? null,
      how_to_apply: llmExtraction?.how_to_apply ?? null,
      description: sourceText || null,
      application_email: resolvedApplicationEmail,
      video_play_url: videoPlayURL ?? null,
      diagnostics,
    };

    return new Response(JSON.stringify({ suggestion }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Unknown error" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
