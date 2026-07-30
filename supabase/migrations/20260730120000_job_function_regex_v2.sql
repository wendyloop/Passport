-- Regex v2 job_function backfill: 40% of the live catalog (13.3k jobs) had
-- NULL job_function because the v1 title rules missed bare "Engineer"
-- titles, "Accountant", "Solutions Architect", "Account Development", etc.
-- Mirrors _shared/title_classify.ts v2 EXACTLY (same rules, same order —
-- keep in sync). Deliberately unclassified: non-startup-function roles
-- (drivers, retail, field technicians) pending a product decision on
-- whether they belong in the feed at all. The generate-carousel LLM pass
-- fills remaining nulls from full JDs as carousels generate.

create or replace function public.classify_job_function_v2(p_title text)
returns public.job_function
language sql
immutable
as $$
  select case
    when p_title ~* 'software|backend|frontend|full.?stack|platform engineer|infrastructure|devops|sre|site reliab|mobile engineer|ios |android|embedded|firmware|security engineer|data engineer|ml engineer|machine learning|ai engineer|research engineer|hardware|electrical engineer|mechanical engineer|qa engineer|test engineer' then 'engineering'
    when p_title ~* 'data scien|data analy|analytics|research scien|applied scien|quantitative|\yscientist\y' then 'science'
    when p_title ~* 'product manager|product owner|technical program|program manager|head of product|product lead' then 'product'
    when p_title ~* 'designer|design lead|\yux\y|\yui designer|user experience|user interface|brand design|graphic|illustrator|creative director' then 'design'
    when p_title ~* 'sales|account exec|account manager|account develop|account represent|business develop|\ybdr\y|\ysdr\y|revenue|partnership|appointment setter' then 'sales'
    when p_title ~* 'marketing|growth|content|brand manager|\yseo\y|social media|community manager|communications' then 'marketing'
    when p_title ~* 'customer success|customer support|support engineer|solutions engineer|solutions architect|solutions consultant|implementation|technical account|help ?desk|customer experience' then 'support'
    when p_title ~* 'recruit|talent|people ops|people partner|\yhr\y|human resources' then 'hr'
    when p_title ~* 'finance|accounting|accountant|controller|fp&a|treasury|payroll|bookkeep|billing|\ytax\y' then 'finance'
    when p_title ~* 'legal|counsel|compliance|regulatory|paralegal' then 'legal'
    when p_title ~* '\yengineer(ing)?\y|\ydeveloper\y' then 'engineering'
    when p_title ~* 'operations|\yops\y|chief of staff|office manager|executive assistant|logistics|supply chain' then 'operations'
    else null
  end::public.job_function
$$;
revoke all on function public.classify_job_function_v2(text) from public, anon, authenticated;
grant execute on function public.classify_job_function_v2(text) to service_role;

-- Backfill NULLs only — never overrides an existing classification.
update public.jobs
set job_function = public.classify_job_function_v2(title)
where job_function is null
  and title is not null
  and public.classify_job_function_v2(title) is not null;
