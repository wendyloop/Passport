// C-1: deciding which ATS a company is on, from the apply URLs of its jobs.
//
// Pure, and tested, because getting this wrong is not a no-op: writing the
// wrong (ats_type, ats_token) points the per-company crawler at a DIFFERENT
// company's job board, and every posting it returns would be attributed to
// the wrong employer.

import { classifyApplyURL } from "./classify.ts";
import type { ATSType } from "./models.ts";

export type HarvestResolution = { ats_type: ATSType; ats_token: string };

export type HarvestVerdict =
  | { kind: "resolved"; resolution: HarvestResolution }
  // Recognised URLs pointed at more than one board. Skipped rather than
  // guessed — half-crawling from the wrong board is worse than not crawling.
  | { kind: "ambiguous" }
  // Nothing recognised: a bespoke careers site, or an ATS with no adapter.
  | { kind: "unresolved" };

export function harvestFromApplyURLs(
  urls: Array<string | null | undefined>,
): HarvestVerdict {
  const seen = new Map<string, HarvestResolution>();
  for (const url of urls) {
    const hit = classifyApplyURL(url);
    if (!hit) continue;
    // Token case is preserved: Lever treats jobs.lever.co/Kyverna and
    // /kyverna as the same board, but the token is echoed back into API URLs
    // and normalising it here would silently diverge from what ingest stored.
    seen.set(`${hit.ats_type}:${hit.ats_token}`, {
      ats_type: hit.ats_type,
      ats_token: hit.ats_token,
    });
  }

  if (seen.size === 0) return { kind: "unresolved" };
  if (seen.size > 1) return { kind: "ambiguous" };
  return { kind: "resolved", resolution: [...seen.values()][0] };
}
