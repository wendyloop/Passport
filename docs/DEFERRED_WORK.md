# Plan — consolidated backlog & build order

The single planning doc for scout22. Consolidates: the former tech-debt table
(this file), the feature backlog (2026-07-09 market analysis + carousel v3
plan), the open items from `JOBTOK_PHASE2_NOTES.md`, the `TODO(deferred)`
code markers, and the `FIRST-100-USERS` markers. Updated 2026-07-11 with
product decisions (share loop added; big-co handling, security posture,
application states decided; analytics shelved; carousel-service resolved).

Conventions (unchanged): every item with a code anchor has a
`TODO(deferred):` marker at its implementation site — list them with:

```bash
grep -rn "TODO(deferred)" ios-native/scout22 supabase/functions services
```

Keep marker and table row in sync; delete both when an item ships.
`FIRST-100-USERS` markers are found the same way.

---

## All items

Effort: S ≈ hours · M ≈ a day-ish · L ≈ multi-day.

### Features (candidate-facing)

| ID | Item | Source | Effort | Depends on |
|---|---|---|---|---|
| ~~F9~~ | ~~Throttle `pitch-generate-carousel` back after the backlog drains~~ — ✅ **done 2026-08-15** (`20260815100000_carousel_cron_restore.sql`). Backlog hit 0; schedule restored `*/2` → `*/30`. The `*/2` had been set live via `cron.alter_job` on 07-31, so the repo read `*/30` for two weeks while production ran `*/2` — the restore is a migration specifically so that can't recur | rescue migration comment | S | — |
| F10 | Share-a-job loop. **F10a ShareLink + F10c landing page shipped 2026-07-11** (links point at the Supabase-hosted `job-share` function for now; deep link via `jobtok://job/{id}`). Remaining: **F10b** universal links once tryscout22.com hosts the page + AASA, **F10d** rendered share image. `APP_STORE_URL` secret is the fill-in for the get-the-app CTA | user request | M (remaining) | ⚠ open questions below |

### Platform / tech debt

| ID | Item | Source | Effort | Depends on |
|---|---|---|---|---|
| T1 | Employer + admin view refactors (extract subviews, route networking through services; incl. `Scout22EmployerRoleWorkflow` out of `VideoStudio.swift`) | refactor pass | L | do together with T5 |
| T5 | `CandidateStore` split out of `AppSessionStore` | refactor pass; anchor `AppSessionStore.swift` | M | pair with T1 |
| T6 | Full DI: protocol-extract services, inject through view tree | refactor pass; anchor `SupabaseService.swift` | M–L | with first service-level tests |
| T7 | **First pass shipped 2026-07-11**: ImageRenderer render-smoke tests (crash/zero-size regressions) in `RenderSmokeTests.swift`. Remainder: pixel-diff snapshots via swift-snapshot-testing (SPM) with recorded baselines | refactor pass | M | — |
| T8 | **Partially shipped 2026-07-11** (RLS lockdown: companies/funds/company_funds/carousels now authenticated-only; password minimum 8). Remainder: migrate the committed anon JWT to Supabase's publishable/secret key model — needs keys minted in the dashboard, then swap `Config.swift` + edge secrets. Anchor `Config.swift` | refactor pass + user decision | S | dashboard access |
| T9 | **Partially shipped 2026-07-11** (per-company weekly pitch cap of 3 + 14-day re-scrape cadence for zero-contact companies). Remainder: pre-send email verification via a vendor (Hunter/NeverBounce) — needs an account + API key. Anchor `send-founder-email/index.ts` | founder-email plan | S–M | vendor account |

### Employer side

| ID | Item | Source | Effort | Depends on |
|---|---|---|---|---|

### Shelved (deliberately not scheduled)

| ID | Item | Status |
|---|---|---|
| P3 | Job-level employer analytics (impressions/saves/applies/conversion). **Shelved 2026-07-11** — employer side isn't launching yet. Anchored in code so it isn't lost: `TODO(deferred)` in `supabase/functions/log-application-event/index.ts` (analytics will aggregate on top of those events + new impression tracking) | ⏸ revisit at employer launch |

### Post-launch reversals (FIRST-100-USERS markers)

| ID | Item | Source | Effort | Depends on |
|---|---|---|---|---|
| X1 | Replace founder-fatigue feed demotion with real ranking (the once-per-founder-ever send rule was already replaced 2026-07-23 by a 7-day per-contact cooldown — migration `20260723120000`). **Widened 2026-08-01** to company level: a founder pitch stamps `companies.last_founder_touch_at`, demoting *every* role at that company for 7 days, because one founder usually covers several openings. Deliberately founder-pitch-only — ATS-portal applies never reach the founder's inbox. Migration `20260801130000`; markers in `send-founder-email`, `SharedFormatters.founderFatigueBucket`, `CompanyRef` | `FIRST-100-USERS` markers | S | >100 users / real volume |
| X2 | Feed ranking runs client-side over the 200+200 fetched rows, so founder-fatigue demotion reorders *within* that window rather than pulling untouched older jobs up into it. Company-level demotion (X1) makes this bite sooner. Fix = move ranking server-side (RPC or a ranked view) | noted 2026-08-01 during X1 | M | real volume |

---

## Build order

Sequenced by: dependencies first → launch blockers → Gen Z first-time-user
impact → quick wins early.

### Milestone 1 — "The feed doesn't lie" — ✅ SHIPPED 2026-07-11 (PR #15)
F5 aggregator blocklist · F3 comp-first ranking · F8 big-co demotion +
apply-only gating · F2 experience/work-mode filter chips · T4 board retry ·
T2 carousel-service deleted. **F9 closed 2026-08-15**: backlog fully drained
(0 jobs without a carousel), cron restored to `*/30`.

### Milestone 2 — "First-session wow + the share loop" — ✅ SHIPPED 2026-07-11 (PR #16)
F10a share buttons + F10c landing page (Supabase-hosted until the domain
answers land) · F1 social visuals (sticker chips, caption highlights,
cascade-in bullets, swipe hint) · F7 founder slide + pitch CTA · F4
founder-reachable toggle · F6 For-You affinity ranking.
**Still open**: F10b universal links + F10d share images (blocked on the
two open questions).

### Milestone 3 — "Trust + the other side" — ✅ MOSTLY SHIPPED 2026-07-11 (PR #17)
T8 RLS lockdown + password policy (key migration remains — dashboard needed) ·
P1 employer signed resume download · P2 full application pipeline
(New/Reviewing/Contacted/Rejected/Hired + private notes) · T7 render-smoke
tests (pixel-diff upgrade remains).

### Milestone 4 — "Scale debt" — partially shipped 2026-07-11 (PR #18)
✅ **T3** apify batch existence check + bulk insert · ✅ **T9 partial**
per-company pitch cap + zero-contact re-scrape cadence.
Remaining, deliberately for a dedicated session (multi-day refactors that
shouldn't be rushed at the tail of a long one):
17. **T1 + T5** employer/admin refactor + store split (L, one effort)
18. **T6** full DI (M–L — with the first service-level tests)
19. **T9 remainder** pre-send email verification (needs vendor account)
20. **T8 remainder** publishable-key migration (needs dashboard access)
21. **F10b/d** universal links + rendered share images (need domain/store answers)

### Post-100-users
22. **X1** replace first-100-users mechanics with real ranking

---

## 2026-07-26 roadmap (email trust + profile + matching)

Full plan (findings, schema sketches, test playbook):
`~/.claude/plans/just-plan-and-organize-resilient-beacon.md`. Sequenced
M-A → M-B → P → M-C → M-D → M-E → M-F.

| ID | Item | Status |
|---|---|---|
| M-A | Founder button gates on `companies.founder_contactable` (trigger-maintained); Saved tab fetches bookmarks by id + orders unapplied-by-saved-recency then applied-by-applied-recency; contact scrape 15→50/day | ✅ shipped 2026-07-26 |
| M-B | Resume gate on founder email (`founder_email_require_resume` app_config kill-switch) | ✅ shipped 2026-07-26 |
| — | Resend credentials rotated + webhook wired 2026-07-27; **both email paths verified sending live** (founder via intro@tryscout22.com, applications via applications@tryscout22.com — real Resend ids recorded) | ✅ resolved |
| P | Profile redesign: TikTok shape + LinkedIn substance from `resume_uploads.parsed_json`. Mock v2 locked: full-bleed 3-col grid (1px seams, on-tile captions), no stats row, Videos+About tabs only, weighted profile-strength ring (resume 30/video 30/photo+headline 15/social 15/basics 10), About ends with Links rows + per-role relevance hints ("marketing → IG/TikTok, eng → GitHub, design → portfolio" as fine print, repeated in onboarding socials step). Palette (v4): white with butter yellow as SPARSE accent only — butter appears in exactly four places (tab underline #E8C95C, Primary badge + Parsed pill #F7E39B/#6B5A14, strength-ring border); everything else white #FFFFFF + warm neutrals (tiles/avatar #F1EFE9, hairlines #E6E3DC, borders #DDD9D0, text #201F1B/#6E6A5E/#9B968A). No schema change | ✅ shipped 2026-07-26 (commit d4fe547) |
| M-C | Multi-video + captions (`candidate_videos.caption`/`is_primary`, set/delete RPCs, video picker in apply + founder sheets) | ✅ shipped 2026-07-26 (f7997c7) |
| M-D | Onboarding: basics → resume (skippable) → video (skippable); grandfathered existing accounts | ✅ shipped 2026-07-26 (897f96b) |
| M-E | Matching foundations: `job_embeddings` + `candidate_resume_embeddings` service-role-only tables, `embed-jobs` cron every 10 min (backfill draining ~300/run; **relax to hourly after it drains** — F9-style) | ✅ shipped 2026-07-26 (13a7678) |
| M-F | ≥50% match gate + fit-ranked feed. **Gate flag `founder_email_require_match` is OFF** — calibrate `match_score_floor`/`ceiling` on ~50 real resume/job pairs once real resumes exist, then flip via app_config (no redeploy) | ✅ shipped 2026-07-26 (480ed04), calibration pending |
| — | **Unified pitch email** (2026-07-28): Easy Apply = founder pitch — video required both paths, same founder-useful email (`_shared/pitch_email.ts`), resume+video ATTACHED (5/14MB caps, link fallback), reply-to → candidate, subject hooks. 3,580 regex-junk ats application_emails nulled; sender display name now just "Wendy". Live-verified ALL CHECKS PASSED | ✅ shipped 2026-07-28 (b01efd3) |

---

## ⚠ Open questions (only F10's remain)

| Item | Question |
|---|---|
| **F10b** universal links | Which domain hosts the share links + AASA file — `tryscout22.com`? Where is it hosted today (it currently only has Resend DNS records)? Universal links need us to serve `/.well-known/apple-app-site-association` from that domain over HTTPS. |
| **F10c** landing CTA | Is there a public TestFlight link (or App Store listing) yet? The landing page's "get the app" button needs a real destination before share links go out. |

---

## 2026-09-02 roadmap — Simplify parity, coverage, distribution

From the 2026-09-02 competitive review of Simplify Copilot (simplify.jobs).
Strategic frame: the video feed stays the long-term moat but is **deliberately
dormant** until there is an audience to watch it (`FounderPitchUI.isEnabled =
false` is already that switch). Until ~1,000 active users, scout22 competes as
"Simplify on mobile". **No feature below deletes or degrades anything
video-related** — the video surface stays built and shipped, and later becomes
the unlock ("record a pitch → get X").

Everything ships **free**. No paid tier while the goal is first users. Feature
flags below are cost kill-switches, not paywalls.

Build order: **Part 2 (S) → Part 3 (C) → Part 1 (D)**.

### Part 2 (S) — Simplify feature parity — ⏳ IN PROGRESS (S-1, S-2, S-3, S-5 shipped 2026-09-02)

| ID | Item | Effort | Depends on |
|---|---|---|---|
| ~~S-1~~ | ✅ **shipped 2026-09-02** (`8035004`, `46df3ce`). AI-generated application answers. Three-mode resolution by cosine distance against `candidate_essay_answers`: **reuse** (≥0.85, exists today, $0) → **adapt** (0.60–0.85, rewrite closest prior answer) → **generate** (<0.60, cold, grounded in resume + voice samples). Retrieval path is kept intact and stays the default — it is the free tier if tiering ever returns | M | — |
| ~~S-2~~ | ✅ **shipped 2026-09-02**. Resume↔JD keyword gap surfaced in the apply drawer. Requirement terms extracted per job and cached lazily in `job_keywords` (first candidate to open a job pays the model call; a description hash guards staleness). The diff is pure and free. **Also added `resume_uploads.parsed_text`** — raw resume text was being discarded, leaving matching to see only ~30 skills; that gap also blocked S-4, which cannot tailor bullets that were never stored. Old resumes fall back to `parsed_json` and the UI says so | S–M | — |
| S-2b | **M-F calibration still pending, and not blocked by S-2.** `match_score_floor` 0.20 / `match_score_ceiling` 0.75 remain unvalidated guesses. Calibration needs ~50 real resume/job pairs, which do not exist yet — this is a data problem, not a code one. The S-2 keyword score is a separate, explainable metric and does not depend on it | S | real resumes |
| ~~S-3~~ | ✅ **shipped 2026-09-02**. Cover letters: generate + attach. Attachment needs a **sibling** to `attachResumeHere` — that function deliberately refuses cover-letter uploaders (they threw async from their own bundle; see the comment at its head). Do NOT relax the resume regex. Textarea path routes on a shared `coverLetterPattern` (Swift + injected JS, tested on both sides); file path renders a text-only PDF on device via `CoverLetterPDF`. The kind-aware `findDocumentInput` also closed a latent bug — the resume's accept-based fallback could land it in a cover-letter slot. Voice samples prefer prior letters over essay answers | M | S-1 |
| S-4 | Resume versions + per-job tailoring + on-device PDF render (`ImageRenderer`, same muscle as `CarouselCardTemplates`). Unlimited versions, base never mutated | L | S-2, S-5 |
| ~~S-5~~ | ✅ **shipped 2026-09-02**. Multiple resumes: `resume_uploads` already stores one row per upload; only `fetchLatestResume`'s `limit=1` makes it singular. `is_default` (partial unique index) + `label` + a `set_default_resume` RPC that swaps atomically. Resolution — explicit pick → default → newest — now lives in `_shared/resume_select.ts` and **all five** edge functions use it; a default that the cover letter and keyword gap ignored would be worse than none. Picker in the apply drawer changes the resume for that application only, never the default | S | — |
| S-6 | Candidate-side tracker depth: candidate-editable status, interview date, follow-up. **Must not** reuse `application_notes` — that table is employer-only by RLS design (AUDIT P1-9) | M | — |

**Anti-slop invariant (S-1/S-3/S-4):** only `source IN ('human','edited')` rows
are ever used as voice samples. Never feed model-generated text back in as a
style exemplar — the corpus collapses to one voice within months.

### Part 3 (C) — job coverage beyond VC boards — after Part 2

Measured 2026-09-02 across Simplify's two public lists (34,901 postings /
5,076 distinct companies). **The five existing ATS adapters cover only ~20% of
the intern + new-grad market.** Breakdown (internships / new grad):
Workday **50.2% / 45.1%** · bespoke career sites 17.1% / 17.3% · Oracle Cloud
5.5% / 13.2% · Greenhouse 9.8% / 7.9% · iCIMS 4.2% / 4.1% · SmartRecruiters
4.4% / 4.8% · Ashby 4.2% / 3.9% · Lever 3.0% / 2.3% · Recruitee ~0%.

Intern/new-grad skews enterprise (banks, defense, aero, big tech) and those run
Workday. So coverage needs **both** more tokens *and* new adapters — an earlier
read that named only the token list was wrong.

| ID | Item | Effort | Depends on |
|---|---|---|---|
| C-0 | Baseline: `select ats_type, count(*) from companies where ats_token is not null group by 1`. Judge everything below against it | S | — |
| C-1 | Harvest tokens already owned: sweep `jobs.apply_url` through `classifyApplyURL`, insert any `(ats_type, ats_token)` not in `companies`. Zero network calls | S | C-0 |
| C-2 | Token probing: for companies with a name/domain but no token, guess slug variants against all 5 ATS APIs, keep the 200s. Verified live — `greenhouse/stripe` → 592 jobs, `greenhouse/anthropic` → 1,166; 2 of 4 naive guesses hit. Shape it like `enrich-company-contacts` (cron + cursor + `x-pitch-cron-secret`; remember the `verify_jwt = false` entry in `config.toml`) | M | C-1 |
| C-3 | **Workday adapter** — the single biggest coverage win (~half this market). Known pattern: `POST {tenant}.{host}/wday/cxs/{tenant}/{site}/jobs` with facet/pagination body. Multi-tenant, so the "token" is a (tenant, site) pair — `companies.ats_token` is a single column and will need widening | M–L | C-0 |
| C-4 | Oracle Cloud adapter (`*.oraclecloud.com`, ~5–13%) and iCIMS (~4%). Lower priority than C-3, same shape of work | M | C-3 |
| C-5 | Split the intern/new-grad feed filter. Backend is done — `classifyExperience` already emits `intern` and `entry` separately — but `ExperienceFilter.earlyCareer` merges them. One-line change, outsized impact if interns are the target market | S | — |
| C-6 | More funds (Getro/Consider power hundreds of VC networks; adapters exist, adding fund rows is config) | S | — |
| C-7 | Schema widening this implies: `funds.platform` CHECK is `('getro','consider','bespoke')` — a probe or an external list is not a fund, so this wants a `job_sources` concept. `companies.ats_type` CHECK is the 5 supported and must widen per new adapter | S | C-2/C-3 |

**Built In — assessed and mostly rejected as a jobs source.** `robots.txt`
carries `Disallow: /job/sitemap.xml`; `job-board-sitemap.xml` holds only facet
pages (`/jobs/nashville/project-management`), no job detail URLs; filtered
board pages are disallowed for general crawlers while GPTBot/PerplexityBot get
broad `Allow` exceptions. `/companies/sitemap.xml` IS allowed and enumerates
the company directory — so Built In is a **company-name source that feeds C-2**,
not a job feed. Low priority.

### Part 1 (D) — distribution — after Part 3

Simplify's funnel: GitHub list + programmatic SEO + campus → free unlimited
autofill → tracker → (2026) paid AI. They spent 2021–2024 on the top of that
funnel and only monetized ~5 years in. The AI features retain users; they do
not acquire them.

**Decided 2026-09-02: do SEO pages + campus/CS-club. GitHub list explicitly
deferred** (revisit once the data advantage is real). Wendy will supply the
tryscout22.com web repo when this part starts.

| ID | Item | Effort | Depends on |
|---|---|---|---|
| D-0 | **Domain decision — the actual blocker.** `tryscout22.com` currently has only Resend DNS. Pointing it at the `job-share` function unblocks F10b universal links, F10c's landing CTA, *and* the entire SEO channel at once. This is the highest-leverage open question in the repo | S | ⚠ F10b open question above |
| D-1 | Programmatic SEO pages. `job-share` **already renders a public OG landing page + JSON** — the renderer exists. Needs templated routes generated from rows already held: `/c/{company}`, `/internships/{category}`, `/{role}-jobs-{city}` | M–L | D-0 |
| D-2 | Campus / CS-club channel. Simplify's list is co-branded with Pitt CSC; the partnership is the distribution, the repo is just its artifact | M | — |
| D-3 | ~~GitHub list repo~~ — **deferred 2026-09-02.** Would expose only a new, separate public repo (README + listings JSON + generator); app source is unaffected. Simplify's own org confirms the model: lists + take-homes + small MIT libs are public, product code is private | — | revisit |

**Research banked for D (2026-09-02), so it is not re-derived:**

- **Role mix.** Both lists are tech-only across five categories. Internships
  (15,497 records): AI/ML/Data 43% · Software 31% · Hardware 15% · Product 7% ·
  Quant 3%. New grad (19,404): Software 29% · AI/ML/Data 29% · Hardware 24% ·
  Quant 12% · Product 5%. Hardware and Quant are far larger than expected —
  the new-grad list is not a SWE list.
- **How they are generated — hypothesis, well supported.** 98.6% of internship
  records and 99.4% of new-grad records carry `"source": "Simplify"`; the rest
  are GitHub usernames. The lists are ~99% machine-emitted from Simplify's own
  job DB, with a thin community-PR layer that is mostly co-branding. Supporting
  evidence: `sponsorship` is `"Other"` on 99.3% of rows (a schema field the
  pipeline never populates → generic internal schema, not hand curation); the
  category vocabulary shows a rename in progress (139 `Software Engineering`
  and 72 `Data Science, AI & Machine Learning` stragglers beside the current
  `Software` / `AI/ML/Data`); and the repo is **append-only** — only 17.6% of
  internships and 16.9% of new-grad rows are `active`, the rest kept as an
  archive. Same write-once instinct as `upsert_board_jobs`.
- **Term drift.** "Summer2027-Internships" is mostly *not* Summer 2027 —
  Summer 2026 8,843 · Fall 2026 2,726 · Summer 2027 1,491. `date_posted` spans
  2026-01-05 → present. The new-grad list has no `terms` at all.
- **Record shape** (directly consumable): `company_name`, `title`, `category`,
  `terms[]`, `locations[]`, `url` (raw ATS link), `sponsorship`, `degrees[]`,
  `active`, `date_posted`/`date_updated` (unix), `company_url`.
- **Licence: none** on all three list repos (`"license": null` = all rights
  reserved, not public domain), and every record is stamped `"source":
  "Simplify"` + a `simplify.jobs/c/…` link. Use these lists **only** as a
  company-name discovery seed for C-2, never as a jobs feed to republish.
