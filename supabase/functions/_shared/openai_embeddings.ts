// Thin wrapper around OpenAI's embeddings endpoint. Used by
// store-application-fields and match-essay-answer to embed essay questions
// before writing/searching candidate_essay_answers.

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const EMBEDDING_MODEL = "text-embedding-3-small";
const EMBEDDING_DIMS = 1536;
const TIMEOUT_MS = 10_000;

export function normalizeQuestion(text: string): string {
  return text
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ")
    // Strip trailing punctuation that varies across ATS templates ("Why us?" vs "Why us!?").
    .replace(/[!?.;:,\s]+$/g, "");
}

export async function embedText(text: string): Promise<number[]> {
  if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY not configured");
  const trimmed = text.trim();
  if (!trimmed) throw new Error("empty text");

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: EMBEDDING_MODEL,
        input: trimmed.slice(0, 8000),
      }),
      signal: controller.signal,
    });
    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new Error(`OpenAI embeddings HTTP ${response.status}: ${body.slice(0, 200)}`);
    }
    const payload = await response.json();
    const vec = payload?.data?.[0]?.embedding;
    if (!Array.isArray(vec) || vec.length !== EMBEDDING_DIMS) {
      throw new Error(`unexpected embedding shape (length=${Array.isArray(vec) ? vec.length : "n/a"})`);
    }
    return vec as number[];
  } finally {
    clearTimeout(timer);
  }
}

// Batch variant for pipeline work (embed-jobs): one API call per chunk of
// 100 inputs instead of one per text. Order-preserving via the returned
// index field.
export async function embedTexts(texts: string[]): Promise<number[][]> {
  if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY not configured");
  const results: number[][] = new Array(texts.length);
  for (let offset = 0; offset < texts.length; offset += 100) {
    const chunk = texts.slice(offset, offset + 100).map((t) => t.trim().slice(0, 8000) || " ");
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 30_000);
    try {
      const response = await fetch("https://api.openai.com/v1/embeddings", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${OPENAI_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ model: EMBEDDING_MODEL, input: chunk }),
        signal: controller.signal,
      });
      if (!response.ok) {
        const body = await response.text().catch(() => "");
        throw new Error(`OpenAI embeddings HTTP ${response.status}: ${body.slice(0, 200)}`);
      }
      const payload = await response.json();
      for (const item of payload?.data ?? []) {
        const vec = item?.embedding;
        if (!Array.isArray(vec) || vec.length !== EMBEDDING_DIMS || typeof item.index !== "number") {
          throw new Error("unexpected batch embedding shape");
        }
        results[offset + item.index] = vec as number[];
      }
    } finally {
      clearTimeout(timer);
    }
  }
  if (results.some((r) => !Array.isArray(r))) throw new Error("embedding batch returned gaps");
  return results;
}

// pgvector accepts a bracketed string literal — '[0.1, 0.2, ...]'.
export function toPgVector(values: number[]): string {
  return `[${values.join(",")}]`;
}
