# WC2026 Fantasy — June Go-Live Checklist

Complete these steps **in order** before June 11, 2026.
Steps 1–3 can be done any time now. Steps 4–12 run in sequence on go-live day.

---

## API Keys Reference

| Key | Value | Used for |
|---|---|---|
| **Supabase URL** | `https://wxolmlxphwieqvyfuyfu.supabase.co` | Database (all reads/writes) |
| **Supabase Anon Key** | `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...` | Supabase auth (public key, safe to expose) |
| **RapidAPI Key** | `9ccccda5ebmsh35908237b362fe4p12568cjsn6a49fb26955c` | Live scores + fixture import |
| **api-football League ID** | `1` | FIFA World Cup (confirmed valid for v3) |
| **api-football Season** | `2026` | WC2026 season identifier |
| **BSD API Key** | _Not yet registered_ | Step 7 (odds-informed 🎲 — build before June 11) |

**Verify RapidAPI key before June 11:** Log in at https://rapidapi.com, confirm the key is active and the account has not hit monthly limits. Free tier = 100 calls/day — shared across live scores and fixture import.

**Fixture data is already live:** api-football has all 104 WC2026 fixtures available now at `league=1&season=2026`. Safe to import any time after Step 5.

---

## PHASE 1 — Schema & config (do now, safe to re-run any time)

### Step 1 — Schema fixes

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
-- App uses custom auth — RLS was blocking deletes
ALTER TABLE predictions DISABLE ROW LEVEL SECURITY;

-- 1c. Bold Pick column (knockout feature)
ALTER TABLE predictions ADD COLUMN IF NOT EXISTS bold BOOLEAN DEFAULT false;

-- 1d. PROD_MODE column on leagues
ALTER TABLE leagues ADD COLUMN IF NOT EXISTS prod_mode BOOLEAN DEFAULT false;

-- 1e. api_fixture_id (needed for odds feature in Step 7)
ALTER TABLE matches ADD COLUMN IF NOT EXISTS api_fixture_id INTEGER;

-- 1f. Verify all columns exist
SELECT column_name FROM information_schema.columns
WHERE table_name = 'predictions' AND column_name IN ('bold','match_id','username','pred_home','pred_away');

SELECT column_name FROM information_schema.columns
WHERE table_name = 'matches' AND column_name = 'api_fixture_id';

SELECT column_name FROM information_schema.columns
WHERE table_name = 'leagues' AND column_name = 'prod_mode';
```

### Step 2 — Bet amounts

```sql
UPDATE leagues
SET bet_amount = '{"group":100,"r32":200,"r16":300,"qf":500,"sf":800}'
WHERE name = 'HSBC Friends League';

-- Verify
SELECT name, bet_amount FROM leagues;
```

Rationale: Group ₹100 × ~40 matches = ₹4,000 exposure. QF pot = ₹4,000. Final pot = ₹8,000+. A single correct Final prediction reshuffles the entire leaderboard.

---

## PHASE 2 — Reset test data (when April/May testing is fully done)

Run these **in order**, right before inviting real users.

### Step 3 — Delete test users

```sql
-- Check who's in the DB first
SELECT username, email, earned, spent FROM users ORDER BY username;

-- Delete test accounts (keep only prasun84)
DELETE FROM users WHERE username IN ('test1','test2','test3');

-- Verify
SELECT username, email FROM users;
```

> Real users will register via invite code — do not pre-create accounts.

### Step 4 — Clear all test data

```sql
-- 4a. Clear predictions
DELETE FROM predictions;

-- 4b. Reset balances
UPDATE users SET spent = 0, earned = 0;

-- 4c. Unsettle all matches
UPDATE matches SET
  resolved = false, result_home = null, result_away = null,
  resolved_pot = null, resolved_share = null,
  resolved_type = null, resolved_winners = null
WHERE resolved = true;

-- 4d. Delete ALL test fixtures (Apr + May dates)
DELETE FROM matches WHERE match_date LIKE 'Apr%';
DELETE FROM matches WHERE match_date LIKE 'May%';

-- Verify no test dates remain
SELECT DISTINCT match_date FROM matches ORDER BY match_date;
```

---

## PHASE 3 — Import real fixtures & enable production

### Step 5 — Import real WC2026 fixtures (in the app)

1. Open app → log in as **prasun84** (admin)
2. Go to **Admin tab → "Import WC2026 fixtures from API"**
3. Tap **⬇ Import WC2026 fixtures**
4. Wait for: `✓ Imported 104 fixtures`

Notes:
- Fetches all 104 WC2026 fixtures with correct IST kickoff times and group codes (A–L, R32, R16, QF, SF, Final)
- Upserts — safe to run multiple times
- Also stores `api_fixture_id` from api-football (used by Step 7 odds feature)
- Fixture data is already live on api-football. Can run this now.

### Step 6 — Third place match

WC2026 has a 3rd place playoff on **Jul 18**. Check if the import included it:

```sql
SELECT id, home, away, match_date, grp FROM matches WHERE grp = 'Final' ORDER BY match_date;
```

If Jul 18 is missing, add it manually:

```sql
INSERT INTO matches (id, grp, home, away, home_flag, away_flag, match_date, kickoff_ist, resolved)
VALUES ('3rd', 'Final', 'TBD', 'TBD', '🏳️', '🏳️', 'Jul 18', '00:30', false)
ON CONFLICT (id) DO NOTHING;
```

### Step 7 — Build odds-informed 🎲 (code change, build before June 11)

The 🎲 Random button currently uses weighted random scores. For June, wire it to BSD (Bzzoiro Sports Data) market odds so it suggests a probability-informed score instead.

**Register BSD key:** https://sports.bzzoiro.com — free, instant, no card needed.

**Implementation** (full code in previous session):
1. Add `fetchOddsCache()` — single API call at login fetching all upcoming match odds
2. Replace `randomFillPred()` — uses cached odds to pick outcome probabilistically, then generates a realistic score
3. Add `showOddsHint()` — shows `📊 Market odds · H 52% · D 27% · A 21%` below inputs
4. Gate with `if(PROD_MODE) fetchOddsCache()` — never fires during April testing

### Step 8 — Enable PROD_MODE

```sql
UPDATE leagues SET prod_mode = true WHERE name = 'HSBC Friends League';

-- Verify
SELECT name, prod_mode, bet_amount FROM leagues;
```

Takes effect immediately on next page load. No code push needed. This:
- Removes random Settle buttons (shows "⚡ Auto-settling" instead)
- Sets auto-settle delay to 15 min after FT/AET/PEN
- Keeps manual Settle in Admin for edge cases

To roll back: `UPDATE leagues SET prod_mode = false WHERE name = 'HSBC Friends League';`

---

## PHASE 4 — Code changes (push to GitHub before June 11)

### Step 9 — Restore smart landing logic (code change)

Find in `index.html`:
```js
function smartLanding(){
  // PRE-LAUNCH MODE: always land on How to Play
  return 'howto';
```

Replace with:
```js
function smartLanding(){
  const seen = localStorage.getItem('wc2026_seen');
  if(!seen){ localStorage.setItem('wc2026_seen','1'); return 'howto'; }
  return 'lb';
}
```

**Why:** Pre-launch, everyone lands on How to Play. From June 11, returning users land on Leaderboard (more relevant), first-timers still get How to Play.

---

## PHASE 5 — Verify & launch

### Step 10 — Final verification

```sql
-- All should show expected values
SELECT name, bet_amount, prod_mode FROM leagues;
SELECT username, spent, earned FROM users ORDER BY username;
SELECT COUNT(*) AS predictions FROM predictions;
SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE resolved) AS settled FROM matches;
SELECT grp, COUNT(*) AS matches FROM matches GROUP BY grp ORDER BY grp;
```

Expected:
- `bet_amount` = `{"group":100,"r32":200,"r16":300,"qf":500,"sf":800}`
- `prod_mode` = `true`
- `predictions` = 0, `settled` = 0
- Groups A–L: 4 each (48) + R32: 16 + R16: 8 + QF: 4 + SF: 2 + Final: 1–2 = 79–80 knockouts

### Step 11 — Verify password recovery

```sql
-- All real users must have email set for forgot-password to work
SELECT username, email FROM users WHERE email IS NULL OR email = '';
```

The forgot-password flow is all in-app (no email sent) — password displays on screen. Tell users to note their password when registering.

### Step 12 — League invite code

```sql
SELECT name, admin_username, code FROM leagues;
```

Share the invite code + URL in WhatsApp:
`https://prasun8463.github.io/wc2026-fantasy`

Use Admin tab → "Today's match reminder" → Copy to generate the match-day message.

### Step 13 — Reset localStorage on your test device

In Safari console (Develop → Show JavaScript Console):
```js
Object.keys(localStorage)
  .filter(k => k.startsWith('wc2026_'))
  .forEach(k => localStorage.removeItem(k));
```

Clears: `wc2026_seen`, `wc2026_ranks_*`, `wc2026_user`, `wc2026_bold_seen`

---

## Auto-settle flow (June, no action needed — already in code)

1. Admin must be logged in on match days (polling runs every 5 min)
2. API returns `FT` / `AET` / `PEN` → timestamp recorded
3. **15 min later** → `autoSettleFinished()` settles with real API score
4. `loadAll()` + `renderAll()` → leaderboard updates for all players
5. Toast: `✓ Brazil 2–1 France · prasun84 won ₹4000`

**Knockout matches (R32 onwards):** Auto-settle uses `AET`/`PEN` status correctly. Fallback duration = 150 min (covers ET + penalties). Manual settle available in Admin tab if API data is delayed.

---

## Emergency reference

### Repair balances (if settlement bug occurs)

```sql
UPDATE users SET spent = 0, earned = 0;

UPDATE users u SET spent = COALESCE((
  SELECT COUNT(*) * (SELECT (bet_amount::json->>'group')::int FROM leagues WHERE id = u.league_id)
  FROM predictions p
  JOIN matches m ON m.id = p.match_id
  WHERE p.username = u.username AND m.resolved = true
), 0) WHERE u.league_id IS NOT NULL;

UPDATE users u SET earned = COALESCE((
  SELECT SUM(m.resolved_share)
  FROM matches m
  WHERE m.resolved = true AND u.username = ANY(m.resolved_winners)
), 0) WHERE u.league_id IS NOT NULL;

SELECT username, spent, earned, earned-spent AS pl FROM users ORDER BY pl DESC;
```

### WhatsApp Business

Admin tab → "Today's match reminder" → Copy or Open in WhatsApp. Works with personal WhatsApp — no Business API needed.

---

## Pre-launch day checklist (June 10)

- [ ] Step 1 SQL run (schema fixes, bold column, api_fixture_id, prod_mode column)
- [ ] Step 2 SQL run (bet amounts — HSBC Friends League)
- [ ] Step 3 SQL run (test users deleted)
- [ ] Step 4 SQL run (test data cleared, Apr+May fixtures deleted)
- [ ] Step 5 done (104 real fixtures imported via Admin tab)
- [ ] Step 6 checked (3rd place match Jul 18 present)
- [ ] Step 7 built (odds-informed 🎲 with BSD API key)
- [ ] Step 8 SQL run (PROD_MODE = true)
- [ ] Step 9 code pushed (smart landing restored)
- [ ] Step 10 verify queries all clean
- [ ] Step 11 all real users have email
- [ ] Step 12 invite code shared with friends
- [ ] Step 13 localStorage cleared on your device
- [ ] RapidAPI key confirmed active (test at rapidapi.com)
- [ ] App opens → lands on How to Play for fresh session
- [ ] Admin sees 104 fixtures with correct IST times
- [ ] Bet amounts correct per stage (₹100 group → ₹800 SF/Final)
- [ ] One test prediction placed + settled → leaderboard updates correctly
