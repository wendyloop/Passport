// Given an apply / careers URL discovered on a board, resolve the ATS
// provider, the company's token on that ATS, and the provider's stable
// job id when extractable.
//
// Returns null when the URL does not match a supported ATS. Companies with
// null resolution are stored with ats_type = null; jobs ingested via
// unrecognized URLs fall back to URL-as-dedup-key and remain present in
// the feed without ATS-side description enrichment.

import type { ATSType } from "./models.ts";

export type ATSResolution = {
  ats_type: ATSType;
  ats_token: string;
  // Provider's own job id parsed from the URL when extractable (e.g.
  // greenhouse jobs/12345). Some boards expose tracking-decorated URLs
  // (?gh_src=...) for the same job — extracting the id makes dedup_key
  // stable across those variants.
  ats_external_id: string | null;
};

type Matcher = (url: URL) => ATSResolution | null;

const matchers: Matcher[] = [
  // Greenhouse:
  //   https://boards.greenhouse.io/{token}
  //   https://boards.greenhouse.io/{token}/jobs/123
  //   https://job-boards.greenhouse.io/{token}/jobs/123
  //   https://{token}.greenhouse.io
  (url) => {
    const host = url.hostname.toLowerCase();
    if (host === "boards.greenhouse.io" || host === "job-boards.greenhouse.io") {
      const parts = pathSegments(url);
      const token = parts[0];
      if (!token) return null;
      // parts[1] === "jobs", parts[2] === id (when present)
      const id = parts[1] === "jobs" ? (parts[2] ?? null) : null;
      return { ats_type: "greenhouse", ats_token: token, ats_external_id: id };
    }
    if (host.endsWith(".greenhouse.io")) {
      const subdomain = host.slice(0, -".greenhouse.io".length);
      if (subdomain && subdomain !== "boards" && subdomain !== "job-boards" && subdomain !== "api") {
        const parts = pathSegments(url);
        const id = parts[0] === "jobs" ? (parts[1] ?? null) : null;
        return { ats_type: "greenhouse", ats_token: subdomain, ats_external_id: id };
      }
    }
    return null;
  },

  // Lever:
  //   https://jobs.lever.co/{token}
  //   https://jobs.lever.co/{token}/{posting-uuid}
  (url) => {
    const host = url.hostname.toLowerCase();
    if (host === "jobs.lever.co") {
      const parts = pathSegments(url);
      const token = parts[0];
      if (!token) return null;
      return { ats_type: "lever", ats_token: token, ats_external_id: parts[1] ?? null };
    }
    return null;
  },

  // Ashby:
  //   https://jobs.ashbyhq.com/{token}
  //   https://jobs.ashbyhq.com/{token}/{posting-id}
  (url) => {
    const host = url.hostname.toLowerCase();
    if (host === "jobs.ashbyhq.com") {
      const parts = pathSegments(url);
      const token = parts[0];
      if (!token) return null;
      return { ats_type: "ashby", ats_token: token, ats_external_id: parts[1] ?? null };
    }
    return null;
  },

  // SmartRecruiters:
  //   https://jobs.smartrecruiters.com/{token}/{posting-id}
  //   https://careers.smartrecruiters.com/{token}/{posting-id}
  (url) => {
    const host = url.hostname.toLowerCase();
    if (
      host === "jobs.smartrecruiters.com" ||
      host === "careers.smartrecruiters.com" ||
      host === "smartrecruiters.com" ||
      host.endsWith(".smartrecruiters.com")
    ) {
      const parts = pathSegments(url);
      const token = parts[0];
      if (!token) return null;
      return { ats_type: "smartrecruiters", ats_token: token, ats_external_id: parts[1] ?? null };
    }
    return null;
  },

  // Recruitee:
  //   https://{token}.recruitee.com/o/{posting-slug}
  (url) => {
    const host = url.hostname.toLowerCase();
    if (host.endsWith(".recruitee.com")) {
      const subdomain = host.slice(0, -".recruitee.com".length);
      if (subdomain && subdomain !== "www") {
        const parts = pathSegments(url);
        const id = parts[0] === "o" ? (parts[1] ?? null) : null;
        return { ats_type: "recruitee", ats_token: subdomain, ats_external_id: id };
      }
    }
    return null;
  },
];

export function classifyApplyURL(rawURL: string | null | undefined): ATSResolution | null {
  if (!rawURL) return null;
  let url: URL;
  try {
    url = new URL(rawURL);
  } catch {
    return null;
  }
  for (const matcher of matchers) {
    const resolved = matcher(url);
    if (resolved) return resolved;
  }
  return null;
}

function pathSegments(url: URL): string[] {
  return url.pathname.split("/").filter(Boolean);
}

// Derive apply_flow from the apply URL host. ATS-hosted forms = ats_form;
// anything else (Workday, custom careers pages, mailto) = external_link.
// "message" is reserved for YC-style flows (not crawled in v1).
export function deriveApplyFlow(applyURL: string | null | undefined): "ats_form" | "external_link" | "message" {
  if (!applyURL) return "external_link";
  const resolved = classifyApplyURL(applyURL);
  return resolved ? "ats_form" : "external_link";
}

// Stable dedup key for a board-ingested job: prefer ATS coordinates when
// we can extract them (immune to tracking-parameter noise on URLs); fall
// back to the normalized URL otherwise. Two URLs with the same `dedupKey`
// represent the same job posting and MUST land in the same `jobs` row.
export function computeDedupKey(applyURL: string, resolution: ATSResolution | null): string {
  if (resolution && resolution.ats_external_id) {
    return `${resolution.ats_type}:${resolution.ats_external_id}`;
  }
  return normalizeApplyURL(applyURL);
}

// Strip tracking params, lowercase host, drop trailing slash. The query
// allow-list keeps params that materially change the destination (e.g.
// gh_jid which selects a specific Greenhouse job) and drops the rest.
const PRESERVE_QUERY_PARAMS = new Set(["gh_jid", "jid", "id", "p", "postingId"]);

export function normalizeApplyURL(rawURL: string): string {
  try {
    const url = new URL(rawURL);
    url.hostname = url.hostname.toLowerCase();
    if (url.hostname.startsWith("www.")) url.hostname = url.hostname.slice(4);
    if (url.pathname.length > 1 && url.pathname.endsWith("/")) {
      url.pathname = url.pathname.slice(0, -1);
    }
    const keep: [string, string][] = [];
    for (const [k, v] of url.searchParams) {
      if (PRESERVE_QUERY_PARAMS.has(k)) keep.push([k, v]);
    }
    url.search = "";
    for (const [k, v] of keep) url.searchParams.append(k, v);
    url.hash = "";
    return url.toString();
  } catch {
    return rawURL.trim();
  }
}
