// F10c: public share landing page for a job. Renders rich OG/Twitter
// preview tags (what iMessage/WhatsApp show) plus a minimal page with
// "open in app" (custom scheme) and a get-the-app CTA.
//
// Public by design (verify_jwt = false): reads happen server-side with the
// service role, so nothing here relies on anon RLS access, and only
// published+active jobs render — everything else 404s.
//
// FILL-IN LATER (tracked in docs/DEFERRED_WORK.md, F10b):
//   - APP_STORE_URL secret → real App Store / public TestFlight link.
//   - Once tryscout22.com hosts this page + the AASA file, switch
//     ShareConfig.shareBaseURL in the app and add Associated Domains for
//     true universal links.

import { createAdminClient } from "../_shared/client.ts";
import { escapeHtml } from "../_shared/email.ts";

const APP_STORE_URL = Deno.env.get("APP_STORE_URL") ?? "";
const APP_SCHEME_URL = (jobId: string) => `jobtok://job/${jobId}`;

Deno.serve(async (request) => {
  if (request.method !== "GET") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Path shape: /job-share/{jobId} (function name is the first segment).
  const segments = new URL(request.url).pathname.split("/").filter(Boolean);
  const jobId = segments[segments.length - 1];
  if (!jobId || jobId === "job-share" || !/^[0-9a-f-]{36}$/i.test(jobId)) {
    return new Response("Not found", { status: 404 });
  }

  const admin = createAdminClient();
  const { data: job } = await admin
    .from("jobs")
    .select("id, title, company_name, location, compensation_text, compensation_min_annual, compensation_max_annual, is_published, is_active, company:companies(logo_url)")
    .eq("id", jobId)
    .maybeSingle();

  if (!job || !job.is_published || !job.is_active) {
    return new Response("This job is no longer available.", { status: 404 });
  }

  const title = `${job.title ?? "Open role"} @ ${job.company_name ?? "a startup"}`;
  const comp = compDisplay(job);
  const descriptionBits = [comp, job.location].filter(Boolean);
  const description = descriptionBits.length > 0
    ? `${descriptionBits.join(" · ")} — found on scout22`
    : "Found on scout22 — startup jobs you can pitch the founder for.";
  const company = job.company as { logo_url?: string | null } | null;
  const logo = company?.logo_url ?? null;

  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)} — scout22</title>
  <meta property="og:title" content="${escapeHtml(title)}">
  <meta property="og:description" content="${escapeHtml(description)}">
  <meta property="og:site_name" content="scout22">
  <meta property="og:type" content="website">
  ${logo ? `<meta property="og:image" content="${escapeHtml(logo)}">` : ""}
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="${escapeHtml(title)}">
  <meta name="twitter:description" content="${escapeHtml(description)}">
  <style>
    body { font-family: -apple-system, system-ui, sans-serif; background: #0b0b0f; color: #fff;
           display: flex; min-height: 100vh; align-items: center; justify-content: center; margin: 0; }
    .card { max-width: 420px; padding: 32px 24px; text-align: center; }
    .logo { width: 72px; height: 72px; border-radius: 18px; object-fit: contain; background: #1c1c24; }
    h1 { font-size: 24px; margin: 16px 0 4px; }
    p { color: #9a9aa5; margin: 4px 0 24px; }
    a.btn { display: block; padding: 14px 20px; border-radius: 14px; margin: 10px 0;
            font-weight: 700; text-decoration: none; }
    .primary { background: #c8ff4d; color: #000; }
    .secondary { background: #1c1c24; color: #fff; }
    .brand { margin-top: 28px; color: #5c5c66; font-size: 13px; }
  </style>
</head>
<body>
  <div class="card">
    ${logo ? `<img class="logo" src="${escapeHtml(logo)}" alt="">` : ""}
    <h1>${escapeHtml(title)}</h1>
    <p>${escapeHtml(descriptionBits.join(" · "))}</p>
    <a class="btn primary" href="${escapeHtml(APP_SCHEME_URL(job.id))}">Open in scout22</a>
    ${
    APP_STORE_URL
      ? `<a class="btn secondary" href="${escapeHtml(APP_STORE_URL)}">Get the app</a>`
      : `<span class="btn secondary">App launching soon — check back!</span>`
  }
    <div class="brand">scout22 — pitch the founder, not the ATS</div>
  </div>
</body>
</html>`;

  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=300",
    },
  });
});

function compDisplay(job: {
  compensation_text: string | null;
  compensation_min_annual: number | null;
  compensation_max_annual: number | null;
}): string | null {
  if (job.compensation_text) return job.compensation_text;
  const fmt = (n: number) => `$${Math.round(n / 1000)}k`;
  if (job.compensation_min_annual && job.compensation_max_annual) {
    return `${fmt(job.compensation_min_annual)}–${fmt(job.compensation_max_annual)}`;
  }
  if (job.compensation_min_annual) return `from ${fmt(job.compensation_min_annual)}`;
  if (job.compensation_max_annual) return `up to ${fmt(job.compensation_max_annual)}`;
  return null;
}
