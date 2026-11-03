---
name: fomc-score
description: Score, rate, grade, quantify, or measure FOMC minutes on a -1 (dovish) to +1 (hawkish) scale across rate path, inflation, labor market, activity, financial conditions, balance sheet, and risk balance. Use for meeting tone or stance questions and numeric comparisons across meetings.
---

# FOMC Minutes Scoring

Turn one meeting's minutes into a structured set of scores in [-1, +1], each backed by quotes from the text.
The agent's dedicated scoring workflow supplies the complete minutes text, all rubric files, and the output schema
to one model call at a time; it does not use a minutes retrieval tool while scoring.

## Scale (same for every dimension)

- **+1 = hawkish**: the content argues for tighter policy (higher rates, faster balance-sheet runoff).
- **-1 = dovish**: the content argues for easier policy.
- **0 = neutral**: balanced, or no net push either way.

Scores measure what the *minutes say*, not what you think the Fed should do and not what happened afterward. Read `rubric/00_scale.md` before scoring anything.

## Inputs

- A meeting date (YYYY-MM-DD) or "latest". The agent resolves this against its meeting data and only scores minutes
  released by the session's anchor date.
- The scoring workflow evaluates all seven dimensions. It loads the full meeting text and all rubric reference files
  before asking the model to score.

If the minutes for the requested date are not available by the anchor date, report that rather than scoring from memory.

## Workflow

1. **Use only the supplied minutes** for the selected meeting. The scoring call receives the complete minutes text; do not assume an additional retrieval tool is available. For a comparison, score each meeting separately and independently.
2. **Respect the as-of date.** Use only the minutes text and data known on or before the meeting's release date. Do not use knowledge of later events.
3. **Read the supplied rubric references** and evaluate each of the seven dimensions. Decide the score using the rubric anchors, in steps of 0.25.
4. Pick 1 to 3 **verbatim** quotes (each 40 words or fewer) from the supplied minutes that justify each score, and write a one or two sentence rationale. State the evidence; do not editorialize.
5. **Output** one JSON object matching `schema.json` for each meeting. For a comparison, return a `scores` array containing those schema-conforming objects; keep validation status and issues in separate metadata.
6. **Self-check before returning** (the guard layer will also enforce these):
   - Every score is in [-1, 1], or `null` with `status: "not_discussed"`.
   - Every quote appears word-for-word in the minutes.
   - The `rate_path` score is consistent with the actual decision (see rubric).
   - No dimension cites evidence from outside the minutes.

## Dimensions and rubric files

| Dimension key | Rubric file | What it captures |
|---|---|---|
| `rate_path` | `rubric/ratePath.md` | Expected direction and pace of the policy rate |
| `inflation` | `rubric/inflation.md` | Assessment of inflation and inflation expectations |
| `labor_market` | `rubric/laborMarket.md` | Assessment of employment, wages, labor tightness |
| `economic_activity` | `rubric/economicActivity.md` | Growth, spending, output outlook |
| `financial_conditions` | `rubric/financialConditions.md` | Markets, credit, financial stability |
| `balance_sheet` | `rubric/balanceSheet.md` | Asset purchases, runoff, reserves |
| `risk_balance` | `rubric/riskBalance.md` | Which risk participants emphasize most |

## Rules that prevent common mistakes

- **Direction of the indicator is not the score.** Strong job growth is hawkish (+) because it supports tighter policy; rising unemployment is dovish (-). Always convert to policy implication.
- **Score the Committee, not one voice.** Minutes include "some," "several," "many," "most," and "all" participants. Weight by those quantifiers (see `rubric/00_scale.md`). A view held by "a few" participants moves the score less than one held by "most."
- **Do not infer a topic that is not there.** If the minutes barely mention a dimension, return `null` with `status: "not_discussed"` rather than guessing 0. Zero means "discussed and balanced."
- **Do not average away disagreement.** If participants are split, score near 0 and set `confidence` to `"low"`, and say so in the rationale.
- **Stay consistent across meetings.** Use the anchors in the rubric files, not your impression of how this meeting compares to the last one.
- **Report uncertainty honestly.** `confidence` is `"high"`, `"medium"`, or `"low"` and reflects how clear and consistent the evidence was, not how extreme the score is.

## Output

Follow `schema.json`. See `examples/exampleOutput.json` for the exact shape. Output the JSON only, with no surrounding prose, when the caller is another program.