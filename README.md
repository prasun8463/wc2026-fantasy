# WC2026 Fantasy Predictor

A friend-group World Cup 2026 prediction/betting app. Single-file `index.html`
hosted on GitHub Pages, backed by Supabase (Postgres). Ten players predicted
scores across all 104 matches of the tournament, with stage-scaled stakes and
a bold-pick multiplier system.

**Status: tournament complete.** Spain beat Argentina 1-0 (AET) in the Final
on July 19, 2026. This repo is now a finished reference rather than an
actively-developed app — see [`ARCHITECTURE.md`](./ARCHITECTURE.md) if you're
adapting this for a future tournament.

## Quick facts

- **Live site**: `prasun8463.github.io/wc2026-fantasy`
- **Backend**: Supabase project `wxolmlxphwieqvyfuyfu`
- **Tables**: `users`, `leagues`, `matches`, `predictions`
- **Live scores**: [worldcup26.ir](https://worldcup26.ir) (`/get/games`, free, no key)
- **Admin**: `prasun84`, 10 players total

## Docs in this repo

| File | What it's for |
|---|---|
| [`ARCHITECTURE.md`](./ARCHITECTURE.md) | How the app is built, data model, timezone handling, the Postgres bracket-advance trigger |
| [`CODING_CONVENTIONS.md`](./CODING_CONVENTIONS.md) | Rules for editing `index.html` safely — mandatory pre-commit checklist |
| [`SETTLEMENT_AND_AUDIT.md`](./SETTLEMENT_AND_AUDIT.md) | How payouts are calculated, the ledger audit query, and every bug class we hit this tournament |
| [`CHANGELOG.md`](./CHANGELOG.md) | Chronological record of features built and bugs fixed across the tournament |

## Stakes by stage

| Stage | Bet per player |
|---|---|
| Group | ₹100 |
| R32 | ₹200 |
| R16 | ₹300 |
| QF | ₹500 |
| SF / 3rd place | ₹800 |
| Final | ₹1000 *(bumped from ₹800 as a send-off for the last match)* |

Bold picks pay 2× the base share; limits are R32=5, R16=3, QF+SF shared=2,
Final+3rd shared=1.

## Final result

**World Cup Champions: 🇪🇸 Spain** (1-0 AET over Argentina, Ferran Torres 106')

**League Champion: theoffsite** — highest P/L% across the tournament.

**Biggest single win: arvind_fc & dipt, ₹5,000 each** — both predicted the
Final's exact 1-0 scoreline and split the ₹10,000 pot.
