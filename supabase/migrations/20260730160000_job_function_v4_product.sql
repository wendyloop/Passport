-- Classifier v4 (mirrors _shared/title_classify.ts — keep in sync). Fixes
-- the starved/polluted product bucket:
--   1. product now runs FIRST — "Product Manager, Infrastructure" and
--      "Senior Software Product Manager" were leaking to engineering via
--      the tech keywords;
--   2. senior product-org titles match ("Director/VP of Product
--      (Management)", "Chief Product Officer") — 36 senior PM jobs sat
--      unclassified;
--   3. word boundary on "head of product" — "Head of ProductION, Missiles"
--      manufacturing titles were false-positives; production/manufacturing
--      now lands in operations;
--   4. "product (marketing|design)" exclusion keeps PMM/product-design with
--      their own teams even though product runs first.

create or replace function public.classify_job_function_v4(p_title text)
returns public.job_function
language sql
immutable
as $$
  select case
    when p_title ~* 'product manager|product owner|product management|product lead|head of product\y|(director|vp|svp) of product\y|chief product officer'
         and p_title !~* 'product (marketing|design)' then 'product'
    when p_title ~* 'software|backend|frontend|full.?stack|platform engineer|infrastructure|devops|sre|site reliab|mobile engineer|ios |android|embedded|firmware|security engineer|data engineer|ml engineer|machine learning|ai engineer|research engineer|hardware|electrical engineer|mechanical engineer|qa engineer|test engineer' then 'engineering'
    when p_title ~* 'data scien|data analy|analytics|research scien|applied scien|quantitative|\yscientist\y' then 'science'
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
    when p_title ~* 'operations|\yops\y|chief of staff|office manager|executive assistant|logistics|supply chain|production\y|manufactur' then 'operations'
    else null
  end::public.job_function
$$;

-- 1) Rows v4 newly claims for product (from engineering/science/null/…).
update public.jobs
set job_function = 'product'
where title is not null
  and public.classify_job_function_v4(title) = 'product'
  and job_function is distinct from 'product';

-- 2) Evict the known production/manufacturing false-positives from product.
--    Scoped to titles containing "production" so LLM-classified product
--    rows whose titles carry no keyword are left alone.
update public.jobs
set job_function = public.classify_job_function_v4(title)
where job_function = 'product'
  and title ~* 'production'
  and public.classify_job_function_v4(title) is distinct from 'product';

-- 3) Fill remaining NULLs v4 can now place (production/manufacturing → ops).
update public.jobs
set job_function = public.classify_job_function_v4(title)
where job_function is null
  and title is not null
  and public.classify_job_function_v4(title) is not null;
