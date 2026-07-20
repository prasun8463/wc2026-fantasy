# Changelog

Chronological record of features and fixes across the WC2026 tournament.
Grouped by theme rather than exact dates, since work happened across many
sessions as the tournament progressed.

## Settlement correctness

- Fixed the `allSame` refund bug — matches were wrongly voided whenever all
  predictors happened to pick the same outcome, instead of only when nobody
  got it right. Retroactively re-audited and corrected ~10 historically
  wrongly-voided matches.
- Replaced `floor(pot/shares)` + remainder-dumped-on-first-winner with
  individually-rounded payouts per winner (`round(base × multiplier)`).
  Re-settled every historical match under the new formula and reset all
  user balances to ground truth.
- Consolidated six different payout-display code paths (leaderboard, match
  row badge, match sheet, player drawer, modal, audit) into a single
  `actualWinnerPayout()` function, eliminating drift between what different
  parts of the UI showed for the same match.
- Added three-layer double-settle protection: in-memory lock, fresh DB
  re-check after acquiring the lock, and a conditional DB write that bails
  if the match was already resolved by a concurrent session.
- Fixed a wrongly-recorded pot on one early match (`g01`) where 10
  predictions existed but only 9 players' worth of stake was recorded as
  the pot; corrected the pot, share, and winner credits.

## Bug fixes from refactors

- Fixed the player drawer (`showPlayerPopup`) always showing the logged-in
  admin's own win/loss instead of whichever player's row was tapped — a
  stale `ME.username` reference left behind by an earlier bulk
  find/replace.
- Fixed a hard JS error (`Can't find variable: u`) in the match sheet's
  all-predictions list from the same class of bug — a stale loop-variable
  reference. Caught immediately because the render function was wrapped in
  try/catch that surfaces real errors in the UI instead of leaving a silent
  spinner.

## Live scores & auto-settle

- Fixed KO-stage status mapping so finished matches that went to extra time
  or penalties correctly map to `AET`/`PEN` status (with penalty scores
  attached) instead of a generic `FT`, so `autoSettleFinished` recognizes
  them.
- Fixed `liveDataFor(m)` to try both `home_away` and `away_home` key
  orderings against the live-score API's response, swapping scores when the
  API returned teams in reversed order relative to the DB. This was
  breaking both score display and auto-settle matching for several matches.
- Added a secondary settlement pass (checking `LIVE_SCORES` directly, not
  just the freshly-fetched API response) to both the automatic catch-up
  settle and the manual "⚡ Run now" debug button, since the two data
  sources sometimes disagreed on whether a match was finished.
- Made the debug settle log persistent, scrollable, and copyable in the UI
  for easier diagnosis when auto-settle silently fails.
- Added `penalty_winner` handling throughout — reading penalty shootout
  results from the live API first, falling back to a manually-set DB column
  when the API had already stopped reporting a since-finished match.

## Knockout bracket

- Fixed the bracket display which was missing R16→QF winner slots entirely
  (jumped straight from R32 to QF); expanded the grid and added the missing
  columns.
- Fixed the bracket display which similarly had no SF column at all,
  jumping straight from QF to Final; expanded from a 7-column to 9-column
  grid layout to show both semifinal matchups.
- Built and deployed a Postgres trigger (`advance_bracket_on_settle`) that
  automatically writes a knockout winner's name into the next round's DB
  row the instant that match is marked resolved, and the loser into 3rd
  place for semifinal matches — replacing what would otherwise be a manual
  SQL update after every knockout match.
- Same trigger stamps `leagues.final_settled_at` when the Final resolves,
  driving the tournament-over celebration banner.
- Manually populated each knockout round's fixtures (teams, IST kickoff
  times) as they became mathematically determined, cross-checked against
  independent sources; caught and fixed one date entry error where a QF's
  `match_date` was one day off from its actual IST calendar date.

## Ledger integrity & auditing

- Built a definitive, stage-aware, round-aware SQL audit query comparing
  DB `spent`/`earned` against values recomputed from scratch — used
  repeatedly throughout the tournament to catch and fix drift.
- Fixed the audit's own pot-calculation logic, which was recomputing an
  "expected" pot from the *current* prediction count instead of trusting
  the historically-recorded `resolved_pot`, causing a false-positive flag
  in one case.
- Fixed a CASE-statement ordering bug in the audit query itself when
  auditing the Final at its bumped ₹1000 rate — a generic
  `grp IN ('SF','Final','3rd')` branch was matching before a more specific
  `id='fin'` branch, since Postgres CASE evaluates top-to-bottom.
- Tuned the audit's tolerance to accept ±1 differences on `earned` as
  expected JS-vs-Postgres rounding noise (`Math.round` rounds 0.5 up;
  Postgres `ROUND` uses banker's rounding), rather than flagging every
  such case as an error.

## Shareable images

- Built a canvas-rendered standings image (stage-by-stage P/L breakdown,
  total bet, P/L%), sorted correctly by P/L% rather than raw P/L.
- Increased render scale (2x → 3x) and font sizes across the board after
  real-world testing showed WhatsApp's compression softened the original
  smaller text.
- Built a richer end-of-tournament "Tournament Wrap" image: per-player
  cards with a stacked exact/outcome/wrong/void bar, participation % and
  hit rate, and each player's single biggest win of the tournament.
- Iterated the Wrap's layout multiple times based on real generated
  screenshots — removed a redundant "biggest win" banner (info already
  shown per-card), center-aligned the champion banner, moved the
  exact/outcome/wrong/void counts to be drawn directly on the bar segments
  instead of a separate text line (with a width check to auto-hide numbers
  that wouldn't fit their segment), and tightened spacing for a more
  compact, legible result.
- Every visual change was mocked up as a standalone HTML file and
  screenshotted via Playwright before being ported into the real canvas
  code — caught several issues (wrong sort order dropped in a mockup,
  missing columns, a tied "biggest win" silently showing only one of two
  winners) before they reached the shipped version.

## Tournament-close features

- Bumped the Final's stake to ₹1000 (from the SF/3rd rate of ₹800) as a
  send-off for the last match, via a single `bet_amount.sf` key update
  that only affected the still-unresolved Final since 3rd place had
  already settled.
- Built the tournament-over celebration banner: shown to every player once
  per device, displaying the actual World Cup champion (flag + nation,
  read from the Final's result including penalty-shootout handling) and
  the fantasy league's top player; admin additionally gets a button to
  generate the shareable Tournament Wrap image.
- Considered and explicitly declined a participation-threshold guardrail
  for the leaderboard (to stop a low-participation player with one lucky
  big win from outranking consistent, high-participation players) — real
  data showed the concern was legitimate in principle but didn't change
  the actual final standings, so it was mocked up for reference but not
  built into the shipped app.
