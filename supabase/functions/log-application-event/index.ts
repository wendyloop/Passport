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

    // A submitted event = the candidate finished an application in the ATS
    // web portal, so record it on the Applications page like any other
    // apply. Failure-isolated: the funnel event is already stored, and a
    // bookkeeping problem must not fail this request. If a row already
    // exists from a founder pitch, upgrade it in place (keeping
    // founder_pitched_at); a row that is already an ats_apply stays as the
    // dup guard intends.
    if (body.eventType === "submitted") {
      try {
        const [{ data: job }, { data: profile }] = await Promise.all([
          adminClient
            .from("jobs")
            .select("id, employer_profile_id, title, company_name, location, application_email")
            .eq("id", body.jobId)
            .maybeSingle(),
          adminClient
            .from("profiles")
            .select("full_name, headline")
            .eq("id", user.id)
            .maybeSingle(),
        ]);

        if (job) {
          const applicationRow = {
            job_id: job.id,
            employer_profile_id: job.employer_profile_id ?? null,
            candidate_profile_id: user.id,
            application_kind: "ats_apply",
            job_title: job.title ?? "Open role",
            company_name: job.company_name ?? "the company",
            job_location: job.location ?? null,
            application_email: job.application_email ?? null,
            candidate_name: profile?.full_name ?? "A scout22 candidate",
            candidate_headline: profile?.headline ?? null,
            // No application email exists on the portal path — the ATS
            // received the submission directly.
            email_delivery_status: "not_applicable",
          };
          const { error: appError } = await adminClient
            .from("job_applications")
            .insert(applicationRow);
          if (appError?.code === "23505") {
            await adminClient
              .from("job_applications")
              .update(applicationRow)
              .eq("job_id", job.id)
              .eq("candidate_profile_id", user.id)
              .eq("application_kind", "founder_pitch");
          } else if (appError) {
            console.error(JSON.stringify({
              event: "portal_application_record_failed",
              job_id: job.id,
              error: appError.message,
            }));
          }
        }
      } catch (error) {
        console.error(JSON.stringify({
          event: "portal_application_record_threw",
          job_id: body.jobId,
          error: (error as Error).message,
        }));
      }
    }

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
