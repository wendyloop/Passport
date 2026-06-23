// Given an apply / careers URL discovered on a board, resolve the ATS
// provider + the company's token on that ATS.
//
// Returns null when the URL does not match a supported ATS. Companies with
// null resolution are stored with ats_type = null and skipped by sync-jobs.

import type { ATSType } from "./models.ts";

export type ATSResolution = {
  ats_type: ATSType;
  ats_token: string;
};

type Matcher = (url: URL) => ATSResolution | null;

const matchers: Matcher[] = [
  // Greenhouse:
  //   https://boards.greenhouse.io/{token}
  //   https://boards.greenhouse.io/{token}/jobs/123
  //   https://job-boards.greenhouse.io/{token}
  //   https://{token}.greenhouse.io
  (url) => {
    const host = url.hostname.toLowerCase();
    if (host === "boards.greenhouse.io" || host === "job-boards.greenhouse.io") {
      const token = firstPathSegment(url);
      return token ? { ats_type: "greenhouse", ats_token: token } : null;
    }
    if (host.endsWith(".greenhouse.io")) {
      const subdomain = host.slice(0, -".greenhouse.io".length);
      if (subdomain && subdomain !== "boards" && subdomain !== "job-boards" && subdomain !== "api") {
        return { ats_type: "greenhouse", ats_token: subdomain };
      }
    }
    return null;
  },

  // Lever:
  //   https://jobs.lever.co/{token}
  //   https://jobs.lever.co/{token}/{id}
  (url) => {
    const host = url.hostname.toLowerCase();
    if (host === "jobs.lever.co") {
      const token = firstPathSegment(url);
      return token ? { ats_type: "lever", ats_token: token } : null;
    }
    return null;
  },

  // Ashby:
  //   https://jobs.ashbyhq.com/{token}
  //   https://jobs.ashbyhq.com/{token}/{id}
  //   https://app.ashbyhq.com/v1/job-board/{token}  (less common; not the apply URL)
  (url) => {
    const host = url.hostname.toLowerCase();
    if (host === "jobs.ashbyhq.com") {
      const token = firstPathSegment(url);
      return token ? { ats_type: "ashby", ats_token: token } : null;
    }
    return null;
  },

  // SmartRecruiters:
  //   https://jobs.smartrecruiters.com/{token}
  //   https://careers.smartrecruiters.com/{token}
  //   https://smartrecruiters.com/{token}
  (url) => {
    const host = url.hostname.toLowerCase();
    if (
      host === "jobs.smartrecruiters.com" ||
      host === "careers.smartrecruiters.com" ||
      host === "smartrecruiters.com" ||
      host.endsWith(".smartrecruiters.com")
    ) {
      const token = firstPathSegment(url);
      return token ? { ats_type: "smartrecruiters", ats_token: token } : null;
    }
    return null;
  },

  // Recruitee:
  //   https://{token}.recruitee.com
  //   https://careers.{token}.com (less common, not detectable without lookup)
  (url) => {
    const host = url.hostname.toLowerCase();
    if (host.endsWith(".recruitee.com")) {
      const subdomain = host.slice(0, -".recruitee.com".length);
      if (subdomain && subdomain !== "www") {
        return { ats_type: "recruitee", ats_token: subdomain };
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

function firstPathSegment(url: URL): string | null {
  const parts = url.pathname.split("/").filter(Boolean);
  return parts[0] ?? null;
}

// Derive apply_flow from the apply URL host. ATS-hosted forms = ats_form;
// anything else (Workday, custom careers pages, mailto) = external_link.
// "message" is reserved for YC-style flows (not crawled in v1).
export function deriveApplyFlow(applyURL: string | null | undefined): "ats_form" | "external_link" | "message" {
  if (!applyURL) return "external_link";
  const resolved = classifyApplyURL(applyURL);
  return resolved ? "ats_form" : "external_link";
}
