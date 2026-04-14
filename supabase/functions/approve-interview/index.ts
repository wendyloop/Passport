import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    const userClient = createUserClient(authHeader);
    const adminClient = createAdminClient();
    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await request.json();
    const { data, error } = await userClient.rpc("respond_to_interview_request", {
      p_request_id: body.requestId,
      p_approved: Boolean(body.approved),
    });

    if (error) {
      throw error;
    }

    if (body.approved) {
      const { data: connection } = await adminClient
        .from("calendar_connections")
        .select("provider, access_token, refresh_token")
        .eq("profile_id", user.id)
        .maybeSingle();

      if (!connection?.access_token) {
        await adminClient.from("notifications").insert({
          profile_id: user.id,
          type: "calendar_sync_needed",
          title: "Connect Google Calendar",
          body: "Approve flow completed, but calendar tokens are missing for automatic event creation.",
          metadata: {
            request_id: body.requestId,
          },
        });
      }
    }

    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Unknown error" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
