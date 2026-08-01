-- Purge EEO / protected-class answers captured by the ATS autofill pass.
--
-- Until 2026-08-01 the submit-capture loop walked every labelled input on an
-- ATS page, so the EEO block Greenhouse/Lever/Ashby append to their
-- application forms (race, ethnicity, disability, veteran status, gender) was
-- captured into application_fields. Worse, _shared/profile_fields.ts had
-- first-class canonical keys for four of them, so a single answer was
-- promoted into candidate_field_history and then PREFILLED into every later
-- application.
--
-- That data is GDPR Art. 9 special-category data we have no lawful basis to
-- hold, and its presence alongside application materials defeats the
-- segregation EEO reporting depends on. Capture is now blocked client-side
-- (ATSAutofillPolicy.sensitiveLabelPatterns) and server-side
-- (isSensitiveLabel in store-application-fields); this removes what was
-- already collected.
--
-- Postgres word boundaries are \y, not \b (\b is backspace here). Patterns
-- mirror ATSAutofillPolicy.sensitiveLabelPatterns and profile_fields.ts.

do $$
declare
  sensitive_label_re constant text :=
    '\yrace\y|ethnic|disab|\yveteran\y|\ygender\y|\ysex\y|sexual|pregnan|religio|politic|trade union|genetic|biometric';
  removed_fields  bigint;
  removed_history bigint;
  removed_essays  bigint;
begin
  delete from public.application_fields
  where field_label ~* sensitive_label_re;
  get diagnostics removed_fields = row_count;

  -- Raw-label rows plus the four retired canon: keys.
  delete from public.candidate_field_history
  where field_label ~* sensitive_label_re
     or field_label in (
       'canon:gender',
       'canon:race_ethnicity',
       'canon:veteran_status',
       'canon:disability_status'
     );
  get diagnostics removed_history = row_count;

  -- Long-form answers keyed by question text (embeddings cascade with them).
  delete from public.candidate_essay_answers
  where question_text ~* sensitive_label_re
     or question_norm ~* sensitive_label_re;
  get diagnostics removed_essays = row_count;

  raise notice 'purged EEO capture: % application_fields, % candidate_field_history, % candidate_essay_answers',
    removed_fields, removed_history, removed_essays;
end $$;
