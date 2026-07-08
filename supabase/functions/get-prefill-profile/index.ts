// Returns everything the WebView bridge needs to autofill an apply form.
//
// Response shape:
//   profile:    legacy flat bundle (firstName, email, etc.) — kept so older
//               iOS builds keep working.
//   canonical:  { <canon_key>: <value> } from candidate_field_history rows
//               with the `canon:` prefix. The bridge JS uses these for
//               cross-ATS label matching.
//   rawHistory: { <raw_label>: <value> } from candidate_field_history rows
//               without the prefix — verbatim label hits on a repeat visit
//               to the same ATS template.

import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";
import { CANON_PREFIX } from "../_shared/profile_fields.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    const userClient = createUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const admin = createAdminClient();

    const [
      { data: profile },
      { data: seekerProfile },
      { data: fieldHistory },
    ] = await Promise.all([
      admin.from("profiles").select("full_name, email").eq("id", user.id).maybeSingle(),
      admin
        .from("job_seeker_profiles")
        .select("linkedin_url, github_url, portfolio_url, city, phone")
        .eq("profile_id", user.id)
        .maybeSingle(),
      admin
        .from("candidate_field_history")
        .select("field_label, field_value")
        .eq("candidate_profile_id", user.id),
    ]);

    const canonical: Record<string, string> = {};
    const rawHistory: Record<string, string> = {};
    for (const row of fieldHistory ?? []) {
      const label = row.field_label?.trim();
      const value = row.field_value?.trim();
      if (!label || !value) continue;
      if (label.startsWith(CANON_PREFIX)) {
        canonical[label.slice(CANON_PREFIX.length)] = value;
      } else {
        rawHistory[label] = value;
      }
    }

    // Build legacy `profile` bundle. Prefer canonical values (newest-wins via
    // parser + capture), fall back to the older profile / job_seeker_profile
    // columns so a fresh user with no application history still gets a prefill.
    const nameParts = (profile?.full_name ?? "").trim().split(/\s+/);
    const firstName = canonical.first_name || nameParts[0] || "";
    const lastName  = canonical.last_name  || nameParts.slice(1).join(" ");

    const prefillProfile = {
      firstName,
      lastName,
      fullName:     profile?.full_name ?? `${firstName} ${lastName}`.trim(),
      email:        canonical.email         || user.email                  || profile?.email                  || "",
      phone:        canonical.phone         || seekerProfile?.phone        || "",
      city:         canonical.city          || seekerProfile?.city         || "",
      linkedInUrl:  canonical.linkedin_url  || seekerProfile?.linkedin_url || "",
      githubUrl:    canonical.github_url    || seekerProfile?.github_url   || "",
      portfolioUrl: canonical.portfolio_url || seekerProfile?.portfolio_url|| "",
    };

    return jsonResponse({
      profile: prefillProfile,
      canonical,
      rawHistory,
      // Older clients read `fieldHistory` — keep it as the union for back-compat.
      fieldHistory: { ...rawHistory, ...prefixWithCanon(canonical) },
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Unknown error" },
      400,
    );
  }
});

function prefixWithCanon(canonical: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(canonical)) {
    out[`${CANON_PREFIX}${key}`] = value;
  }
  return out;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
