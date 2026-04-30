# WC2026 Fantasy — June Go-Live Checklist

Complete these steps in order before June 11, 2026.

---

## Step 1 — Schema fixes (run now, safe to re-run)

In Supabase SQL Editor:

```sql
-- 1a. Unique constraint on predictions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'predictions_match_username_unique'
  ) THEN
    ALTER TABLE predictions
      ADD CONSTRAINT predictions_match_username_unique
      UNIQUE (match_id, username);
  END IF;
END $$;

-- 1b. Disable RLS on predictions
-- App uses custom auth (not Supabase Auth) — RLS was blocking deletes
ALTER TABLE predictions DISABLE ROW LEVEL SECURITY;
```

---

## Step 2 — Bet amounts (run now)

```sql
UPDATE leagues
SET bet_amount = '{"group":100,"r32":200,"r16":300,"qf":500,"sf":800}'
WHERE name = 'prasun84''s League';
```

Rationale:
- Group: ₹100 base × 40 matches = ₹4,000 total exposure
- Knockout stages scale by scarcity — QF pot = ₹4,000, Final pot = ₹8,000+
- A single correct Final prediction can swing the leaderboard completely

---

## Step 3 — Reset all April test data

Run this when April testing is fully done, right before inviting real users.

```sql
-- 3a. Clear all predictions
DELETE FROM predictions;

-- 3b. Reset user balances
UPDATE users SET spent = 0, earned = 0;

-- 3c. Unsettle all matches (keep fixtures, wipe results)
UPDATE matches SET
  resolved         = false,
  result_home      = null,
  result_away      = null,
  resolved_pot     = null,
  resolved_share   = null,
  resolved_type    = null,
  resolved_winners = null
WHERE resolved = true;

-- 3d. Delete April test fixtures
DELETE FROM matches WHERE match_date LIKE 'Apr%';
```

---

## Step 4 — Import real fixtures (in the app)

1. Open the app, log in as admin
2. Go to **Admin tab → "Import WC2026 fixtures from API"**
3. Tap **⬇ Import WC2026 fixtures**
4. Wait for success message: "✓ Imported 104 fixtures"

Notes:
- Fetches all 104 WC2026 fixtures from api-football (league=1, season=2026)
- Upserts with correct IST kickoff times and group codes (A–L, R32, R16, QF, SF, Final)
- Safe to re-run — upsert not insert, no duplicates
- If API doesn't have data yet, it will say so — re-try closer to June 11

---

## Step 5 — Enable PROD_MODE (SQL only, no code change needed)

```sql
-- Add prod_mode column if it doesn't exist
ALTER TABLE leagues ADD COLUMN IF NOT EXISTS prod_mode BOOLEAN DEFAULT false;

-- Flip to true before June go-live
UPDATE leagues SET prod_mode = true WHERE name = 'prasun84''s League';

-- Verify
SELECT name, prod_mode FROM leagues;
```

`prod_mode` is read from the DB at login — no code push needed, takes effect immediately on next page load.

This single flag:
- ✅ Removes random Settle button from matches tab (shows "⚡ Auto-settling" instead)
- ✅ Removes random Settle button from admin tab (shows "⚡ Will auto-settle via API")
- ✅ Keeps manual Settle in admin for edge cases (e.g. API score available but auto-settle hasn't fired)
- ✅ Sets auto-settle delay to 15 mins after FT (covers VAR/extra time wrap-up)

To roll back (e.g. during testing):
```sql
UPDATE leagues SET prod_mode = false WHERE name = 'prasun84''s League';
```

---

## Step 6 — Verify clean state

```sql
-- All should show clean / expected values
SELECT name, bet_amount FROM leagues;
SELECT username, spent, earned FROM users ORDER BY username;
SELECT COUNT(*) AS predictions FROM predictions;
SELECT COUNT(*) AS total_matches,
       COUNT(*) FILTER (WHERE resolved) AS settled
FROM matches;
SELECT grp, COUNT(*) AS matches
FROM matches
GROUP BY grp
ORDER BY grp;
```

Expected:
- `bet_amount` = `{"group":100,"r32":200,"r16":300,"qf":500,"sf":800}`
- All users: `spent = 0`, `earned = 0`
- `predictions` = 0
- `total_matches` = 104, `settled` = 0
- Groups A–L: 4 matches each (48 total) + R32: 16 + R16: 8 + QF: 4 + SF: 2 + Final: 1 = 79 knockout + 48 group = but knockouts are TBD until group stage ends

---

## Auto-settle flow (June, already in code)

No action needed — this runs automatically:

1. Live polling runs every 5 mins during match windows (admin must be logged in)
2. API returns `FT` / `AET` / `PEN` → timestamp recorded
3. **15 minutes later** → `autoSettleFinished()` runs
4. Settles with real API score via `settleWithScore()`
5. `loadAll()` + `renderAll()` fires → leaderboard, stage breakdown, recent results all update
6. Toast shown to admin: "✓ Auto-settled: Brazil 2–1 France"

> **Important:** Keep the app open on match days (admin account) for auto-settle to fire.
> If the admin session is closed, matches can still be manually settled via Admin tab
> once the real FT score is visible.

---

## RapidAPI key check

Verify the key in `index.html` is still active before June 11:

```
Key: 9ccccda5ebmsh35908237b362fe4p12568cjsn6a49fb26955c
Host: api-football-v1.p.rapidapi.com
League: 1 (FIFA World Cup)
Season: 2026
```

Test at: https://rapidapi.com/api-sports/api/api-football

---

## Step 7 — Odds-informed 🎲 prediction hint (build before June 11)

### What it does
The 🎲 Random button in the predict form currently generates a purely weighted random score. From June, it should suggest a score informed by real market odds — so a user who doesn't know the matchup gets a sensible starting point, not just noise.

### API choice: BSD (Bzzoiro Sports Data)
- Free, no rate limits, no credit card: https://sports.bzzoiro.com
- Returns 1X2 odds (home win / draw / away win) for all upcoming matches
- Multi-bookmaker aggregated — more reliable than a single bookmaker
- No fixture ID mapping needed — matches by team name

### Architecture: fetch once, cache for session
One API call at login (or first 🎲 tap) fetches all upcoming WC2026 matches with odds. Cached in memory as `ODDS_CACHE`. Every subsequent 🎲 tap reads from cache — zero additional API calls. No quota risk.

### Implementation plan

**1. Fetch and cache odds at session start (add to `launchApp`):**
```javascript
let ODDS_CACHE = {}; // { 'TeamA_TeamB': { home, draw, away } }

async function fetchOddsCache(){
  try {
    const res = await fetch('https://sports.bzzoiro.com/api/events/?sport=soccer', {
      headers: { 'Authorization': 'Token YOUR_BSD_KEY' }
    });
    const data = await res.json();
    (data.results || []).forEach(e => {
      if(!e.odds_home) return;
      const key = e.home_team + '_' + e.away_team;
      ODDS_CACHE[key] = {
        home: parseFloat(e.odds_home),
        draw: parseFloat(e.odds_draw),
        away: parseFloat(e.odds_away)
      };
    });
    console.log('Odds cache loaded:', Object.keys(ODDS_CACHE).length, 'matches');
  } catch(err) {
    console.log('Odds fetch failed, using random fallback:', err.message);
  }
}
```

**2. Replace `randomFillPred` with odds-aware version:**
```javascript
function randomFillPred(mid){
  const m = MATCHES.find(x => x.id === mid);
  const oddsKey = Object.keys(ODDS_CACHE).find(k => {
    const [h, a] = k.split('_');
    return m.home.includes(h) || h.includes(m.home);
  });
  const odds = oddsKey ? ODDS_CACHE[oddsKey] : null;

  let h, a;
  if(odds){
    // Convert to implied probabilities (remove bookmaker margin)
    const raw = [1/odds.home, 1/odds.draw, 1/odds.away];
    const total = raw.reduce((s,v) => s+v, 0);
    const [pH, pD, pA] = raw.map(v => v/total);

    // Pick outcome based on probability
    const r = Math.random();
    let outcome;
    if(r < pH) outcome = 'home';
    else if(r < pH + pD) outcome = 'draw';
    else outcome = 'away';

    // Generate realistic score for that outcome
    [h, a] = scoreForOutcome(outcome);
    // Flash with odds label
    showOddsHint(mid, odds, outcome);
  } else {
    [h, a] = randomScore(); // weighted random fallback
  }

  document.getElementById('sh_ph_'+mid).value = h;
  document.getElementById('sh_pa_'+mid).value = a;
  [document.getElementById('sh_ph_'+mid), document.getElementById('sh_pa_'+mid)].forEach(el => {
    if(!el) return;
    el.style.borderColor = 'rgba(212,160,23,.7)';
    setTimeout(() => el.style.borderColor = '', 600);
  });
}

function scoreForOutcome(outcome){
  const homeWin = [[1,0,15],[2,0,12],[2,1,14],[3,0,7],[3,1,8],[3,2,5],[1,0,15]];
  const draw    = [[0,0,20],[1,1,35],[2,2,15],[3,3,5]];
  const awayWin = [[0,1,15],[0,2,12],[1,2,14],[0,3,7],[1,3,8],[2,3,5]];
  const weights = outcome==='home'?homeWin : outcome==='draw'?draw : awayWin;
  const total = weights.reduce((s,w) => s+w[2], 0);
  let r = Math.floor(Math.random()*total);
  for(const [h,a,w] of weights){ r-=w; if(r<0) return [h,a]; }
  return [1,0];
}

function showOddsHint(mid, odds, chosenOutcome){
  const el = document.getElementById('sh_odds_hint_'+mid);
  if(!el) return;
  const fmt = v => (v > 0 ? '+' : '') + Math.round(v) + '%';
  const raw = [1/odds.home, 1/odds.draw, 1/odds.away];
  const total = raw.reduce((s,v) => s+v, 0);
  const [pH, pD, pA] = raw.map(v => Math.round(v/total*100));
  el.innerHTML = `<span style="font-size:10px;color:var(--muted)">📊 Market odds · `
    + `<span style="${chosenOutcome==='home'?'color:var(--gold)':''}">H ${pH}%</span> · `
    + `<span style="${chosenOutcome==='draw'?'color:var(--gold)':''}">D ${pD}%</span> · `
    + `<span style="${chosenOutcome==='away'?'color:var(--gold)':''}">A ${pA}%</span></span>`;
}
```

**3. Add odds hint placeholder to predict form (inside `openMatchSheet`):**
```javascript
// Add this div after the score inputs, before the buttons
`<div id="sh_odds_hint_${mid}" style="margin-top:6px;min-height:16px"></div>`
```

**4. Call `fetchOddsCache()` in `launchApp` after `loadAll()`:**
```javascript
await loadAll();
if(PROD_MODE) fetchOddsCache(); // only in June — no data in April
goTab('matches');
```

### BSD API key
Register at https://sports.bzzoiro.com — free, instant, no card needed.
Store key in the same config section as the RapidAPI key in `index.html`.

### Fallback behaviour
- If BSD fetch fails (network error, key issue) → silent fallback to weighted random
- If match not found in cache (e.g. knockout fixture teams TBD) → weighted random
- April testing (`PROD_MODE = false`) → always weighted random, BSD never called

### UX result
User taps 🎲 on "Brazil vs France" → sees 2–1 pre-filled with `📊 Market odds · H 52% · D 27% · A 21%` below the inputs → can accept or adjust → taps Predict. Informed but not prescriptive.

---

## Step 8 — Clean up test users before inviting real users

After resetting match/prediction data in Step 3, also clean up test accounts:

```sql
-- View current test users (adjust usernames as needed)
SELECT username, email, earned, spent FROM users ORDER BY username;

-- Delete test accounts (keep only real admin account)
DELETE FROM users WHERE username IN ('test1','test2','test3');

-- If test users have a league, their removal orphans predictions — already cleared in Step 3
-- Verify only real users remain
SELECT username, email FROM users;
```

> **Note:** Real users will register themselves via the app using your league invite code. Don't pre-create their accounts.

---

## Step 9 — Reset localStorage for first-run experience

Real users on new devices will automatically get the How to Play stepper (first login detection via `wc2026_seen` key in localStorage). However if you are testing on the same device/browser used for April testing, clear your own localStorage first so you see what real users see:

In Safari console (Develop → Show JavaScript Console):
```js
// Clear all WC2026 app keys
Object.keys(localStorage)
  .filter(k => k.startsWith('wc2026_'))
  .forEach(k => localStorage.removeItem(k));
```

This resets:
- `wc2026_seen` → triggers How to Play on next login
- `wc2026_ranks_*` → clears rank movement history
- `wc2026_user` → clears remembered username

---

## Step 10 — May test matches cleanup

If you ran May-dated test fixtures (May 1–2 for SF/Final), these also need deletion in Step 3:

```sql
-- Extend the April cleanup to also cover May test fixtures
DELETE FROM matches WHERE match_date LIKE 'May%';

-- Verify no test dates remain
SELECT DISTINCT match_date FROM matches ORDER BY match_date;
```

---

## Step 11 — Verify password recovery flow works for real users

The forgot password flow uses the `email` column on the `users` table. Verify before inviting real users:

```sql
-- Check all real users have email set
SELECT username, email FROM users WHERE email IS NULL OR email = '';
```

- If any users have no email, they cannot use forgot password — ask them to set it via registration or update manually
- The flow: username + email → random 8-char password shown on screen → user logs in → no email is actually sent (all in-app)
- Communicate this to real users so they know to note their password

---

## Step 12 — League invite code & admin setup

Before sharing the app with real users:

1. **Verify invite code** — go to League tab, note the 6-char invite code to share with friends
2. **Verify admin username** — the admin is whoever registered first (without invite code). Confirm it's `prasun84` via:
   ```sql
   SELECT name, admin_username, code FROM leagues;
   ```
3. **Share the app URL** with invite code: `https://prasun8463.github.io/wc2026-fantasy`
4. **WhatsApp message** — use the League tab → "Invite others" button to generate a ready-to-send WhatsApp message with the code

---

## Step 13 — WhatsApp Business (optional, for June match-day reminders)

The admin tab has a WhatsApp reminder generator that creates match-day messages. Currently uses WhatsApp personal (wa.me links). For June, if you want to send reminders to the group:

- The feature works with personal WhatsApp — just tap "Send reminder" in Admin tab on match day
- WhatsApp Business API (for programmatic sending) was discussed but is NOT implemented — would require approval, Meta Business account, and a paid API. Not needed unless you want fully automated reminders
- **Current behaviour**: Admin taps button → WhatsApp opens with pre-filled message → manually send to league group

No action needed unless you want to upgrade to full automation.

---

## Step 14 — Third place match

WC2026 has a third place playoff on July 18 (day before the Final). Currently your DB has SF and Final but no third place fixture. Add it after importing fixtures in Step 4:

```sql
-- Add third place match after fixture import
-- Only needed if you want users to predict the 3rd place playoff
INSERT INTO matches (id, grp, home, away, home_flag, away_flag, match_date, kickoff_ist, resolved)
VALUES ('3rd', 'Final', 'TBD', 'TBD', '🏳️', '🏳️', 'Jul 18', '00:30', false)
ON CONFLICT (id) DO NOTHING;
```

> The api-football import may already include this — check after Step 4 before adding manually.

---

## Step 15 — Repair balances SQL (if needed)

If after going live any user balances look wrong (e.g. after a settle bug or manual DB edit), run this to recompute from scratch:

```sql
-- Recompute all balances from actual prediction/settlement data
UPDATE users SET spent = 0, earned = 0;

UPDATE users u SET spent = COALESCE((
  SELECT COUNT(*) * b.bet_per_match
  FROM predictions p
  JOIN matches m ON m.id = p.match_id
  CROSS JOIN (
    SELECT (bet_amount::json->>'group')::int AS bet_per_match
    FROM leagues WHERE id = u.league_id
  ) b
  WHERE p.username = u.username AND m.resolved = true
), 0)
WHERE u.league_id IS NOT NULL;

UPDATE users u SET earned = COALESCE((
  SELECT SUM(m.resolved_share)
  FROM matches m
  WHERE m.resolved = true
  AND u.username = ANY(m.resolved_winners)
), 0)
WHERE u.league_id IS NOT NULL;

-- Verify
SELECT username, spent, earned, earned-spent AS pl FROM users ORDER BY pl DESC;
```

---

## Step 16 — api_fixture_id column (needed for Step 7 odds feature)

When building the odds-informed 🎲 button (Step 7), the fixture import needs to store api-football's internal fixture ID so odds can be fetched per match. Add this column before running the fixture import:

```sql
ALTER TABLE matches ADD COLUMN IF NOT EXISTS api_fixture_id INTEGER;
```

Then update the `importFixturesFromAPI()` function in index.html to store `fixture.fixture.id` into this column during import. The odds endpoint takes this ID as a parameter.

---

## Pre-launch verification checklist

Run through all of these the day before June 11:

- [ ] Step 1 SQL run (unique constraint + RLS disabled)
- [ ] Step 2 SQL run (bet amounts correct)
- [ ] Step 3 SQL run (all test data cleared)
- [ ] Step 10 SQL run (May test fixtures deleted)
- [ ] Step 8 SQL run (test users deleted)
- [ ] Step 4 done (104 real fixtures imported from API)
- [ ] Step 5 SQL run (PROD_MODE = true)
- [ ] Step 6 verify query shows clean state
- [ ] Step 9 done (localStorage cleared on your test device)
- [ ] Step 14 checked (third place match present)
- [ ] Step 11 done (all real users have email set)
- [ ] Step 12 done (invite code verified, shared with friends)
- [ ] RapidAPI key tested and active
- [ ] App opens correctly, lands on How to Play for fresh session
- [ ] Admin can see all fixtures, betting amounts correct per stage
- [ ] One test prediction made and settled to verify full flow

---

## Step 17 — Add `bold` column to predictions (for Bold Pick feature)

```sql
-- Add bold column for the knockout Bold Pick feature
ALTER TABLE predictions ADD COLUMN IF NOT EXISTS bold BOOLEAN DEFAULT false;

-- Verify column exists
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'predictions' AND column_name = 'bold';
```

The Bold Pick feature is enabled in code for all knockout stages (R32, R16, QF, SF/Final). Each player gets one bold pick per stage. If they nail the exact score on a bold pick, they take the entire pot (no splitting with other exact pickers). Loss is unchanged.

The DB stores `resolved_type='exact_bold'` instead of `exact` when a bold won the pot — used in stats and badges.

---

## Step 18 — Knockout settlement window for extra time + penalties

**Already handled in code** — but worth verifying in production:

- `MATCH_DURATION_MS` (105 min) used for group stage fallback if API has no live data
- `KNOCKOUT_DURATION_MS` (150 min = 90 + 30 ET + 30 penalties) used for R32 onwards
- Auto-settle waits for `FT`, `AET`, or `PEN` status from api-football before firing
- Auto-settle delay after FT/AET/PEN: 15 min in PROD_MODE (covers VAR review, post-match procedures)

**Verification on first knockout match in June:**
1. Watch a live R32 match in the app
2. If it goes to extra time, verify the match shows `live` (not finished) status throughout ET
3. After penalties, verify status badge shows `PEN` and final score reflects penalty total
4. Confirm auto-settle fires ~15 min after PEN status

**Manual fallback if auto-settle misbehaves:** Admin can use the Settle button on the match row with the actual final score (including penalty result, e.g. for a 1-1 match decided 4-3 on penalties, enter 1-1 and let the API status indicate it was PEN).
