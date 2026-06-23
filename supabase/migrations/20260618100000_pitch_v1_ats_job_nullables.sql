-- Pitch v1 follow-up: ATS-sourced jobs have no video. The MVP jobs schema
-- requires video_url; drop the constraint so sync-jobs can insert ATS rows.
-- Reels and employer posts continue to set video_url; the iOS feed treats
-- a null value as the signal to render the carousel placeholder instead of
-- the AVPlayer.

alter table public.jobs
  alter column video_url drop not null;
