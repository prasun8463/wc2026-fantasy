---
name: wc2026-fantasy
description: Use when editing or building features for the WC2026 Fantasy Predictor app — a single-page index.html hosted on GitHub Pages with a Supabase backend. Covers architecture, coding conventions, timezone handling, common pitfalls, and the mandatory pre-commit checklist. Trigger on any mention of wc2026, fantasy predictor, match predictions, fixture dates, Supabase match/prediction tables, or the GitHub repo prasun8463/wc2026-fantasy.
---

# WC2026 Fantasy Predictor — Coding Conventions & Pitfall Prevention

## Architecture

- **Single file**: Everything lives in one `index.html` — HTML, CSS, and ~3500 lines of JS in a single `<script>` block.
- **Backend**: Supabase (PostgreSQL). Tables: `users`, `leagues`, `matches`, `predictions`.
- **Hosting**: GitHub Pages at `prasun8463.github.io/wc2026-fantasy`.
- **Live scores**: api-football via api-sports.io (free tier, 100 calls/day).
- **Timezone**: All user-facing dates and times are in IST (UTC+5:30). The DB stores `match_date` (e.g. "Jun 12") and `kickoff_ist` (e.g. "00:30") both in IST.
- **Target devices**: Primarily mobile (iPhone Safari). All UI must work on narrow viewports. Modals use inline DOM expansion, not CSS overlays (Safari compatibility).


## RULE 1 — No complex JS in inline onclick inside innerHTML strings

**The #1 source of silent runtime bugs in this codebase.**

### The problem
When JS builds an HTML string that gets injected via `innerHTML`, any `onclick="..."` attribute is parsed TWICE:
1. By the JS engine (as a string literal)
2. By the HTML parser (as an attribute value)
3. By the JS engine again (when the click fires)

Escaping breaks silently at step 2 or 3. `new Function()` and `node --check` only test step 1.

### The rule
```
NEVER: onclick="someObj.method({key:'value'})"     inside an innerHTML string
NEVER: onclick="fn('${var}')"                       with nested template literals
NEVER: onclick="document.querySelector('...').scrollIntoView({behavior:'smooth'})"

ALWAYS: onclick="namedFunction()"                   simple function call, no args
ALWAYS: onclick="namedFunction('${simpleId}')"      one simple string arg only
ALWAYS: el.addEventListener('click', handler)       after DOM injection
```

### Example — BAD
```js
html += `<button onclick="items.filter(x => x.id === '${id}').forEach(doThing)">Go</button>`;
```

### Example — GOOD
```js
// Define function at module scope
function handleGoClick(id) {
  items.filter(x => x.id === id).forEach(doThing);
}
// Reference it simply in innerHTML
html += `<button onclick="handleGoClick('${id}')">Go</button>`;
```


## RULE 2 — No nested template literals in innerHTML assignments

### The problem
```js
html += `<div>${condition ? `<span>${value}</span>` : ''}</div>`;
//                         ^ this inner backtick is valid JS
//                         but fragile and hard to audit
```
While syntactically valid, nested backticks inside `${}` inside template literals:
- Are invisible to line-by-line scanners
- Are easy to accidentally unbalance during edits
- Cannot be caught by `node --check` or `new Function()` when broken inside innerHTML

### The rule
```
ONE LEVEL of backtick template literals only.
For nested HTML, use string concatenation with + operator.
```

### Example — BAD
```js
html += `<div>
  ${isOpen ? `<button onclick="fn('${id}')">Click</button>` : ''}
</div>`;
```

### Example — GOOD
```js
const btn = isOpen ? '<button onclick="fn(\''+id+'\')">Click</button>' : '';
html += `<div>${btn}</div>`;
```

Or even better (combining Rule 1):
```js
const btn = isOpen ? '<button onclick="handleClick()">Click</button>' : '';
html += `<div>${btn}</div>`;
```


## RULE 3 — Single source of truth: `matchStatus()` is the authority

### The problem
The `forceFuture` flag was a shortcut that overrode `matchStatus()` for future date groups. When `matchStatus()` gained the 12-hour prediction window, `forceFuture` silently suppressed it — matches that should have been "open" stayed "future", breaking both the Predict button and the CSS highlight.

### The rule
```
matchStatus(m) is the ONLY function that determines a match's status.
No caller may override, shortcut, or second-guess its return value.
No flag like forceFuture, forceOpen, overrideStatus, etc. may exist.
```

If `matchStatus()` returns the wrong thing, **fix matchStatus()** — don't patch the caller.

### Status values and their meaning
| Status | Meaning | Prediction allowed |
|---|---|---|
| `'future'` | Before 12:00 PM IST the day before match date | No |
| `'open'` | From 12:00 PM IST prior day until 5 min before kickoff | **Yes** |
| `'inprogress'` | Within 5 min of kickoff through 105 min after | No |
| `'live'` | API confirms match is live | No |
| `'finished'` | API confirms FT, not yet settled | No |
| `'settled'` | Admin has resolved the match | No |


## RULE 4 — All dates and times are IST, always

### The problem
The original fixture seed used US Eastern dates. The app code treats `match_date` + `kickoff_ist` as IST. This mismatch caused every fixture to display on the wrong day.

### The rule
```
match_date = IST calendar date (e.g. "Jun 12")
kickoff_ist = IST wall clock time (e.g. "00:30")

When converting from ET: add 9h30m. If result >= 24:00, increment the date.
Example: June 11 3:00 PM ET → June 12 00:30 IST

When building Date objects in JS:
  const kickoffIST = new Date(Date.UTC(2026, month, day, hh, mm));  // treat as IST
  const kickoffUTC = new Date(kickoffIST.getTime() - IST_OFFSET_MS);
```

### API date fetch rule
The live scores API (api-football) uses UTC dates. A match at 00:30 IST on Jun 12 = 19:00 UTC on Jun 11. The `fetchLiveScores()` function must query BOTH the IST date AND the UTC date to avoid missing matches that straddle midnight.


## RULE 5 — CSS-driven state, not JS-driven visibility

### The problem
Adding a "Scroll to" button required complex JS in an onclick. Removing it and using a CSS highlight (`data-status="open"` + gold border) was simpler, more reliable, and zero-maintenance.

### The rule
```
Prefer data-attributes + CSS for visual state over JS-driven DOM manipulation.
Every match row already carries data-status="${status}" — use CSS selectors on it.
```

### Available selectors
```css
.mrow[data-status="open"]        { /* gold highlight */ }
.mrow[data-status="future"]      { /* default muted */ }
.mrow[data-status="inprogress"]  { /* pulse animation */ }
.mrow[data-status="settled"]     { /* dimmed */ }
```


## RULE 6 — `const` at parse time cannot reference runtime state

### The problem
```js
let PROD_MODE = false;  // set to true after loadAll() reads the DB
const AUTO_SETTLE_DELAY = PROD_MODE ? 15*60*1000 : 10*60*1000;  // ALWAYS 10 min!
```
`const` is evaluated at parse time. `PROD_MODE` is still `false` at that point.

### The rule
```
If a value depends on state that changes after page load (PROD_MODE, LEAGUE, ME, MATCHES),
use a function, not a const.

function getAutoSettleDelay() { return PROD_MODE ? 15*60*1000 : 10*60*1000; }
```


## RULE 7 — Team name consistency

### The rule
```
The CANONICAL name for each team is whatever is stored in the `matches` table.
GROUP_TEAMS, FLAG_MAP, and all display code must use the same spelling.
The normaliseTeamName() function handles API aliases (e.g. "Cabo Verde" → "Cape Verde").
```

When adding a new team or renaming:
1. Update the DB (matches table)
2. Update GROUP_TEAMS
3. Update FLAG_MAP
4. Update normaliseTeamName() aliases
5. Verify with: `SELECT DISTINCT home FROM matches UNION SELECT DISTINCT away FROM matches ORDER BY 1;`


## Pre-commit checklist

Run these EVERY TIME before pushing index.html:

### 1. JS syntax check
```bash
# Extract JS and check with Node
python3 -c "
import re
with open('index.html') as f: html = f.read()
m = re.search(r'<script>(.*?)</script>', html, re.DOTALL)
with open('/tmp/check.js','w') as f: f.write(m.group(1))
"
node --check /tmp/check.js
```

### 2. Backtick balance
```bash
# Must be even
grep -o '`' index.html | wc -l
```

### 3. No complex onclick in innerHTML
```bash
# Should return 0 results — any match needs refactoring to a named function
grep -P "onclick=\"[^\"]{80,}\"" index.html
```

### 4. No forceFuture or status overrides
```bash
grep -i "forceFuture\|forceOpen\|overrideStatus" index.html
# Must return 0
```

### 5. Team name consistency
```bash
# Check for known mismatches
grep "Cabo Verde" index.html  # should only appear in normaliseTeamName alias
grep "Curacao" index.html     # should only appear in normaliseTeamName alias (canonical: Curaçao)
```

### 6. Runtime compile check
```bash
node -e "
const fs=require('fs');
const html=fs.readFileSync('index.html','utf8');
const js=html.match(/<script>([\s\S]*?)<\/script>/)[1];
new Function(js);
console.log('✅ Compiles OK');
"
```

### 7. Supabase fixture verify (after any fixture change)
```sql
-- Must return 0
SELECT COUNT(*) FROM matches WHERE kickoff_ist IS NULL AND grp IN ('A','B','C','D','E','F','G','H','I','J','K','L');

-- Must total 104 (72 group + 32 knockout)
SELECT grp, COUNT(*) FROM matches GROUP BY grp ORDER BY grp;
```


## App-specific constants reference

| Constant | Value | Notes |
|---|---|---|
| `IST_OFFSET_MS` | 19800000 (5.5h) | UTC to IST |
| `KICKOFF_CUTOFF_MS` | 300000 (5 min) | Lock predictions this long before kickoff |
| `MATCH_DURATION_MS` | 6300000 (105 min) | Group stage match window |
| `KNOCKOUT_DURATION_MS` | 9000000 (150 min) | Knockout match window (incl. ET/pens) |
| Prediction window | 12:00 PM IST prior day | All matches on a date open together, prior day noon |
| Reminder window | Same as prediction | WhatsApp reminder shows all open matches |
| `PROD_MODE` | Boolean from DB | Set via `UPDATE leagues SET prod_mode = true` |
| API daily limit | 100 calls | api-sports.io free tier |
| Poller intervals | 2 min (live) / 5 min (quiet) | Adaptive based on `_liveMatchCount()` |


## File edit methodology

When Claude edits this single-file app:

1. **Always use Python string replacement** — `str_replace` or `python3` with `html.replace(old, new)`. Never sed on this file (Unicode flags break it).
2. **Assert the old string exists** — `assert old in html` before replacing. Prevents silent no-ops.
3. **Run `node --check`** after every edit, not just at the end.
4. **One logical change per edit** — don't bundle unrelated fixes. If one breaks, the others are clean.
5. **Never guess line numbers** — always `grep -n` or `view` to find the exact location first.
