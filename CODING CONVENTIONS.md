# Coding Conventions & Pitfall Prevention

Rules that held up across a full tournament of edits. Follow these whether
you're a human or an AI assistant editing `index.html`.

## Rule 1 — No complex JS in inline `onclick` inside `innerHTML` strings

**The #1 source of silent runtime bugs in this codebase.**

When JS builds an HTML string injected via `innerHTML`, any `onclick="..."`
attribute gets parsed multiple times (once as a JS string literal, once as
an HTML attribute, once again when the click fires). Escaping breaks
silently partway through — `node --check` only catches step one.

```
NEVER: onclick="someObj.method({key:'value'})"     inside an innerHTML string
NEVER: onclick="fn('${var}')"                       with nested template literals
ALWAYS: onclick="namedFunction()"                   simple call, no args
ALWAYS: onclick="namedFunction('${simpleId}')"      one simple string arg only
```

## Rule 2 — No nested template literals in innerHTML assignments

```js
// BAD — nested backtick, fragile, invisible to line-scanners
html += `<div>${isOpen ? `<button onclick="fn('${id}')">Click</button>` : ''}</div>`;

// GOOD — string concatenation for the inner piece
const btn = isOpen ? '<button onclick="handleClick()">Click</button>' : '';
html += `<div>${btn}</div>`;
```

## Rule 3 — `matchStatus()` is the single source of truth

No caller may override, shortcut, or second-guess `matchStatus()`'s return
value. No flag like `forceFuture` or `overrideStatus` may exist — if the
status is wrong, fix the function, not the caller.

| Status | Meaning | Prediction allowed |
|---|---|---|
| `'future'` | Before 12:00 PM IST the day before | No |
| `'open'` | 12:00 PM IST prior day → 5 min before kickoff | **Yes** |
| `'inprogress'` | Within 5 min of kickoff through ~105/150 min after | No |
| `'finished'` | Live-score API confirms FT/AET/PEN, not yet settled | No |
| `'settled'` | Admin/auto-settle has resolved the match | No |

## Rule 4 — All dates and times are IST, always

`match_date` = IST calendar date, `kickoff_ist` = IST wall-clock time. When
converting from US Eastern fixtures: add 9h30m, roll the date forward if it
crosses midnight. Double-check every knockout-round fixture against an
independent source — a single arithmetic slip here silently puts a match
under the wrong day heading with no error thrown.

## Rule 5 — CSS-driven state over JS-driven visibility

Every match row carries `data-status="${status}"`. Prefer selecting on that
in CSS over imperative DOM manipulation for anything purely visual (open
highlight, dimmed/settled state, live pulse animation).

## Rule 6 — `const` at parse time cannot reference runtime state

If a value depends on state that changes after page load (`LEAGUE`, `ME`,
`MATCHES`, `PROD_MODE`), it must be a function, not a `const` computed once
at parse time.

## Rule 7 — One function, one job, no stale variable scope after refactors

When introducing a shared helper used across multiple render functions
(e.g. `actualWinnerPayout()` used by the leaderboard, match card, match
sheet, player drawer, and audit), a bulk find/replace risks leaving a stale
variable reference behind — `ME.username` copy-pasted into a function whose
actual parameter is `username`, or a loop where the right variable is
`p.username` not `u`. This bit us twice in one tournament (see
`SETTLEMENT_AND_AUDIT.md` for both incidents).

**Mitigation**: wrap risky render functions (anything building a modal or
sheet from dynamic data) in try/catch that surfaces the real JS error
message in the UI rather than leaving a silent spinner. This is what
actually caught both incidents — the error text (`Can't find variable: u`)
pointed straight at the bug.

## Rule 8 — Team name consistency

The canonical name for each team is whatever's stored in the `matches`
table. `normaliseTeamName()` handles known API aliases (e.g. accents,
"Czech Republic" vs "Czechia", "USA" vs "United States"). When adding a team
or fixing a name mismatch, update the DB, any hardcoded team maps in the
bracket code (`TEAMS`, `ID_MAP` in `winnerOf()`), and
`normaliseTeamName()`'s alias table together — a mismatch in any one place
breaks bracket display or live-score matching silently.

## Pre-commit checklist

Run every time before pushing `index.html`:

```bash
# 1. JS syntax check
python3 -c "
import re
with open('index.html') as f: html = f.read()
m = re.search(r'<script>(.*?)</script>', html, re.DOTALL)
with open('/tmp/check.js','w') as f: f.write(m.group(1))
"
node --check /tmp/check.js

# 2. No complex onclick left in innerHTML (should return 0 results)
grep -P "onclick=\"[^\"]{80,}\"" index.html

# 3. No status-override flags (must return 0)
grep -i "forceFuture\|forceOpen\|overrideStatus" index.html

# 4. Runtime compile check
node -e "
const fs=require('fs');
const html=fs.readFileSync('index.html','utf8');
const js=html.match(/<script>([\s\S]*?)<\/script>/)[1];
new Function(js);
console.log('✅ Compiles OK');
"
```

After any fixture change, verify in Supabase SQL editor:

```sql
-- Must total 104 for a full World Cup (72 group + 32 knockout)
SELECT grp, COUNT(*) FROM matches GROUP BY grp ORDER BY grp;
```

## File edit methodology

1. **Always use Python string replacement** (`str_replace` tool or
   `html.replace(old, new)`) — never `sed` on this file, Unicode flag
   emojis break it.
2. **Assert the old string exists** before replacing — prevents silent
   no-ops when the target text has already changed.
3. **Run `node --check` after every edit**, not just at the end of a
   session.
4. **One logical change per edit** — if something breaks, you know
   immediately which change caused it.
5. **Never guess line numbers** — `grep -n` or view the file fresh before
   editing, especially after any prior edit has shifted line numbers.
