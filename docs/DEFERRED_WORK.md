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
| T3 | `process-apify-results` N+1: loads all `jobs.source_url` into memory, row-by-row inserts | refactor pass; anchor ~line 385 | S–M | — |
| T5 | `CandidateStore` split out of `AppSessionStore` | refactor pass; anchor `AppSessionStore.swift` | M | pair with T1 |
| T6 | Full DI: protocol-extract services, inject through view tree | refactor pass; anchor `SupabaseService.swift` | M–L | with first service-level tests |
| T7 | Snapshot/UI tests for feed cards + pitch sheet (swift-snapshot-testing via SPM) | refactor pass; anchor `CarouselFeedCard.swift` | M | — |
| T8 | **Security posture for App Store release (decided 2026-07-11)**: (a) require auth on `companies`/`funds`/`carousels` — consistent with `jobs`; the F10c landing page reads via service-role server-side, so nothing needs anon; (b) migrate anon JWT → Supabase publishable/secret key model; (c) raise `minimum_password_length` 6→8 + enable leaked-password protection; (d) verify all storage buckets private (resumes already signed-URL-only) | refactor pass + user decision; anchor `Config.swift` | M | do before App Store submission; after F10c exists (landing page must not rely on anon reads) |
| T9 | Founder-pitch v2: re-scrape cadence, email verification vendor before send, per-company weekly cap | founder-email plan; anchors in both functions | M | real send/bounce data (post-launch) |

### Employer side

| ID | Item | Source | Effort | Depends on |
|---|---|---|---|---|
| P1 | Signed resume download edge function for employers (application-based authorization; bucket stays private) | PHASE2 notes | M | — |
| P2 | **Application states — decided (2026-07-11)**: implement the full `reviewing`/`contacted`/`rejected`/`hired` set + **optional** internal notes per application. Rationale: state transitions + notes are the feedback loop for improving both candidate and employer experience — we want this insight | PHASE2 notes + user decision | M | — |

### Shelved (deliberately not scheduled)

| ID | Item | Status |
|---|---|---|
| P3 | Job-level employer analytics (impressions/saves/applies/conversion). **Shelved 2026-07-11** — employer side isn't launching yet. Anchored in code so it isn't lost: `TODO(deferred)` in `supabase/functions/log-application-event/index.ts` (analytics will aggregate on top of those events + new impression tracking) | ⏸ revisit at employer launch |

### Post-launch reversals (FIRST-100-USERS markers)

| ID | Item | Source | Effort | Depends on |
|---|---|---|---|---|
| X1 | Replace founder-fatigue feed demotion + once-per-founder-ever send rule with real ranking/caps | `FIRST-100-USERS` markers | S–M | >100 users / real volume |

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

### Milestone 3 — "Trust + the other side of the marketplace" (~1-2 weeks)
13. **T8** security posture: RLS lockdown + publishable keys + password policy (M — before App Store submission, after F10c)
14. **P1** employer signed resume download (M)
15. **P2** application states + optional internal notes (M)
16. **T7** snapshot tests (M)

### Milestone 4 — "Scale debt" (as volume justifies)
17. **T1 + T5** employer/admin refactor + store split (L)
18. **T3** apify N+1 (S–M)
19. **T9** founder-pitch v2 (M — after real bounce/reply data)
20. **T6** full DI (M–L)
21. **F10d** rendered share images (M — pick renderer then)

### Post-100-users
22. **X1** replace first-100-users mechanics with real ranking

---

## ⚠ Open questions (only F10's remain)

| Item | Question |
|---|---|
| **F10b** universal links | Which domain hosts the share links + AASA file — `tryscout22.com`? Where is it hosted today (it currently only has Resend DNS records)? Universal links need us to serve `/.well-known/apple-app-site-association` from that domain over HTTPS. |
| **F10c** landing CTA | Is there a public TestFlight link (or App Store listing) yet? The landing page's "get the app" button needs a real destination before share links go out. |
