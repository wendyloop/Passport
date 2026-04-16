drop policy if exists "Employer profiles are readable by authenticated users" on public.employer_profiles;

create policy "Employer profiles are readable by authenticated users"
on public.employer_profiles
for select
to authenticated
using (true);
