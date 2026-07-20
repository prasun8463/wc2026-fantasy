# Settlement, Payouts & Ledger Audit

## Bet amounts (final, end of tournament)

```
Group          : ₹100
R32            : ₹200
R16            : ₹300
QF             : ₹500
SF / 3rd place : ₹800
Final          : ₹1000   (bumped from ₹800 on the last day)
```

Stored in `leagues.bet_amount` as JSON:
`{"group":100,"r32":200,"r16":300,"qf":500,"sf":1000}`. The `sf` key covers
SF, 3rd, and Final collectively via the app's `betFor()` fallback — when
only the Final needs a different rate than an already-settled 3rd place
match, update the `sf` key; it only affects whichever of those stages is
still unresolved.

To check current values: `SELECT bet_amount FROM leagues LIMIT 1;`

## Bold pick rules

Limits: R32=5, R16=3, QF+SF shared=2, Final+3rd shared=1. Bold winners earn
2× share, non-bold winners earn 1× share.

`resolved_type` values: `exact`, `exact_bold`, `outcome`, `outcome_bold`,
`refund`.

## The correct settlement formula

**This is the single most important thing to get right, and the thing this
tournament's bugs kept circling back to.**

For a settled match with winners split into bold and non-bold groups:

```
totalShares = boldWinnerCount × 2 + nonBoldWinnerCount
base = pot / totalShares
bold winner payout    = round(base × 2)
non-bold winner payout = round(base)
```

Each winner's payout is **individually rounded**, not derived from a shared
floored share value. `resolved_share` in the DB stores `round(base)` — the
non-bold reference value — but a bold winner's actual payout is
`round(base × 2)`, which is **not always exactly `resolved_share × 2`**
(e.g. base=184.615 → `resolved_share`=185, but `round(184.615×2)`=369, not
370). Any code that computes a bold payout as `resolved_share × 2` will be
off by ±1 in cases like this.

### What we used before, and why it was wrong

Original logic: `floor(pot / totalShares)` per share, with the leftover
remainder dumped entirely onto the first bold winner (or first winner if no
bold winner). This was both mathematically unfair (arbitrary recipient of
the remainder) and a source of ledger drift once multiple display locations
started computing payouts slightly differently. Replaced with the
individually-rounded formula above partway through the tournament; **all
historical settled matches were re-audited and corrected** using the new
formula as ground truth (see "Ground-truth reset" below).

### Single source of truth for display

`actualWinnerPayout(m, username, preds)` is the one function every part of
the UI calls to answer "what did this player win on this match" — the
leaderboard, match row badges, the match sheet's all-predictions list, the
player drawer (tapping any player from the leaderboard), and the in-app
audit. Before this consolidation, six separate call sites each computed
payouts slightly differently (some using `resolved_share × 2`, some using
stale rounding logic), which is exactly the kind of drift that's invisible
until someone screenshots two different numbers for the same match.

**When adding any new payout display, call `actualWinnerPayout()`. Do not
recompute the formula inline again.**

## Bug classes hit this tournament (in case they recur)

### 1. `allSame` refund bug
Original settle logic refunded everyone whenever **all** predictors picked
the same outcome, on the theory that a unanimous pick meant nothing to
learn. This is wrong — refunds should only happen when **nobody** picked
the correct outcome. This silently voided legitimate group wins across
several matches (10+ historically) before being caught. Fix: refund only
when zero players match the actual outcome; `allSame` was removed from the
settle logic entirely.

### 2. `resolved_share × 2` used for bold payouts in display code
Six different UI locations independently computed a bold winner's payout as
`resolved_share × 2` instead of the individually-rounded formula. Since
`resolved_share` is the *non-bold* rounded value, this diverges from the
true bold payout whenever the base share has a fractional part that rounds
differently ×1 vs ×2. Fixed by consolidating all six into calls to
`actualWinnerPayout()`.

### 3. Player drawer showing the wrong player's numbers
`showPlayerPopup(username)` — the drawer that opens when tapping any player
row in the leaderboard — had a line computing `actualWinnerPayout(m,
ME.username, ...)` instead of `actualWinnerPayout(m, username, ...)`. Since
`ME.username` is always the logged-in admin, every player's drawer silently
showed the *admin's own* win/loss on each match instead of the viewed
player's. This happened during a bulk find/replace that introduced the
shared helper — see Coding Conventions Rule 7 for the general pattern and
mitigation (try/catch surfacing real errors instead of silent failures).

### 4. `Can't find variable: u` — same root cause, different function
A near-identical stale-variable bug in the match sheet's all-predictions
list: a loop variable was `p` (from `arr.forEach(p => ...)`) but a
leftover reference used `u`. This one threw a hard JS error rather than
silently showing wrong data, and was caught immediately because the render
function was wrapped in try/catch that surfaces the actual error message in
the UI instead of leaving a spinner forever.

### 5. Double-settle races
Three layers of protection are needed, not one:
1. **In-memory lock** — a `SETTLING` Set blocking duplicate calls within one
   browser session.
2. **Fresh DB re-check** — immediately after acquiring the in-memory lock,
   re-fetch `resolved` from the DB before doing any calculation, to catch a
   concurrent session (different tab, different device) that settled while
   this one was still loading.
3. **Conditional DB write** — the actual `UPDATE matches ... WHERE id=? AND
   resolved=false` only succeeds if the match was still unresolved at write
   time. If zero rows are affected, bail out without touching any user
   balances. This is the layer that actually matters if the first two are
   somehow bypassed.

### 6. Live-score API team-order and lag issues
See `ARCHITECTURE.md`'s Live Scores section — `liveDataFor()` must try both
key orderings and swap scores if reversed, and matches going to extra time
need a manual settlement fallback since the API can lag by hours.

### 7. Wrongly-computed match pot
One match (`g01`, Mexico vs South Africa) was settled with `resolved_pot`
recorded as ₹900 when 10 predictions actually existed (should have been
₹1000). The in-app audit was also briefly wrong about this — it recomputed
the "expected" pot from the *current* prediction count rather than trusting
`resolved_pot` as the historical record of what was actually collected at
settle time, which caused a false-positive audit flag on an unrelated
occasion. Both were fixed: the match's `resolved_pot`/`resolved_share` were
corrected and winners credited the difference, and the audit now trusts
`resolved_pot` from the DB rather than recomputing it.

## Ledger audit

Run this whenever balances look suspicious, after any batch settlement, or
routinely at the end of each round. It's stage-aware, round-aware, and uses
the correct rounding formula.

```sql
WITH match_stats AS (
  SELECT m.id, m.grp, m.resolved_type, m.resolved_pot, m.resolved_share, m.resolved_winners,
    SUM(CASE WHEN p.bold AND m.resolved_type IN ('exact_bold','outcome_bold') THEN 1 ELSE 0 END) AS bold_count,
    SUM(CASE WHEN NOT p.bold OR m.resolved_type NOT IN ('exact_bold','outcome_bold') THEN 1 ELSE 0 END) AS nonbold_count
  FROM matches m
  JOIN predictions p ON p.match_id=m.id AND p.username=ANY(m.resolved_winners)
  WHERE m.resolved=true
  GROUP BY m.id, m.grp, m.resolved_type, m.resolved_pot, m.resolved_share, m.resolved_winners
),
user_earned AS (
  SELECT p.username,
    SUM(CASE
      WHEN ms.resolved_type='refund' THEN ms.resolved_share
      WHEN p.bold AND ms.resolved_type IN ('exact_bold','outcome_bold')
        THEN ROUND(ms.resolved_pot::numeric / NULLIF(ms.bold_count*2+ms.nonbold_count,0) * 2)
      ELSE ROUND(ms.resolved_pot::numeric / NULLIF(ms.bold_count*2+ms.nonbold_count,0))
    END) AS correct_earned
  FROM match_stats ms
  JOIN predictions p ON p.match_id=ms.id AND p.username=ANY(ms.resolved_winners)
  GROUP BY p.username
),
user_spent AS (
  SELECT p.username, SUM(
    CASE WHEN id='fin' THEN 1000
      WHEN m.grp IN ('A','B','C','D','E','F','G','H','I','J','K','L') THEN 100
      WHEN m.grp='R32' THEN 200 WHEN m.grp='R16' THEN 300
      WHEN m.grp='QF' THEN 500 WHEN m.grp IN ('SF','Final','3rd') THEN 800
      ELSE 100 END
  ) AS correct_spent
  FROM predictions p JOIN matches m ON m.id=p.match_id AND m.resolved=true
  GROUP BY p.username
)
SELECT u.username,
  u.spent, COALESCE(us.correct_spent,0) AS calc_spent, u.spent-COALESCE(us.correct_spent,0) AS spent_diff,
  u.earned, COALESCE(ue.correct_earned,0) AS calc_earned, u.earned-COALESCE(ue.correct_earned,0) AS earned_diff
FROM users u
LEFT JOIN user_earned ue ON ue.username=u.username
LEFT JOIN user_spent us ON us.username=u.username
ORDER BY u.username;
```

**Note the `CASE WHEN id='fin' THEN 1000` must come first** in the spent
CASE block — Postgres CASE evaluates top-to-bottom, and `fin`'s `grp` value
is `'Final'` which would otherwise match the generic `SF/Final/3rd` = ₹800
branch before reaching a later `id='fin'` check. This exact ordering bug
produced a false universal ₹200 spent_diff for every player when first
auditing the settled Final — worth remembering if a similar stage-specific
override is ever needed again.

**Tolerance**: accept `spent_diff = 0` always (spent should never drift —
it's just bet-amount × predictions-made, no rounding involved). For
`earned_diff`, accept **±1** as clean — this comes from JS `Math.round()`
(rounds 0.5 up) vs PostgreSQL `ROUND()` (banker's rounding, rounds 0.5 to
nearest even) occasionally landing on different integers for the same
fractional share value. Anything beyond ±1, or any nonzero `spent_diff`,
is a real issue worth investigating.

## Ground-truth reset (when drift is found)

Safest fix when `earned` or `spent` has drifted for any reason — resets
directly to the mathematically correct value rather than trying to
reconstruct the sequence of what went wrong:

```sql
UPDATE users u SET earned = e.correct_earned
FROM (
  WITH match_stats AS (
    SELECT m.id, m.resolved_type, m.resolved_pot, m.resolved_share, m.resolved_winners,
      SUM(CASE WHEN p.bold AND m.resolved_type IN ('exact_bold','outcome_bold') THEN 1 ELSE 0 END) AS bold_count,
      SUM(CASE WHEN NOT p.bold OR m.resolved_type NOT IN ('exact_bold','outcome_bold') THEN 1 ELSE 0 END) AS nonbold_count
    FROM matches m JOIN predictions p ON p.match_id=m.id AND p.username=ANY(m.resolved_winners)
    WHERE m.resolved=true
    GROUP BY m.id, m.resolved_type, m.resolved_pot, m.resolved_share, m.resolved_winners
  )
  SELECT p.username,
    SUM(CASE WHEN ms.resolved_type='refund' THEN ms.resolved_share
      WHEN p.bold AND ms.resolved_type IN ('exact_bold','outcome_bold')
        THEN ROUND(ms.resolved_pot::numeric / NULLIF(ms.bold_count*2+ms.nonbold_count,0) * 2)
      ELSE ROUND(ms.resolved_pot::numeric / NULLIF(ms.bold_count*2+ms.nonbold_count,0)) END) AS correct_earned
  FROM match_stats ms JOIN predictions p ON p.match_id=ms.id AND p.username=ANY(ms.resolved_winners)
  GROUP BY p.username
) e WHERE u.username=e.username;
```

Same pattern applies to `spent` — recompute from `predictions × bet_amount`
for resolved matches and overwrite directly.

## Auto-settle diagnostics

The app's "⚡ Run now" debug button (`debugCatchUpSettle()`) logs its
findings to a persistent, copyable, scrollable debug box in the UI. When
auto-settle isn't firing for a finished match, check this log first — it
shows both the primary pass (matching the freshly-fetched API data against
unsettled matches) and a secondary pass (checking `LIVE_SCORES`, the same
source the match cards use for their `FT`/`AET` badges) so you can see
exactly which data source has or hasn't caught up.

If both passes show "not in LIVE_SCORES" or a stale status for a match you
know has finished (per an independent source like a sports news search),
it's the worldcup26.ir API lag — settle manually via SQL rather than
waiting.
