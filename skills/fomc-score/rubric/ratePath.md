# rate_path

**Question:** What direction and pace of the policy rate do the minutes point to?

This is the headline dimension. It combines the decision actually taken with the forward-looking signal in participants' views.

## Where to look

Keywords for retrieval: "federal funds rate," "target range," "policy firming," "tightening," "easing," "restrictive," "accommodative," "additional policy firming," "reduce the target range," "pause," "hold," "path of rates," "terminal rate."
Sections: Committee Policy Actions; Participants' Views on Current Conditions and the Economic Outlook.

## Anchors

| Score | What the minutes look like |
|---|---|
| +1.00 | Rate raised and many participants argue for more or a faster pace; talk of needing to move "expeditiously" or front-load |
| +0.75 | Rate raised, or held with a strong tightening bias; most see further increases as likely |
| +0.50 | Hold with a clear lean toward future increases, or a small increase with hedging on what comes next |
| +0.25 | Hold; some mention that further firming might be needed |
| 0.00 | Hold with balanced discussion; no stated direction |
| -0.25 | Hold; some mention that easing may become appropriate |
| -0.50 | Hold with a clear lean toward cuts, or a small cut with hedging on what comes next |
| -0.75 | Rate cut, or hold with strong easing bias; most see further cuts as likely |
| -1.00 | Large cut, or cuts with many participants arguing for faster or larger moves; emergency language |

## Consistency with the decision

Look up the actual decision for the meeting in the decisions data.

- If the Committee **raised** the rate, `rate_path` must be above 0 unless the minutes explicitly describe the move as the final one and the discussion is clearly about stopping. In that case, score no lower than +0.25.
- If the Committee **cut** the rate, `rate_path` must be below 0 under the mirror rule.
- If the Committee **held**, the score is driven by forward-looking language and may be positive, negative, or zero.
- A score that contradicts the decision without an explicit explanation in the rationale is wrong. The guard layer should flag it.

## Pitfalls

- A hold is not automatically 0. Read the forward guidance.
- "Data-dependent" language alone is 0. It signals no direction.
- Do not score the size of the move alone. A 25 bp hike with "many" arguing for 50 bp is stronger than a 25 bp hike that "most" see as the last.
- Do not use the market-implied path. Only what the minutes say counts.