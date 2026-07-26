// Cron: embed active/published jobs for resume↔job matching (M-E).
// Batches through get_jobs_needing_embedding (never-embedded first, then
// content-updated rows); one OpenAI call per 100 jobs via embedTexts.
// Auth: x-pitch-cron-secret (fail-closed) — pg_net cron calls carry no JWT,
// so config.toml carries [functions.embed-jobs] verify_jwt = false.

import { requireCronSecret } from "../_shared/cron_auth.ts";
import { createAdminClient } from "../_shared/client.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { embedTexts, toPgVector } from "../_shared/openai_embeddings.ts";
import { buildJobEmbeddingText } from "../_shared/matching.ts";
import { recordPipelineRun } from "../_shared/pipeline_runs.ts";

const BATCH_LIMIT = 300;

type QueueRow = {
  job_id: string;
  title: string | null;
  job_function: string | null;
  company_name: string | null;
  company_stage: string | null;
  compensation_min_annual: number | null;
  compensation_max_annual: number | null;
  description: string | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const denied = requireCronSecret(request);
  if (denied) return denied;

  const startedAt = new Date();
  const admin = createAdminClient();
  let embedded = 0;
  let errored = 0;

  try {
    const { data, error } = await admin.rpc("get_jobs_needing_embedding", { p_limit: BATCH_LIMIT });
    if (error) throw error;
    const queue = (data ?? []) as QueueRow[];

    if (queue.length > 0) {
      const built = queue.map((row) =>
        buildJobEmbeddingText({
          title: row.title,
          job_function: row.job_function,
          company_name: row.company_name,
          company_stage: row.company_stage,
          compensation_min_annual: row.compensation_min_annual,
          compensation_max_annual: row.compensation_max_annual,
          description: row.description,
        })
      );
      const vectors = await embedTexts(built.map((b) => b.text));
      const nowISO = new Date().toISOString();
      const rows = queue.map((row, i) => ({
        job_id: row.job_id,
        embedding: toPgVector(vectors[i]),
        quality: built[i].quality,
        embedded_at: nowISO,
      }));

      for (let offset = 0; offset < rows.length; offset += 100) {
        const { error: upsertError } = await admin
          .from("job_embeddings")
          .upsert(rows.slice(offset, offset + 100), { onConflict: "job_id" });
        if (upsertError) {
          errored += 1;
          console.error(JSON.stringify({ event: "embed_jobs_upsert_error", error: upsertError.message }));
        } else {
          embedded += Math.min(100, rows.length - offset);
        }
      }
    }

    const summary = {
      event: "embed_jobs_run",
      queued: queue.length,
      embedded,
      errored,
      duration_ms: Date.now() - startedAt.getTime(),
    };
    console.log(JSON.stringify(summary));
    await recordPipelineRun(admin, "embed-jobs", startedAt, summary, errored);

    return new Response(JSON.stringify(summary), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    const summary = {
      event: "embed_jobs_run",
      embedded,
      errored: errored + 1,
      error: (error as Error).message,
      duration_ms: Date.now() - startedAt.getTime(),
    };
    console.error(JSON.stringify(summary));
    await recordPipelineRun(admin, "embed-jobs", startedAt, summary, errored + 1);
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
