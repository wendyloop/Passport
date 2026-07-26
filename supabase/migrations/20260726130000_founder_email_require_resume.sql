-- M-B (roadmap 2026-07-26): founder emails now also require an uploaded
-- resume (the compose sheet promises "your latest resume" — until now that
-- could silently be nothing). Config-flagged so the gate can be toggled off
-- without a redeploy, e.g. during email-deliverability testing.
insert into public.app_config (key, value)
values ('founder_email_require_resume', 'true'::jsonb)
on conflict (key) do nothing;
