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
grep -rn "TODO(deferred)" ios-native/JobTok supabase/functions services
```

Keep marker and table row in sync; delete both when an item ships.
`FIRST-100-USERS` markers are found the same way.

---

## All items

Effort: S ≈ hours · M ≈ a day-ish · L ≈ multi-day.

### Features (candidate-facing)

| ID | Item | Source | Effort | Depends on |
|---|---|---|---|---|
| F9 | Throttle `pitch-generate-carousel` back from `*/30` to hourly/daily **after** the backlog drains (the backfill itself is already running; this is the cost-hygiene step at the end, not the backfill) | rescue migration comment | S | carousel backlog drained |
| F10 | Share-a-job loop. **F10a ShareLink + F10c landing page shipped 2026-07-11** (links point at the Supabase-hosted `job-share` function for now; deep link via `jobtok://job/{id}`). Remaining: **F10b** universal links once tryscout22.com hosts the page + AASA, **F10d** rendered share image. `APP_STORE_URL` secret is the fill-in for the get-the-app CTA | user request | M (remaining) | ⚠ open questions below |

### Platform / tech debt

| ID | Item | Source | Effort | Depends on |
|---|---|---|---|---|
| T1 | Employer + admin view refactors (extract subviews, route networking through services; incl. `JobTokEmployerRoleWorkflow` out of `VideoStudio.swift`) | refactor pass | L | do together with T5 |
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
| X1 | Replace founder-fatigue feed demotion with real ranking (the once-per-founder-ever send rule was already replaced 2026-07-23 by a 7-day per-contact cooldown — migration `20260723120000`) | `FIRST-100-USERS` markers | S | >100 users / real volume |

---

## Build order

Sequenced by: dependencies first → launch blockers → Gen Z first-time-user
impact → quick wins early.

### Milestone 1 — "The feed doesn't lie" — ✅ SHIPPED 2026-07-11 (PR #15)
F5 aggregator blocklist · F3 comp-first ranking · F8 big-co demotion +
apply-only gating · F2 experience/work-mode filter chips · T4 board retry ·
T2 carousel-service deleted. **F9 still pending**: throttle the carousel
cron back from `*/30` once the backlog drains (96/32k done at ship time).

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
