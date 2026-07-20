# Architecture

## Overview

- **Single file**: everything lives in `index.html` — HTML, CSS, and the full
  JS app in one `<script>` block (~4,900 lines by tournament end).
- **Backend**: Supabase (Postgres). No custom server — the browser client
  talks directly to Supabase via the JS SDK, using row-level operations and
  one Postgres trigger for bracket auto-advancement.
- **Hosting**: GitHub Pages, static file, no build step.
- **Target devices**: primarily mobile (iPhone Safari via WhatsApp-shared
  links). Modals use inline DOM expansion, not CSS-only overlays.

## Data model

```
users        (username, spent, earned)
leagues      (id, name, admin_username, bet_amount jsonb, final_settled_at)
matches      (id, home, away, grp, match_date, kickoff_ist,
              result_home, result_away, resolved, resolved_type,
              resolved_pot, resolved_share, resolved_winners[],
              penalty_winner, winner_team, home_flag, away_flag)
predictions  (match_id, username, pred_home, pred_away, bold)
```

`bet_amount` on `leagues` is a JSON object keyed by stage:
`{"group":100,"r32":200,"r16":300,"qf":500,"sf":1000}` — the `sf` key covers
SF, 3rd place, and Final collectively via `betFor()`'s fallback logic. When
we bumped the Final to ₹1000 on the last day, we updated only this one key —
since 3rd place had already settled at ₹800, the change only affected the
still-unresolved Final.

`resolved_type` values: `exact`, `exact_bold`, `outcome`, `outcome_bold`,
`refund`. `resolved_share` stores the **rounded base (1×) share** — bold
winners' actual payout is computed on the fly as
`round(pot/totalShares × 2)`, not `resolved_share × 2` (see
`SETTLEMENT_AND_AUDIT.md` for why this distinction matters).

## Timezone handling

All user-facing dates/times are IST. `match_date` (e.g. `"Jun 12"`) and
`kickoff_ist` (e.g. `"00:30"`) are both stored in IST directly — there's no
UTC conversion at render time. Predictions open 12:00 PM IST the day before
kickoff and close 5 minutes before.

**Converting fixtures from US ET**: add 9 hours 30 minutes (ET is UTC-4 in
July/EDT; IST is UTC+5:30; 4 + 5.5 = 9.5). If the result crosses midnight,
increment the date. Example: 9:00 PM ET July 11 → 6:30 AM IST July 12.

This offset bit us once — a QF's `match_date` was entered as one day later
than the actual IST date because of an arithmetic slip, causing the app to
show it under the wrong day heading. Always double check against an
independent source (FIFA's own schedule page) when entering knockout
fixtures, since there's no automated fixture feed for future rounds.

## Live scores

[worldcup26.ir](https://worldcup26.ir)`/get/games` (also `/get/groups`,
`/get/teams`). Free, no key, but:

- **Not reachable from a server/bash context** — only works as a client-side
  fetch from the browser (CORS-friendly for browser use, not on Anthropic's
  container network allowlist).
- **Lags significantly for matches that go to extra time** — sometimes 20
  minutes, sometimes multiple hours after real full-time, before the API
  reflects the AET/penalty result. Every knockout match this tournament that
  went to AET needed manual/SQL settlement as a fallback; don't rely on
  auto-settle alone for anything past regular time.
- **Sometimes returns home/away reversed** relative to what's stored in the
  `matches` table. `liveDataFor(m)` tries both `home_away` and `away_home`
  keys and swaps the scores if the reversed key matched — this same fix
  applies everywhere live data is read (match cards, `matchStatus()`,
  auto-settle).

## Knockout bracket auto-advancement (Postgres trigger)

Rather than a cron job or client-side polling to advance the bracket, a
Postgres trigger does it in the same transaction as settlement:

```sql
CREATE TRIGGER trg_advance_bracket
  AFTER UPDATE ON matches
  FOR EACH ROW
  EXECUTE FUNCTION advance_bracket_on_settle();
```

`advance_bracket_on_settle()` fires only on the `resolved: false → true`
transition for QF/SF matches. It determines the winner (from the score, or
`penalty_winner` on a draw), and writes the winner's name + flag into the
next round's `home`/`away` slot via a hardcoded progression map:

```
qf_01 → sf_01.home     qf_02 → sf_01.away
qf_03 → sf_02.home     qf_04 → sf_02.away
sf_01 → fin.home       sf_02 → fin.away
sf_01 (loser) → 3rd.home    sf_02 (loser) → 3rd.away
```

The same trigger also stamps `leagues.final_settled_at = NOW()` when the
match with id `'fin'` resolves — this is what the app checks on every load
to fire the tournament-over celebration banner (see below).

**Why a DB trigger instead of app logic**: it fires regardless of *how* the
match got settled — app Settle button, catch-up auto-settle, or a direct SQL
UPDATE by an admin — so the bracket can never drift out of sync with actual
results, and there's no need to remember a manual "advance the bracket" step
after every knockout match.

**What it does NOT do**: settle payouts. Payout math (pot splitting, bold
multipliers, updating `users.earned`/`spent`) stays in the app's
`settleWithScore()` JS function, or manual SQL when the API is lagging. This
was a deliberate split — bracket progression is low-risk and mechanical
(just copying a winner's name forward), but money math benefits from a human
glancing at the numbers before they're final. See `SETTLEMENT_AND_AUDIT.md`.

## Tournament-over celebration

When `leagues.final_settled_at` is set, `checkFinalSettledPrompt()` runs on
every `renderAll()` call and shows a **full-screen modal to every player**
(once per device, tracked via a `localStorage` key scoped to that specific
`final_settled_at` timestamp) with:

- 🏆 "The tournament is over!"
- **World Cup Champions** card — the actual winning nation's flag + name,
  read from the Final match's result (including penalty-shootout handling
  via `penalty_winner`)
- **League Champion** — the fantasy leaderboard's #1 player by P/L%
- A thank-you message

Only the admin (`ME.username === LEAGUE.admin_username`) additionally sees a
**"🎉 View Tournament Wrap"** button, which jumps to the Admin tab and
auto-triggers the shareable stats image (`screenshotTournamentWrap()`).
Everyone else just gets a "Close" button — the share/export action is
intentionally admin-only since only they can act on it.

## Share images

Two canvas-generated PNGs, both rendered at `scale=3` for pixel density
(WhatsApp's own compression on send is the main quality bottleneck, so a
higher source resolution survives it better than a scale-2 render did):

- **`screenshotStageBreakdown()`** — a compact standings table (per-stage
  P/L columns, total P/L, total bet, P/L%), sorted by P/L% not raw P/L.
- **`screenshotTournamentWrap()`** — richer end-of-tournament matrix: one
  card per player with a stacked bar (exact/outcome/wrong/void, counts drawn
  directly on the colored segments rather than in a separate legend line —
  numbers auto-hide via a width check if a segment is too narrow to fit
  them), participation % and hit rate, each player's single biggest win
  (amount + match + stage), and a center-aligned gold champion banner.

Both should be regenerated via mockup (build an HTML file, screenshot with
Playwright, iterate) before porting layout changes into the actual canvas
code — this was the working pattern for every visual iteration and caught
several issues (wrong sort order, missing columns, tied winners) before they
reached the real function.
