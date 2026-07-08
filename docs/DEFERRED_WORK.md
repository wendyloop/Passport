# Deferred work

Known-but-intentionally-postponed work from the candidate-first refactor +
"email the founder" feature (July 2026). Each item has a `TODO(deferred):`
marker at its anchor in the code — run:

```bash
grep -rn "TODO(deferred)" ios-native/JobTok supabase/functions services
```

to list every anchor. This file is the human-readable index of that backlog;
keep the two in sync (delete the row and the marker together when an item
ships).

| Item | Anchor(s) | Effort | Why deferred / what it takes |
|---|---|---|---|
| **Employer & admin view refactors** | `EmployerHomeView.swift`, `AdminHomeView.swift`, `JobTokEmployerRoleWorkflow` in `VideoStudio.swift` | Large | Same God-view smell as the candidate side, but off the candidate path. Extract sheets/rows into their own files; move direct networking behind the service layer (mirror the `JobSeekerHomeView` / `SupabaseService` split). |
| **`services/carousel-service`** | `services/carousel-service/src/index.ts` | Small to delete, large to wire up | Standalone Fastify + R2 + Redis carousel *image* renderer that nothing imports — the live carousel path is text slides via `generate-carousel`. Recommend deleting until there's a product reason for image carousels. |
| **`process-apify-results` N+1** | `supabase/functions/process-apify-results/index.ts` (~line 385) | Small–medium | Loads all `jobs.source_url` into memory per run, then inserts scraped rows one at a time. Fix: scope the existence check with `.in(...)` and bulk-insert. Admin cron pipeline, not user-facing. |
| **Board adapters skip retry** | `supabase/functions/_shared/boards/getro.ts`, `consider.ts` | Small | Use `_shared/ats/http.ts` `fetchWithRetry` (5xx/429 backoff) instead of plain `postJSON`. Board crawl is cron and resumes from its cursor next run, so transient failures are cheap. |
| **`CandidateStore` split** | `AppSessionStore.swift` | Medium | Store still holds all three roles' ~20 `@Published` props, which feed `NativeRootView`'s per-role closures. Splitting candidate state out means rewiring those closures — do it alongside the employer/admin refactor. |
| **Full DI container** | `SupabaseService.swift` | Medium–large | Services reached via `SupabaseService.shared`; only `ApplyDrawerView`/`FounderEmailSheet` take an injected `CandidateService`. Protocol-extract each service and inject through the view tree so they're mockable. Big diff for a test-only payoff today. |
| **Snapshot / UI tests** | `CarouselFeedCard.swift` (feed card) + `FounderEmailSheet.swift` (compose sheet) | Medium | Needs an external snapshot lib (swift-snapshot-testing via SPM) + baseline images. The `JobTokTests` target is the foundation to add it onto. |
| **Anon-key → publishable-key + RLS audit** | `Config.swift`; `JobTok.xcconfig` | Small–medium | Anon key is public-by-design and RLS is the real boundary, so not urgent. Migrate to Supabase's publishable/secret key model, and decide whether the anon-readable `companies`/`funds`/`carousels` should require auth like `jobs` does. |
| **Founder-email v2** | `send-founder-email/index.ts` (verification, per-company caps), `enrich-company-contacts/index.ts` (re-scrape cadence) | Medium | Ship v1, learn from real reply/bounce rates first. Then: a re-scrape cadence for companies that scraped zero founders, email verification (Hunter/NeverBounce) *before* sending, and a per-company weekly cap so multiple candidates don't all hit the same founder in one week. |
