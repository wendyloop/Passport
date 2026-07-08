// Shared OpenAI /v1/responses helpers: output-text extraction (the response
// shape varies between output_text and the output[].content[].text form) and
// a structured-output call wrapper used by carousel generation, resume
// parsing, and contact scraping.

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const DEFAULT_MODEL = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";
const DEFAULT_TIMEOUT_MS = 30_000;

export function extractOutputText(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const p = payload as Record<string, unknown>;
  if (typeof p.output_text === "string" && p.output_text.trim()) return p.output_text;
  const output = Array.isArray(p.output) ? p.output : [];
  for (const item of output) {
    if (!item || typeof item !== "object") continue;
    const content = (item as Record<string, unknown>).content;
    if (!Array.isArray(content)) continue;
    for (const c of content) {
      if (c && typeof c === "object" && typeof (c as Record<string, unknown>).text === "string") {
        const text = ((c as Record<string, unknown>).text as string).trim();
        if (text) return text;
      }
    }
  }
  return null;
}

export type StructuredCallParams = {
  systemPrompt: string;
  userPrompt: string;
  schemaName: string;
  // JSON schema object for the response body (additionalProperties: false etc.
  // is the caller's responsibility — it is passed through verbatim).
  schema: Record<string, unknown>;
  model?: string;
  maxOutputTokens?: number;
  timeoutMs?: number;
};

// Calls /v1/responses with a strict json_schema format and returns the parsed
// output. Throws on HTTP errors, missing output, and invalid JSON.
export async function callStructured<T>(params: StructuredCallParams): Promise<T> {
  if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY not set");

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), params.timeoutMs ?? DEFAULT_TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: params.model ?? DEFAULT_MODEL,
        input: [
          { role: "system", content: [{ type: "input_text", text: params.systemPrompt }] },
          { role: "user", content: [{ type: "input_text", text: params.userPrompt }] },
        ],
        max_output_tokens: params.maxOutputTokens ?? 800,
        text: {
          format: {
            type: "json_schema",
            name: params.schemaName,
            strict: true,
            schema: params.schema,
          },
        },
      }),
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }

  if (!response.ok) {
    const text = await response.text().catch(() => "");
    throw new Error(`OpenAI HTTP ${response.status}: ${text.slice(0, 200)}`);
  }

  const payload = await response.json();
  const outputText = extractOutputText(payload);
  if (!outputText) throw new Error("OpenAI returned no output_text");
  return JSON.parse(outputText) as T;
}
