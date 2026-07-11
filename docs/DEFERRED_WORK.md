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
| F1 | Social visual language for carousels: sticker chips w/ rotation, caption-highlight text blocks, doodle accents, cascade-in bullets, "swipe →" affordance | carousel v3 plan (backlog C); anchor `CarouselFeedCard.swift` | M | — |
| F4 | Startup-stage "founder-reachable" toggle (pre-seed→series B, ~3.4k jobs) | analysis (backlog D3); anchor `JobSeekerHomeView.swift` | S–M | needs company `stage` in feed payload (shared with F8) |
| F6 | For-You v0: rank feed by job_function affinity from saves + applies (no ML) | analysis (backlog D5); anchor `SupabaseService.swift` | M | job_function ✅ |
| F7 | Founder slide in carousel ("meet Jane 👋") ending in the Pitch-the-founder CTA | carousel v3 plan | M | `company_contacts` populating ✅ |
| F9 | Throttle `pitch-generate-carousel` back from `*/30` to hourly/daily **after** the backlog drains (the backfill itself is already running; this is the cost-hygiene step at the end, not the backfill) | rescue migration comment | S | carousel backlog drained |
| F10 | **Share-a-job loop** (added 2026-07-11 — network-effect priority): candidate shares a job by link over text; recipient sees a rich preview, taps → landing page → App Store/TestFlight → app opens the job. Parts: **F10a** ShareLink button on feed cards (S) · **F10b** universal links — Associated Domains + AASA file on the domain, app routes `https://<domain>/j/{id}` to the job (M) · **F10c** public landing edge function: OG tags (title/company/comp), store link, "open in app" (M) · **F10d** v2 rendered share image for the OG card (decide renderer then — carousel-service was deleted; prefer an edge-side render) | user request | M–L total | ⚠ two open questions below (domain hosting, store/TestFlight URL) |

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

### Milestone 2 — "First-session wow + the share loop" (~1-1.5 weeks)
8. **F10a-c** share-a-job loop (M–L — the network-effect play; needs the two open questions answered)
9. **F1** social visual language for carousels (M)
10. **F7** founder slide → Pitch CTA (M)
11. **F4** startup-stage toggle (S–M — stage payload already done by F8)
12. **F6** For-You v0 (M)

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
