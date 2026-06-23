// Retryable fetch with per-call timeout.
//
// Spec FR-3.2: transient 5xx + timeouts retry up to 3x with backoff.
// 4xx responses are returned without retry (caller decides what to do).

const DEFAULT_TIMEOUT_MS = 10_000;
const DEFAULT_RETRIES = 3;
const DEFAULT_BACKOFF_BASE_MS = 500;

const DEFAULT_USER_AGENT =
  "PitchJobBot/1.0 (+https://jobtok.app/bots) supabase-edge-function";

export type FetchWithRetryOptions = RequestInit & {
  timeoutMs?: number;
  retries?: number;
  backoffBaseMs?: number;
};

export class HTTPError extends Error {
  constructor(public status: number, public body: string, url: string) {
    super(`HTTP ${status} for ${url}: ${body.slice(0, 200)}`);
    this.name = "HTTPError";
  }
}

export async function fetchWithRetry(
  url: string,
  options: FetchWithRetryOptions = {},
): Promise<Response> {
  const {
    timeoutMs = DEFAULT_TIMEOUT_MS,
    retries = DEFAULT_RETRIES,
    backoffBaseMs = DEFAULT_BACKOFF_BASE_MS,
    headers,
    ...init
  } = options;

  const mergedHeaders: HeadersInit = {
    "user-agent": DEFAULT_USER_AGENT,
    accept: "application/json",
    ...(headers ?? {}),
  };

  let lastError: unknown;

  for (let attempt = 0; attempt <= retries; attempt++) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(url, {
        ...init,
        headers: mergedHeaders,
        signal: controller.signal,
      });

      // Retry only on 5xx + 429. 4xx returns immediately.
      if (response.status >= 500 || response.status === 429) {
        if (attempt < retries) {
          await sleep(backoffMs(attempt, backoffBaseMs));
          continue;
        }
      }

      return response;
    } catch (error) {
      lastError = error;
      if (attempt < retries) {
        await sleep(backoffMs(attempt, backoffBaseMs));
        continue;
      }
      throw error;
    } finally {
      clearTimeout(timeoutId);
    }
  }

  throw lastError ?? new Error(`fetchWithRetry exhausted retries for ${url}`);
}

export async function fetchJSON<T>(
  url: string,
  options: FetchWithRetryOptions = {},
): Promise<T> {
  const response = await fetchWithRetry(url, options);
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new HTTPError(response.status, body, url);
  }
  return await response.json() as T;
}

function backoffMs(attempt: number, base: number) {
  // 500ms, 1s, 2s with ±25% jitter
  const exp = base * 2 ** attempt;
  const jitter = exp * 0.25 * (Math.random() * 2 - 1);
  return Math.max(50, Math.round(exp + jitter));
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Process N items with at most `concurrency` in flight at a time.
export async function pMap<T, R>(
  items: T[],
  concurrency: number,
  fn: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let cursor = 0;

  const workers = Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    while (true) {
      const index = cursor++;
      if (index >= items.length) return;
      results[index] = await fn(items[index], index);
    }
  });

  await Promise.all(workers);
  return results;
}
