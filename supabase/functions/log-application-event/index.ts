// TODO(deferred): P3 — employer job-level analytics (SHELVED until the
// employer side launches). When built, it aggregates on top of the events
// this function records (opened/submitted) plus new impression/save events.
// Deliberately not implemented today. See docs/DEFERRED_WORK.md.
import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";

type LogEventRequest = {
  jobId: string;
  applicationId?: string | null;
  eventType: "opened" | "submitted";
  atsType?: string | null;
  applyUrl?: string | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    const userClient = createUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = (await request.json().catch(() => ({}))) as LogEventRequest;

    if (!body.jobId || !body.eventType) {
      return new Response(JSON.stringify({ error: "jobId and eventType are required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const adminClient = createAdminClient();

    const { data: event, error: insertError } = await adminClient
      .from("application_events")
      .insert({
        job_id: body.jobId,
        candidate_profile_id: user.id,
        application_id: body.applicationId ?? null,
        event_type: body.eventType,
        ats_type: body.atsType ?? null,
        apply_url: body.applyUrl ?? null,
      })
      .select("id")
      .single();

    if (insertError) throw insertError;

    return new Response(JSON.stringify({ id: event.id }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Unknown error" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
