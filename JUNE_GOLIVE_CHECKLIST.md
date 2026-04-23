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

## Step 5 — Enable PROD_MODE (code change)

In `index.html`, find line ~8:

```js
const PROD_MODE = false;
```

Change to:

```js
const PROD_MODE = true;
```

Push to GitHub. This single flag:
- ✅ Removes random Settle button from matches tab (shows "⚡ Auto-settling" instead)
- ✅ Removes random Settle button from admin tab (shows "⚡ Will auto-settle via API")
- ✅ Keeps manual Settle in admin for edge cases (e.g. API score available but auto-settle hasn't fired)
- ✅ Sets auto-settle delay to 15 mins after FT (covers VAR/extra time wrap-up)

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
