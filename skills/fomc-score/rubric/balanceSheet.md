# balance_sheet

**Question:** Do the minutes support a smaller or larger balance sheet?

Faster runoff, outright reduction, or reserve scarcity concerns on the shrinking side are hawkish (+). Slower runoff, a halt, or new asset purchases are dovish (-).

## Where to look

Keywords: "balance sheet," "runoff," "redemption caps," "securities holdings," "asset purchases," "quantitative easing," "quantitative tightening," "reserves," "ample reserves," "repo," "standing repo facility," "reinvestment," "MBS," "Treasury securities."
Sections: Developments in Financial Markets and Open Market Operations; Committee Policy Actions; Participants' Views.

## Anchors

| Score | What the minutes look like |
|---|---|
| +1.00 | Faster or larger runoff announced; many argue for more shrinkage |
| +0.75 | Runoff continuing at full pace; most support further reduction |
| +0.50 | Runoff on track, with discussion of possible acceleration or composition shift |
| +0.25 | Runoff continuing without debate; a few mention going further |
| 0.00 | Not changing; discussion is technical or balanced |
| -0.25 | Some discussion of slowing runoff when reserves approach ample |
| -0.50 | Slowing or ending runoff under active consideration; many support it |
| -0.75 | Runoff slowed or ended; most support caution |
| -1.00 | New purchases or large expansion announced or strongly urged |

## Pitfalls

- Technical operations discussions (repo usage, reserve demand) are not policy signals unless participants link them to the pace of runoff.
- Many meetings have little on this topic. If nothing beyond routine operations appears, return `not_discussed`.
- Do not confuse composition changes (shifting toward Treasuries) with size changes; treat composition shifts as a mild signal (|score| of 0.25 or less) unless the minutes tie them to the stance.