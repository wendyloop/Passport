// Detecting postings that no longer exist in the ATS.
//
// `jobs.is_active` was originally driven only by ingest-jobs' expiry sweep,
// which keys off `last_seen_at` — "still listed on the VC board". That sweep
// is gated on the fund fully draining in a single run (`nextCursor === null`),
// because a partial pass can't distinguish "gone" from "not reached yet". Four
// big Getro funds never drain in one 45s run, so their sweep effectively never
// fires and their closed postings stay is_active=true indefinitely.
//
// The ATS adapters give us a second, strictly better signal. When an adapter
// returns the company's full live board, any active job carrying an
// ats_external_id that is absent from that board is definitively gone at the
// source — the ATS is the system of record for the posting, and a VC board
// re-listing it does not resurrect it.
//
// Two guards keep this from mass-closing on bad input:
//   - The caller must only pass a feed it actually fetched successfully and
//     that came back non-empty (see feedIsAuthoritative). A renamed/dead board
//     token returns an empty list, which would otherwise close every job.
//   - A grace window on created_at absorbs the ingest→enrich race: a job the
//     board surfaced minutes ago may not be visible in a cached ATS response
//     yet. Anything older than the window has had many chances to appear.

/** Minimal shape needed to decide whether a job vanished from its ATS. */
export type VanishableJob = {
  id: string;
  ats_external_id: string;
  created_at: string | null;
};

/**
 * An empty adapter result is indistinguishable from a dead board token or a
 * transient upstream failure, so it is never treated as proof of absence.
 */
export function feedIsAuthoritative(fetchedCount: number): boolean {
  return fetchedCount > 0;
}

/**
 * Ids of jobs that are absent from the live ATS board and old enough to trust
 * that absence. Jobs with an unparseable/missing created_at are kept active —
 * this fails safe toward showing a stale posting rather than hiding a live one.
 */
export function selectVanishedJobIds(
  jobs: VanishableJob[],
  liveExternalIds: Set<string>,
  options: { now: number; graceMs: number },
): string[] {
  const vanished: string[] = [];
  for (const job of jobs) {
    if (liveExternalIds.has(job.ats_external_id)) continue;

    const createdAt = job.created_at ? Date.parse(job.created_at) : NaN;
    if (!Number.isFinite(createdAt)) continue;
    if (options.now - createdAt < options.graceMs) continue;

    vanished.push(job.id);
  }
  return vanished;
}
