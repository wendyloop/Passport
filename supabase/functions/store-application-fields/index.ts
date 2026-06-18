import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";

type StoreFieldsRequest = {
  eventId: string;
  fields: Record<string, string>;
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

    const body = (await request.json().catch(() => ({}))) as StoreFieldsRequest;

    if (!body.eventId || !body.fields || typeof body.fields !== "object") {
      return new Response(JSON.stringify({ error: "eventId and fields are required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const adminClient = createAdminClient();

    // Verify event belongs to this user
    const { data: event, error: eventError } = await adminClient
      .from("application_events")
      .select("id, candidate_profile_id")
      .eq("id", body.eventId)
      .eq("candidate_profile_id", user.id)
      .maybeSingle();

    if (eventError) throw eventError;
    if (!event) {
      return new Response(JSON.stringify({ error: "Event not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const fieldEntries = Object.entries(body.fields).filter(([label, value]) =>
      label.trim() && value?.trim()
    );

    if (fieldEntries.length > 0) {
      const fieldRows = fieldEntries.map(([label, value]) => ({
        event_id: body.eventId,
        candidate_profile_id: user.id,
        field_label: label.trim(),
        field_value: value.trim(),
      }));

      const { error: fieldsError } = await adminClient
        .from("application_fields")
        .insert(fieldRows);

      if (fieldsError) throw fieldsError;

      // Upsert into candidate_field_history — update if newer
      const historyRows = fieldEntries.map(([label, value]) => ({
        candidate_profile_id: user.id,
        field_label: label.trim(),
        field_value: value.trim(),
        updated_at: new Date().toISOString(),
      }));

      const { error: historyError } = await adminClient
        .from("candidate_field_history")
        .upsert(historyRows, { onConflict: "candidate_profile_id,field_label" });

      if (historyError) throw historyError;
    }

    return new Response(JSON.stringify({ stored: fieldEntries.length }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Unknown error" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
