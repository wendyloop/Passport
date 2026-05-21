import { corsHeaders } from "../_shared/cors.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";

function pathFromPublicURL(url: string, bucket: string) {
  const marker = `/object/public/${bucket}/`;
  const index = url.indexOf(marker);
  if (index < 0) return null;
  return decodeURIComponent(url.slice(index + marker.length));
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

    const [
      { data: resumes, error: resumesError },
      { data: candidateVideos, error: candidateVideosError },
      { data: jobs, error: jobsError },
    ] = await Promise.all([
      adminClient
        .from("resume_uploads")
        .select("file_path")
        .eq("profile_id", user.id),
      adminClient
        .from("candidate_videos")
        .select("public_url")
        .eq("profile_id", user.id),
      adminClient
        .from("jobs")
        .select("video_url")
        .eq("posted_by_profile_id", user.id),
    ]);

    if (resumesError) throw resumesError;
    if (candidateVideosError) throw candidateVideosError;
    if (jobsError) throw jobsError;

    const resumePaths = (resumes ?? [])
      .map((row) => row.file_path?.trim())
      .filter((value): value is string => Boolean(value));
    const candidateVideoPaths = (candidateVideos ?? [])
      .map((row) => row.public_url ? pathFromPublicURL(row.public_url, "videos") : null)
      .filter((value): value is string => Boolean(value));
    const jobVideoPaths = (jobs ?? [])
      .map((row) => row.video_url ? pathFromPublicURL(row.video_url, "job-videos") : null)
      .filter((value): value is string => Boolean(value));

    if (resumePaths.length > 0) {
      await adminClient.storage.from("resumes").remove(resumePaths);
    }
    if (candidateVideoPaths.length > 0) {
      await adminClient.storage.from("videos").remove(candidateVideoPaths);
    }
    if (jobVideoPaths.length > 0) {
      await adminClient.storage.from("job-videos").remove(jobVideoPaths);
    }

    const { error: deleteError } = await adminClient.auth.admin.deleteUser(user.id);
    if (deleteError) throw deleteError;

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : "Unknown error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
