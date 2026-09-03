// S-5: which resume does this candidate mean?
//
// Five edge functions each hand-rolled `order created_at desc limit 1`, which
// silently meant "the newest one". Now that a candidate can hold several and
// nominate a default, that convention has to live in one place — a default the
// cover letter and keyword gap ignored would be worse than no default at all.
//
// Resolution order, everywhere:
//   1. an explicitly requested resume (the candidate picked one for this
//      application), verified to belong to the caller
//   2. their default
//   3. the newest that did not fail to parse
//
// Step 3 is the pre-S-5 behaviour, so a candidate who never sets a default
// sees no change.

type Admin = {
  from: (table: string) => any;
};

export type ResumeQueryOptions = {
  /// Columns to select. Callers need different slices — file_path for the
  /// attach path, parsed_json for prompting — so this is not fixed here.
  columns?: string;
  /// A specific resume the candidate chose for this application. Accepts an id
  /// or a storage path; apply-to-job has always passed the latter.
  requestedId?: string | null;
  requestedPath?: string | null;
  /// Skip rows with no parsed_json. Prompting paths need the structured blob;
  /// the attach path only needs the file and should take whatever exists.
  requireParsed?: boolean;
};

export async function selectResume<T = Record<string, unknown>>(
  admin: Admin,
  profileId: string,
  options: ResumeQueryOptions = {},
): Promise<T | null> {
  const columns = options.columns ?? "id, file_path, parsed_json, parsed_text";

  // An explicit choice is always scoped to the caller's own rows, so a
  // requested id belonging to someone else resolves to null rather than
  // leaking another candidate's resume into this application.
  const requested = options.requestedId ?? options.requestedPath;
  if (requested) {
    const column = options.requestedId ? "id" : "file_path";
    const { data } = await admin
      .from("resume_uploads")
      .select(columns)
      .eq("profile_id", profileId)
      .eq(column, requested)
      .maybeSingle();
    if (data) return data as T;
    // Deliberately falls through rather than failing: a stale path from an
    // older client should still produce an application, just with the
    // default resume attached.
  }

  let query = admin
    .from("resume_uploads")
    .select(columns)
    .eq("profile_id", profileId)
    .neq("parse_status", "failed");

  if (options.requireParsed) query = query.not("parsed_json", "is", null);

  // is_default first, created_at as the tiebreak. One ordered query rather
  // than "try the default, then try the newest" — half the round trips, and
  // no window where a candidate mid-switch resolves to nothing.
  const { data } = await query
    .order("is_default", { ascending: false })
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  return (data ?? null) as T | null;
}
