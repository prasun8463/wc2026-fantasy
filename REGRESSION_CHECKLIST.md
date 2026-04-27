
---

## Security & Code Quality Audit (Apr 2026)

Results from full static analysis of index.html. Run these checks after any major refactor.

### Security

- [ ] `esc()` function present in code — HTML-escapes usernames before innerHTML injection
- [ ] All username insertions in standings, story highlights, player expand use `esc(username)` not raw `username`
- [ ] No new `innerHTML = ... + username + ...` patterns added without `esc()`
- [ ] Supabase anon key and RapidAPI key still scoped correctly (anon key is intentionally public — verify RLS is still active on users/leagues tables)
- [ ] No passwords stored in localStorage (only `username`, `wc2026_seen`, `wc2026_ranks_*` keys)
- [ ] Client-side SHA-256 hash used for passwords — acceptable for this use case but no salt used. Not a regression item, just documented.

### Functional

- [ ] `renderDash()` is not called anywhere (function was removed — verify no stray calls)
- [ ] `betFor()` correctly parses JSON string from DB for all stages (group=100, r32=200, r16=300, qf=500, sf=800)
- [ ] `matchStatus()` returns `'future'` for TBD matches (home==='TBD' || away==='TBD')
- [ ] `settle()` never fires with score 0–0 when inputs are empty — uses `settleRandom()` fallback when no live data
- [ ] `calcRoundStats()` returns `{bet:0, won:0, pl:0}` for users with no league — no undefined/.bet crashes
- [ ] `renderAll()` only re-renders active tab + LB + matches (not all 6 tabs simultaneously)

### Performance

- [ ] `loadAll()` fetches league → members → matches → predictions sequentially — acceptable at current scale. If league grows beyond 20 users, consider parallelising with `Promise.all`
- [ ] `renderLB()` called max 8 times per settle cycle — acceptable. If sluggish, add a 100ms debounce
- [ ] `groupsLastFetched` resets to 0 after `loadAll()` so Tournament tab re-renders with fresh data
- [ ] File size stays under 250KB — check with `wc -c index.html` before each push

### Code Quality Constants

- [ ] `IST_OFFSET_MS`, `KICKOFF_CUTOFF_MS`, `MATCH_DURATION_MS` constants used in matchStatus — not hardcoded magic numbers
- [ ] `dateKey()` shared utility used for date comparisons — not inline month maps
- [ ] `MONTH_MAP`, `MONTH_NAMES`, `MONTH_NUM` used as shared constants — not redeclared per function

### Known Accepted Risks (not regression items)

- API keys in source: Supabase anon key is designed to be public. RapidAPI key has rate limits as natural protection.
- Client-side password hashing: SHA-256 without salt. Acceptable for a friends-league app. Not production auth.
- `div` elements with onclick: 25+ non-keyboard-navigable elements. Mobile-first app, acceptable.
- Single 173KB file: No code splitting. Acceptable for current 8–10 user scale.
- Score validation client-side only: Admin-only feature, low risk.
