# WC2026 Fantasy — Regression Checklist

Run through this after every new feature deployment. Takes ~10 mins.

---

## Auth

- [ ] Register a new user without invite code → creates league, lands on Matches tab
- [ ] Register a new user with invite code → joins existing league, lands on Matches tab
- [ ] Login with correct credentials → lands on Matches tab
- [ ] Login with wrong password → shows error, does not proceed
- [ ] Forgot password → enter username + email → new password shown on screen
- [ ] Logout → clears session, reload shows login screen

---

## Matches tab

- [ ] Today's matches pinned gold at top, future ascending below, past descending below that
- [ ] Match row tap → match sheet opens instantly (spinner visible, then fills)
- [ ] Open match → Predict form visible with score inputs
- [ ] Submit prediction → saved, sheet closes, row shows "Predicted" badge
- [ ] Tap same match again → sheet shows "Your prediction X–Y" with Change link
- [ ] Tap Change → form reappears pre-filled with existing prediction
- [ ] Update prediction → saved without duplicate key error
- [ ] Past match row → sheet shows locked state, no predict form
- [ ] Settled match row → sheet shows result, all predictions visible with Exact/Outcome/Wrong badges

---

## Leaderboard tab

- [ ] Ranked by P/L% not raw P/L
- [ ] Medal emojis visible and large (26px) for top 3
- [ ] Tap player row → inline expand appears with 4 chips (Exact/Outcome/Wrong/Refund)
- [ ] Tap chip → if 1 match: sheet opens directly. If multiple: tappable list appears
- [ ] Tap same player row again → collapses
- [ ] Stage breakdown table: all 5 stages always shown, future stages dimmed
- [ ] Stage breakdown P/L column shows absolute ₹ (not %)
- [ ] Recent results section shows yesterday's matches only
- [ ] Tap recent result row → match sheet opens (same as matches tab)
- [ ] Highlights section: 2×2 grid, correct badge holders

---

## Tournament tab

- [ ] Opens instantly (no spinner/fetch delay)
- [ ] Group standings computed correctly from settled matches
- [ ] Knockout bracket shows correct teams after group stage

---

## Admin tab (admin user only)

- [ ] Settle button appears on finished matches
- [ ] With no live score (April testing): shows "Settle" → picks random weighted score → settles immediately with toast
- [ ] With live score (June): shows FT score pre-filled → confirm → settles
- [ ] After settle: leaderboard updates, recent results updates, stage breakdown updates
- [ ] Bet amounts locked when stage has active matches
- [ ] Import fixtures button visible, shows status message on tap
- [ ] WhatsApp reminder generates correct message for today's matches
- [ ] Random settle (April only, PROD_MODE=false): single tap, no confirm dialog, toast shows score

---

## Cross-session persistence

- [ ] Prediction made → logout → login → prediction still shown on match row
- [ ] Prediction visible to other league members (check from different account)
- [ ] Settled match result + payouts visible after re-login
- [ ] Leaderboard P/L reflects correct balances after re-login

---

## Safari / iOS specific

- [ ] Predict button responds on first tap (no 300ms delay)
- [ ] Match sheet opens without scrolling issues
- [ ] Inline player expand doesn't cause page jump
- [ ] Score inputs accept numeric keyboard
- [ ] Close button on match sheet works

---

## Known April-only behaviours (not bugs)

- Settle button shows random score (no API data) — expected
- FT badge shows "FT" without score — expected
- Auto-settle fires 10 mins after kickoff+105mins — expected
