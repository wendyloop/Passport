alter table public.jobs
  add constraint jobs_source_url_unique unique (source_url);
