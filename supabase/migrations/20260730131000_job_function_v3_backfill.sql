-- Classifier v3 (mirrors _shared/title_classify.ts — keep in sync):
-- program_management + clinical buckets, plus the approved white-collar
-- recoveries (bare architect → engineering, accounts payable/receivable →
-- finance, contracts manager → legal, engagement/deployment/delivery
-- consulting → support). Clinical runs before legal so /counsel/ can't eat
-- "counselor"; program_management runs before the team rules so every PM
-- flavor lands in the new section.

create or replace function public.classify_job_function_v2(p_title text)
returns public.job_function
language sql
immutable
as $$
  select case
    when p_title ~* 'software|backend|frontend|full.?stack|platform engineer|infrastructure|devops|sre|site reliab|mobile engineer|ios |android|embedded|firmware|security engineer|data engineer|ml engineer|machine learning|ai engineer|research engineer|hardware|electrical engineer|mechanical engineer|qa engineer|test engineer' then 'engineering'
    when p_title ~* 'data scien|data analy|analytics|research scien|applied scien|quantitative|\yscientist\y' then 'science'
    when p_title ~* 'product manager|product owner|head of product|product lead' then 'product'
    when p_title ~* 'designer|design lead|\yux\y|\yui designer|user experience|user interface|brand design|graphic|illustrator|creative director' then 'design'
    when p_title ~* 'program manager|project manager|technical program|program lead|scrum master|\ypmo\y' then 'program_management'
    when p_title ~* 'nurse|physician|clinician|clinical|therapist|therapy\y|psycholog|psychiatr|counselor|dental|dentist|pharmac|paramedic|medical assistant|medical director|behavior technician|\yrn\y|endocrinolog|cardiolog|dermatolog|patholog|radiolog|oncolog|pediatric|primary care|urgent care|telehealth|dietitian|nutritionist|midwife|phlebotom|health information|caregiver|home health|veterinar' then 'clinical'
    when p_title ~* 'sales|account exec|account manager|account develop|account represent|business develop|\ybdr\y|\ysdr\y|revenue|partnership|appointment setter' then 'sales'
    when p_title ~* 'marketing|growth|content|brand manager|\yseo\y|social media|community manager|communications' then 'marketing'
    when p_title ~* 'customer success|customer support|support engineer|solutions engineer|solutions architect|solutions consultant|implementation|technical account|help ?desk|customer experience|engagement manager|deployment strategist|domain consultant|client solutions|delivery lead' then 'support'
    when p_title ~* 'recruit|talent|people ops|people partner|\yhr\y|human resources' then 'hr'
    when p_title ~* 'finance|accounting|accountant|controller|fp&a|treasury|payroll|bookkeep|billing|\ytax\y|accounts payable|accounts receivable' then 'finance'
    when p_title ~* 'legal|counsel|compliance|regulatory|paralegal|contracts manager' then 'legal'
    when p_title ~* '\yengineer(ing)?\y|\ydeveloper\y|\yarchitect\y' then 'engineering'
    when p_title ~* 'operations|\yops\y|chief of staff|office manager|executive assistant|logistics|supply chain' then 'operations'
    else null
  end::public.job_function
$$;

-- Fill remaining NULLs with v3 rules.
update public.jobs
set job_function = public.classify_job_function_v2(title)
where job_function is null
  and title is not null
  and public.classify_job_function_v2(title) is not null;

-- Move program/project managers that v1/v2 parked under product (or that
-- team-qualified rules claimed) into the new dedicated section.
update public.jobs
set job_function = 'program_management'
where title is not null
  and title ~* 'program manager|project manager|technical program|program lead|scrum master|\ypmo\y'
  and title !~* 'product manager|product owner|head of product'
  and job_function is distinct from 'program_management';
