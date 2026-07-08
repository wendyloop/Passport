// Shared guard for cron-invoked functions. Fail closed: an unset secret must
// never leave an endpoint open — these functions trigger crawls, LLM spend,
// and service-role DB writes.

import { jsonError } from "./http.ts";

const PITCH_CRON_SECRET = Deno.env.get("PITCH_CRON_SECRET") ?? "";

// Returns a 401 response to short-circuit with, or null when authorized.
export function requireCronSecret(request: Request): Response | null {
  const provided = request.headers.get("x-pitch-cron-secret");
  if (!PITCH_CRON_SECRET || provided !== PITCH_CRON_SECRET) {
    return jsonError("unauthorized", 401);
  }
  return null;
}
