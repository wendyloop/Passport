create table public.scrape_query_stats (
  id              uuid primary key default gen_random_uuid(),
  run_id          text        not null,           -- Apify run ID
  run_date        date        not null,
  platform        text        not null,           -- 'tiktok' | 'instagram'
  query_type      text        not null,           -- 'hashtag' | 'keyword'
  query           text        not null,           -- exact hashtag or keyword phrase
  total_pulled    int         not null default 0, -- raw results from Apify
  passed_screening int        not null default 0, -- passed the hiring keyword filter
  rejected_noise  int         not null default 0, -- failed screening (not hiring content)
  rejected_duplicate int      not null default 0, -- already in DB
  inserted        int         not null default 0, -- new rows written to jobs table
  oldest_post_at  timestamptz,                    -- oldest post timestamp in this batch
  newest_post_at  timestamptz,                    -- newest post timestamp in this batch
  created_at      timestamptz not null default now()
);

-- Index for the admin report view (platform + date range queries)
create index scrape_query_stats_platform_date_idx
  on public.scrape_query_stats (platform, run_date desc);

-- Admins can read, service role can write
alter table public.scrape_query_stats enable row level security;

create policy "Admins can read scrape stats"
  on public.scrape_query_stats for select
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'admin'
    )
  );
