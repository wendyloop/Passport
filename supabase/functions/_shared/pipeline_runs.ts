// DB-P1-9: persist one row per pipeline run so outcomes outlive function
// logs. Recording is fail-open — a broken insert must never break the
// pipeline it observes.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";

export type PipelineRunRow = {
  function_name: string;
  started_at: string;
  duration_ms: number;
  summary: Record<string, unknown>;
  error_count: number;
};

export function buildPipelineRunRow(
  functionName: string,
  startedAtMs: number,
  summary: Record<string, unknown>,
  errorCount: number,
  nowMs: number = Date.now(),
): PipelineRunRow {
  return {
    function_name: functionName,
    started_at: new Date(startedAtMs).toISOString(),
    duration_ms: Math.max(0, nowMs - startedAtMs),
    summary,
    error_count: errorCount,
  };
}

export async function recordPipelineRun(
  admin: SupabaseClient,
  functionName: string,
  startedAtMs: number,
  summary: Record<string, unknown>,
  errorCount: number,
): Promise<void> {
  try {
    const { error } = await admin
      .from("pipeline_runs")
      .insert(buildPipelineRunRow(functionName, startedAtMs, summary, errorCount));
    if (error) {
      console.error(`pipeline_runs insert failed for ${functionName}: ${error.message}`);
    }
  } catch (error) {
    console.error(`pipeline_runs insert threw for ${functionName}:`, error);
  }
}
