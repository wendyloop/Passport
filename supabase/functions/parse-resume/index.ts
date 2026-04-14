import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";

function inferSchool(resumeText: string) {
  const lines = resumeText
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  return (
    lines.find((line) =>
      /(university|college|institute|school of)/i.test(line),
    ) ?? null
  );
}

function inferEmployers(resumeText: string) {
  return resumeText
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => /experience|worked at|intern at|engineer at/i.test(line))
    .slice(0, 5)
    .map((line) => line.replace(/^(experience|worked at|intern at|engineer at)\s*:?\s*/i, ""));
}

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
    const resumeId = body.resumeId as string;
    const rawText = (body.rawText as string | undefined)?.trim();

    const school = rawText ? inferSchool(rawText) : null;
    const employers = rawText ? inferEmployers(rawText) : [];

    const status = rawText ? "parsed" : "pending_manual_review";

    const { data: resume, error: resumeError } = await adminClient
      .from("resume_uploads")
      .update({
        parse_status: status,
        parsed_school_name: school,
        parsed_employers: employers,
      })
      .eq("id", resumeId)
      .eq("profile_id", user.id)
      .select("profile_id")
      .single();

    if (resumeError) {
      throw resumeError;
    }

    if (school || employers.length) {
      await adminClient.from("job_seeker_profiles").upsert({
        profile_id: resume.profile_id,
        school_name: school,
      });

      if (employers.length) {
        await adminClient
          .from("job_seeker_employers")
          .delete()
          .eq("profile_id", resume.profile_id);

        await adminClient.from("job_seeker_employers").insert(
          employers.map((employerName, index) => ({
            profile_id: resume.profile_id,
            employer_name: employerName,
            sort_order: index + 1,
          })),
        );
      }
    }

    return new Response(
      JSON.stringify({
        resumeId,
        parseStatus: status,
        school,
        employers,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
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
