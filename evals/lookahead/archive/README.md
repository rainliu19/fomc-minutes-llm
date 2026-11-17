# Retired lookahead runs and the version history

These runs are kept for reference. They are not shown on the Evaluation page (the page route serves only the
folders `evals/lookahead/`, `fresh/` and `unseen/`).

## Stages shown on the page
| Stage | What is in it |
|---|---|
| baseline | App with the data cutoff off (`--open`): no guards, no prompt rules, the tools see all data |
| v0 | Guards: data cutoff, dated lookups refused, checks, unreleased minutes answered "not public" by code (the app in main) |
| v1 | v0 + a date check in code that answers "not known yet" for a period the data cannot show (months in words, quarters, parts of a year, "N months from now", "rate decision" at an unreleased meeting) + the short rules in `agents/shared/asof.md` |

## Versions tried on the way to v1 (code in git history)
| Version | What it was | Result |
|---|---|---|
| prompt-only v1 (commit 25d1d10, run in f4352de) | longer rules (543 characters) in `agents/shared/asof.md`, no code check | 39/104 errors on the main key, no better than v0 (38/104). Run discarded (file removed in git history). |
| month-names-only v1 (commit b99501c) | short rules (about 330 characters) + a code check that reads only months named in words ("June 2020") | main key 0/104, fresh 12/56, unseen 15/62. Files in this folder: `*-fast-team-v1-months-only.json`. |
| v1 (final, commit 2893e57) | the month-names check broadened to quarters, "July of 2020", long dates, "N months from now", "end of 2021", and a rate decision with no rate word | main key 0/104, fresh 1/56 (a development set), unseen 7/62 (the fair test). |

## Question sets
- `../key.json` (main key, 114 questions): three fixed wordings; v1's first check was designed from v0's errors on it.
- `../fresh/key.json` (68): new wordings; its misses were used to broaden the check, so it is a development set for v1.
- `../unseen/key.json` (74): written after the broadened check, not used to build it; the headline set. Includes forms the check cannot read on purpose (numeric month, month with no year, season, bare year, "next meeting").
- Rule: when v1 changes after a set's errors were seen, that set is a development set and a new unseen set is written (`tests/make_lookahead_unseen.py` is the pattern, a new seed and new wordings).

## Remaining v1 errors on the unseen set (7 of 62)
Five decision questions worded with no rate or "decide" keyword ("What was the outcome of the FOMC's December 2016 rate meeting?", "After the March 2017 meeting, what was the new target?"), a numeric month, a month with no year; one rate and one pressure question. Not fixed, so the unseen set stays unseen until v1 changes.
