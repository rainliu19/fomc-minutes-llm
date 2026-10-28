# Shared scoring scale

Read this before scoring any dimension.

## Sign convention

+1 is hawkish (supports tighter policy). -1 is dovish (supports easier policy). Every dimension uses this convention, so a hot labor market and rising inflation both score positive, and weak activity and falling inflation both score negative.

## Score levels

Use steps of 0.25.

| Score | Meaning |
|---|---|
| +1.00 | Unambiguous, near-unanimous push toward tighter policy; urgency language |
| +0.75 | Strong push; most participants agree; little dissent |
| +0.50 | Clear lean toward tighter; meaningful minority disagrees or hedges |
| +0.25 | Slight lean toward tighter; mostly balanced |
| 0.00 | Discussed and balanced, or views split evenly |
| -0.25 | Slight lean toward easier |
| -0.50 | Clear lean toward easier |
| -0.75 | Strong push toward easier |
| -1.00 | Unambiguous, near-unanimous push toward easier; urgency language |

## Participant quantifiers

Minutes use a standard vocabulary. Treat it as a weight on how much the view moves the score.

| Phrase | Roughly |
|---|---|
| "all" / "everyone" | 100% |
| "almost all" | 90%+ |
| "most" / "a majority" | clear majority |
| "many" | large group, less than a majority |
| "several" / "some" | a meaningful minority |
| "a few" / "a couple" | very small group |

A view held by "many" with no counterpart caps near +/-0.50. A view held by "most" with a dissenting "several" lands around +/-0.50 to +/-0.75. "A few" alone rarely justifies more than +/-0.25.

## Intensity language

Words that push the score toward the extremes: "firmly," "decisively," "significant," "substantial," "must," "essential," "unacceptable."
Words that pull it toward zero: "somewhat," "modestly," "could," "might," "monitor," "data-dependent," "well positioned."

## Confidence

- **high**: multiple consistent statements, clear quantifiers, little contradiction.
- **medium**: one clear statement, or mild mixed signals.
- **low**: sparse, ambiguous, or split evidence.

Confidence describes the evidence, not the size of the score. A 0.00 can be high confidence if the minutes clearly describe a balanced view.

## Hard rules

1. Evidence must be a verbatim quote from the minutes, 40 words or fewer.
2. Use only the minutes text and data available at the release date.
3. Do not use knowledge of what the Fed or markets did afterward.
4. If a topic is not meaningfully discussed, return `status: "not_discussed"` and `score: null`.
5. Where a factual decision exists (the actual rate move), the rubric tells you how it constrains the score.

## Where the minutes tend to put each topic

Minutes follow a stable layout. This helps retrieval but is not a rule.

- Developments in financial markets and open market operations: `financial_conditions`, `balance_sheet`
- Staff review of the economic situation: `economic_activity`, `labor_market`, `inflation`
- Staff review of the financial situation and the economic outlook: `financial_conditions`, `risk_balance`
- Participants' views on current conditions and the economic outlook: all dimensions
- Committee policy actions: `rate_path`, `balance_sheet`