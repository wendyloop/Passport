-- Backfill: clear implausible structured compensation.
--
-- Board APIs echo whatever the employer typed into the posting form.
-- PermitFlow's "Recruiting Operations Manager" reached Getro as 13000/16000
-- cents — $130/$160 a year, meant as $130K/$160K — and generate-carousel's
-- `$${Math.round(n / 1000)}k` rendered it as "$0k–$0k" on the cover slide.
-- Stripe's rows carry the mirror-image error: 17200000 dollars (cents that
-- were never divided), which rendered "$17200k".
--
-- Bounds match sanitizeCompensation() in _shared/ats/compensation.ts, which
-- now gates every ingestion path so these can't come back. Keep the two in
-- sync if either moves.
--
-- Both endpoints of an offending pair are cleared together: when one end of
-- a range is a typo the other almost always is too, so keeping the survivor
-- would publish a number no employer stated. Every affected row has a null
-- compensation_text, so there is no raw string to re-derive from — these
-- jobs now show no compensation rather than a wrong one.
--
-- compensation_min_annual feeds the carousel source_hash (cmina in
-- generate-carousel), so clearing it invalidates the stored hash and the
-- affected carousels regenerate on the next cron pass. No version bump
-- needed.

update jobs
set compensation_min_annual = null,
    compensation_max_annual = null
where (compensation_min_annual is not null and (compensation_min_annual < 1000 or compensation_min_annual > 10000000))
   or (compensation_max_annual is not null and (compensation_max_annual < 1000 or compensation_max_annual > 10000000))
   or (compensation_min_annual is not null and compensation_max_annual is not null
       and compensation_min_annual > compensation_max_annual);

update jobs
set compensation_min_hourly = null,
    compensation_max_hourly = null
where (compensation_min_hourly is not null and (compensation_min_hourly < 5 or compensation_min_hourly > 2000))
   or (compensation_max_hourly is not null and (compensation_max_hourly < 5 or compensation_max_hourly > 2000))
   or (compensation_min_hourly is not null and compensation_max_hourly is not null
       and compensation_min_hourly > compensation_max_hourly);
