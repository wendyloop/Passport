drop policy if exists "Jobs are mutable by admins" on public.jobs;
drop policy if exists "Jobs are mutable by admins or employer owners" on public.jobs;

create policy "Jobs are mutable by admins or employer owners"
on public.jobs
for all
to authenticated
using (
  auth.uid() = employer_profile_id
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role::text = 'admin'
  )
)
with check (
  auth.uid() = employer_profile_id
  or exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role::text = 'admin'
  )
);

do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'storage'
      and table_name = 'objects'
  ) then
    execute 'drop policy if exists "Job video uploads scoped to admin folder" on storage.objects';
    execute 'drop policy if exists "Job video uploads scoped to employer or admin folder" on storage.objects';
    execute 'create policy "Job video uploads scoped to employer or admin folder" on storage.objects for insert to authenticated with check (bucket_id = ''job-videos'' and (storage.foldername(name))[1] = auth.uid()::text and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role::text in (''employer'', ''admin'')))';
  end if;
end $$;
