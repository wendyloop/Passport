import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";

type AvailabilityPayload = {
  slots: Array<{
    startAt: string;
    endAt: string;
    source?: string;
  }>;
};

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

    const body = (await request.json()) as AvailabilityPayload;
    const slots = body.slots ?? [];

    if (!slots.length) {
      return new Response(JSON.stringify({ inserted: 0 }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { error } = await adminClient.from("availability_slots").insert(
      slots.map((slot) => ({
        employer_profile_id: user.id,
        start_at: slot.startAt,
        end_at: slot.endAt,
        source: slot.source ?? "google",
      })),
    );

    if (error) {
      throw error;
    }

    await adminClient.from("employer_profiles").update({
      calendar_connected: true,
    }).eq("profile_id", user.id);

    return new Response(JSON.stringify({ inserted: slots.length }), {
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
