// P1: employer-side signed resume download. The MVP emailed a 7-day signed
// URL at apply time; the portal itself only showed the filename. This
// returns a short-lived signed URL, authorized by application ownership —
// the resumes bucket stays private.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";
import { jsonError, jsonResponse } from "../_shared/http.ts";

const SIGNED_URL_TTL_SECONDS = 600; // 10 minutes — view-now, not keep-forever

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    const userClient = createUserClient(authHeader);
    const admin = createAdminClient();
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return jsonError("Unauthorized", 401);

    const body = (await request.json().catch(() => ({}))) as { applicationId?: string };
    const applicationId = body.applicationId?.trim();
    if (!applicationId) return jsonError("applicationId is required", 400);

    const { data: application, error } = await admin
      .from("job_applications")
      .select("id, employer_profile_id, resume_file_path")
      .eq("id", applicationId)
      .maybeSingle();
    if (error) return jsonError(error.message);
    if (!application) return jsonError("Application not found", 404);
    // Ownership is the authorization: only the employer this application
    // was submitted to can mint a resume link.
    if (application.employer_profile_id !== user.id) {
      return jsonError("Not your application", 403);
    }
    if (!application.resume_file_path) {
      return jsonError("No resume on this application", 404);
    }

    const { data: signed, error: signError } = await admin.storage
      .from("resumes")
      .createSignedUrl(application.resume_file_path, SIGNED_URL_TTL_SECONDS);
    if (signError || !signed?.signedUrl) {
      return jsonError(signError?.message ?? "Could not sign resume URL");
    }

    return jsonResponse({ url: signed.signedUrl, expiresIn: SIGNED_URL_TTL_SECONDS });
  } catch (error) {
    return jsonError((error as Error).message);
  }
});
