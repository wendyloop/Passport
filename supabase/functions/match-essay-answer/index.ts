// Returns the candidate's prior answer most semantically similar to a given
// question, or null if nothing clears the similarity floor.
//
// Called by the iOS WebView bridge once per textarea-style question on apply
// form load. The bridge surfaces the match as a "Use prior answer?" suggestion
// rather than auto-filling — essays carry voice and company-specific framing.
//
// Cheap: one ~$0.00002 embedding call + one vector index lookup per question.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";
import { embedText, toPgVector } from "../_shared/openai_embeddings.ts";

const DEFAULT_MIN_SIMILARITY = 0.85;

type RequestBody = {
  question: string;
  minSimilarity?: number;
};

type Match = {
  question: string;
  answer: string;
  similarity: number;
  sourceJobId: string | null;
  updatedAt: string;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    const userClient = createUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return jsonResponse({ error: "Unauthorized" }, 401);

    const body = (await request.json().catch(() => ({}))) as RequestBody;
    const question = body.question?.trim();
    if (!question) return jsonResponse({ error: "question is required" }, 400);

    const minScore = clamp(body.minSimilarity ?? DEFAULT_MIN_SIMILARITY, 0, 1);

    const embedding = await embedText(question);

    const admin = createAdminClient();
    const { data, error } = await admin.rpc("match_candidate_essay", {
      p_profile_id: user.id,
      p_embedding: toPgVector(embedding),
      p_min_score: minScore,
      p_limit: 1,
    });
    if (error) throw error;

    const row = Array.isArray(data) ? data[0] : null;
    const match: Match | null = row
      ? {
          question:    row.question_text,
          answer:      row.answer,
          similarity:  row.similarity,
          sourceJobId: row.source_job_id ?? null,
          updatedAt:   row.updated_at,
        }
      : null;

    return jsonResponse({ match });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Unknown error" },
      400,
    );
  }
});

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n));
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
