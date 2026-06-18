import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";

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

    const adminClient = createAdminClient();

    const [
      { data: profile },
      { data: seekerProfile },
      { data: fieldHistory },
    ] = await Promise.all([
      adminClient
        .from("profiles")
        .select("full_name, email")
        .eq("id", user.id)
        .maybeSingle(),
      adminClient
        .from("job_seeker_profiles")
        .select("linkedin_url, github_url, portfolio_url, city, phone")
        .eq("profile_id", user.id)
        .maybeSingle(),
      adminClient
        .from("candidate_field_history")
        .select("field_label, field_value")
        .eq("candidate_profile_id", user.id),
    ]);

    const nameParts = (profile?.full_name ?? "").trim().split(/\s+/);
    const firstName = nameParts[0] ?? "";
    const lastName = nameParts.slice(1).join(" ");

    // Combine profile fields + historical ATS field captures
    const history: Record<string, string> = {};
    for (const row of fieldHistory ?? []) {
      if (row.field_label && row.field_value) {
        history[row.field_label] = row.field_value;
      }
    }

    const prefillProfile = {
      firstName,
      lastName,
      fullName: profile?.full_name ?? "",
      email: user.email ?? profile?.email ?? "",
      phone: seekerProfile?.phone ?? "",
      city: seekerProfile?.city ?? "",
      linkedInUrl: seekerProfile?.linkedin_url ?? "",
      githubUrl: seekerProfile?.github_url ?? "",
      portfolioUrl: seekerProfile?.portfolio_url ?? "",
    };

    return new Response(JSON.stringify({ profile: prefillProfile, fieldHistory: history }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Unknown error" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
