// Captures field values from an in-app ATS submission.
//
// Two write paths:
//   - Short fields (no length cutoff hit) → application_fields (audit trail)
//     AND candidate_field_history (autofill source). If the raw ATS label
//     maps to a canonical key, we ALSO write a `canon:<key>` row so the
//     value flows back as a prefill suggestion under any label on a future
//     form (e.g. "Phone" today → "Mobile number" tomorrow).
//   - Long answers (textarea-typed, ≥ESSAY_MIN_CHARS) → candidate_essay_answers,
//     keyed by normalized question. The question is embedded so future
//     forms can fetch the best prior answer via match_candidate_essay.
//
// Capture is best-effort: failures on the essay path never block the short
// fields write, because the autofill UX degrades gracefully without essays.

import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse } from "../_shared/http.ts";
import { createAdminClient, createUserClient } from "../_shared/client.ts";
import { canonLabel, isSensitiveLabel, matchCanonical, normalizeCanonicalValue } from "../_shared/profile_fields.ts";
import { embedText, normalizeQuestion, toPgVector } from "../_shared/openai_embeddings.ts";

const ESSAY_MIN_CHARS = 200;

type ShortField = { label: string; value: string };
type EssayField = { question: string; answer: string };

type RequestBody = {
  eventId: string;
  // Legacy shape: { fields: { label: value } }. Still accepted — labels with
  // answers ≥ ESSAY_MIN_CHARS auto-route to the essay path.
  fields?: Record<string, string>;
  // New shape: callers can pre-split if they know which inputs were textareas.
  shortFields?: ShortField[];
  essays?: EssayField[];
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    const userClient = createUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return jsonResponse({ error: "Unauthorized" }, 401);

    const body = (await request.json().catch(() => ({}))) as RequestBody;
    if (!body.eventId) return jsonResponse({ error: "eventId is required" }, 400);

    const admin = createAdminClient();

    // Verify event belongs to this user — guards against cross-user writes.
    const { data: event, error: eventError } = await admin
      .from("application_events")
      .select("id, candidate_profile_id, job_id")
      .eq("id", body.eventId)
      .eq("candidate_profile_id", user.id)
      .maybeSingle();
    if (eventError) throw eventError;
    if (!event) return jsonResponse({ error: "Event not found" }, 404);

    // Normalize the two accepted input shapes into one list.
    const { shortFields, essays } = splitInputs(body);

    // ---------- Short fields ----------
    // EEO / protected-class answers are dropped before any write. The client
    // already refuses to capture them; this is the backstop.
    const shortClean = shortFields
      .map((f) => ({ label: f.label.trim(), value: f.value.trim() }))
      .filter((f) => f.label && f.value && !isSensitiveLabel(f.label));

    let shortStored = 0;
    let canonicalStored = 0;
    if (shortClean.length > 0) {
      const eventRows = shortClean.map((f) => ({
        event_id: body.eventId,
        candidate_profile_id: user.id,
        field_label: f.label,
        field_value: f.value,
      }));
      const { error: fieldsError } = await admin
        .from("application_fields")
        .insert(eventRows);
      if (fieldsError) throw fieldsError;

      // Raw-label rows + canonical rows both go into candidate_field_history.
      // Two rows per matched field is intentional: the raw label lets us match
      // verbatim on a return visit to the same ATS, the canonical row catches
      // semantically-equivalent labels on a different ATS.
      //
      // Keyed by label and deduped BEFORE the upsert. Postgres rejects an
      // ON CONFLICT DO UPDATE whose VALUES contain the same conflict target
      // twice ("cannot affect row a second time", SQLSTATE 21000), and one
      // form can easily repeat a label — Workday asks for "City" and
      // "Job Title" once per work-history row, and two distinct labels can
      // map to the same canonical key. Last value on the page wins.
      const now = new Date().toISOString();
      const historyByLabel = new Map<string, {
        candidate_profile_id: string;
        field_label: string;
        field_value: string;
        updated_at: string;
      }>();
      const put = (label: string, value: string) => {
        historyByLabel.set(label, {
          candidate_profile_id: user.id,
          field_label: label,
          field_value: value,
          updated_at: now,
        });
      };

      const canonicalKeys = new Set<string>();
      for (const f of shortClean) {
        put(f.label, f.value);
        const canon = matchCanonical(f.label);
        if (canon) {
          // De-caps resume-typography names before they reach storage.
          put(canonLabel(canon), normalizeCanonicalValue(canon, f.value));
          canonicalKeys.add(canon);
        }
      }
      canonicalStored = canonicalKeys.size;

      const { error: historyError } = await admin
        .from("candidate_field_history")
        .upsert([...historyByLabel.values()], {
          onConflict: "candidate_profile_id,field_label",
        });
      if (historyError) throw historyError;
      shortStored = shortClean.length;
    }

    // ---------- Essays ----------
    const essayClean = essays
      .map((e) => ({ question: e.question.trim(), answer: e.answer.trim() }))
      .filter((e) => e.question && e.answer && !isSensitiveLabel(e.question));

    const essayResults: Array<{ question: string; stored: boolean; error?: string }> = [];

    for (const essay of essayClean) {
      try {
        const norm = normalizeQuestion(essay.question);
        if (!norm) continue;
        const embedding = await embedText(essay.question);
        const { error: upsertError } = await admin
          .from("candidate_essay_answers")
          .upsert(
            {
              candidate_profile_id: user.id,
              question_text: essay.question,
              question_norm: norm,
              question_embedding: toPgVector(embedding),
              answer: essay.answer,
              source_job_id: event.job_id ?? null,
              source_event_id: body.eventId,
              updated_at: new Date().toISOString(),
            },
            { onConflict: "candidate_profile_id,question_norm" },
          );
        if (upsertError) throw upsertError;
        essayResults.push({ question: essay.question, stored: true });
      } catch (error) {
        // Don't fail the request — essays are nice-to-have, short fields are
        // the main capture path.
        essayResults.push({
          question: essay.question,
          stored: false,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    return jsonResponse({
      shortStored,
      canonicalStored,
      essaysStored: essayResults.filter((r) => r.stored).length,
      essaysFailed: essayResults.filter((r) => !r.stored).length,
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Unknown error" },
      400,
    );
  }
});

function splitInputs(body: RequestBody): { shortFields: ShortField[]; essays: EssayField[] } {
  // Explicit split wins when callers know the input was a textarea.
  if (body.shortFields || body.essays) {
    return {
      shortFields: body.shortFields ?? [],
      essays: body.essays ?? [],
    };
  }
  // Legacy flat shape: split by length.
  const shortFields: ShortField[] = [];
  const essays: EssayField[] = [];
  for (const [label, value] of Object.entries(body.fields ?? {})) {
    if (!label?.trim() || !value?.trim()) continue;
    if (value.length >= ESSAY_MIN_CHARS) {
      essays.push({ question: label, answer: value });
    } else {
      shortFields.push({ label, value });
    }
  }
  return { shortFields, essays };
}
