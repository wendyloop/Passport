// Shared HTTP helpers for edge functions: JSON responses with CORS baked in,
// a timeout-guarded JSON POST, and re-exports of the retrying fetch helpers.

import { corsHeaders } from "./cors.ts";

export { fetchJSON, fetchWithRetry, HTTPError, pMap } from "./ats/http.ts";

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function jsonError(message: string, status = 500): Response {
  return jsonResponse({ error: message }, status);
}

const DEFAULT_POST_TIMEOUT_MS = 15_000;

export async function postJSON<T>(
  url: string,
  body: unknown,
  timeoutMs = DEFAULT_POST_TIMEOUT_MS,
): Promise<T> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new Error(`HTTP ${response.status} for ${url}: ${text.slice(0, 200)}`);
    }
    return (await response.json()) as T;
  } finally {
    clearTimeout(timer);
  }
}
