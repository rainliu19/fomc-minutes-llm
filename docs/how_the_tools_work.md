# How getPolicyPath, assessEconomy and getOutlook work

Each section says what a tool answers, walks one real question through it, explains the
finance behind each step, and ends with what could be wrong. The examples are the tools' actual
output on the data in this repo.

## What the three tools have in common

- **Code does the work, not the AI.** Each tool is plain MATLAB. It reads the data, does the
  arithmetic and writes the sentences. The model only passes the summary on in its answer.
- **Only what was known at the time.** Asking "as of August 25, 2024" uses only data published by
  then, and only minutes released by then. Minutes come out about three weeks after a meeting.
  Data that gets revised, like GDP, is used as it was published by then, not as revised later.
- **The rate target comes from FRED, not the minutes.** That catches the three changes since 2008
  made between scheduled meetings (January 2008, October 2008, March 3, 2020), which no minutes
  record as a decision. Changes are measured on the top of the target range.
- **A "run"** is a stretch of rate changes in one direction, such as the 11 increases from March
  2022 to July 2023. Holds in between don't end it. Only a change in the other direction does.
- **They run on their own.** The model is offered each one as a tool, but a small model often
  skips tools. So the app also runs each one before the model starts, whenever the question's
  wording fits. The model gets the facts either way.

---

## getPolicyPath: how the rate has moved

**It answers:** "How have rates moved over the past year?" "When did the Fed last raise rates?"
"How many cuts were there in 2025?"

**How it works:**
1. It takes the last 8 meetings whose minutes are out, about a year, or the years the question names.
2. It finds the last change and the run it belongs to: how many changes, how much in total, and
   from what range to what range.
3. If the last change reversed direction, it also describes the run that came before.
4. It counts the meetings with no change, before the last change and since.
5. It lists who dissented, and whether each wanted a higher rate, a lower rate or something else,
   such as different statement wording.
6. Every fact from the minutes gets its paragraph id, so the model can cite it.

**Example, as of October 7, 2026:**
- The target was 3-3/4 to 4 percent.
- The last change was a 0.25 point increase at the September 16, 2026 meeting, the first increase
  since July 2023.
- It followed 6 cuts totaling 1.75 points, from September 2024 to December 2025.
- The target had been held for 5 meetings before the increase.
- Over the last 8 meetings: 1 increase, 2 cuts and 5 holds, for a net change of −0.25 point.
- 6 dissents for a lower rate, 6 for a higher one, and 3 on other grounds.

**The finance behind it.** This is the history a Fed watcher starts from: where the rate is,
which way it last moved, how long the Fed has paused, and how split the Committee is.

**What could be wrong:**
- Measuring on the top of the range is a convention. It matters once: in December 2008 the single
  target of 1% became a range of 0 to 1/4. That counts as a cut of 0.75 on the top, but 0.875 on
  the middle.
- A meeting whose minutes aren't out yet isn't counted as a hold.
- A run doesn't end however long the Fed holds (see the open questions).

---

## assessEconomy: where policy may go next

**It answers:** "Is the Fed likely to cut at its next meeting?" "What do current conditions mean
for future FOMC decisions?" "Is policy too tight?" "What does the Taylor rule say?"

It puts five things together. The first is the headline the model is told to answer from.

### 1. The next-meeting reading

Two signals, each doing a different job:
- **Direction, from the minutes:** do participants lean toward raising, cutting or holding? (How
  that's read is in "How the minutes' direction is read" below.)
- **Timing, from the market:** the 6-month Treasury bill yield against the effective fed funds rate.

Why split them? Officials often say further moves are likely, then wait a few meetings. So the
minutes are better at saying which way, and market pricing is better at saying when.

It then adds a base rate: after earlier minutes with the same pair of signals, how often did the
next meeting raise, hold or cut? This is left out when fewer than 3 earlier meetings match.

### 2. The market signal

If the 6-month bill yield is more than 0.275 point **above** the effective fed funds rate (the
rate banks actually charge each other overnight), markets expect an increase soon. More than 0.275
point **below**, a cut. In between, no change.

The finance: a 6-month bill earns roughly the average overnight rate expected over the next six
months. So if markets expect cuts, the bill yields less than today's fed funds rate. The usual
measure is fed funds futures, but they aren't in this data.

How 0.275 was chosen: five measures were tried, the 1-, 3- and 6-month bills against the
effective fed funds rate and the 3- and 6-month bills against the middle of the range. Each had its
cutoff fitted on 2008 to 2018, and the 6-month bill against the effective rate fitted best. Tested
unchanged on 2019 onward, it was right about the next decision 84% of the time, against 65% for
always guessing "hold". The 3-month bill was dropped because it moves only about 0.1 point for a cut
at the next meeting, so cuts mostly read as no change.

The 2-year Treasury yield against the middle of the range is also given, beyond ±0.25 point, as
background on the next two years, not the next meeting. A question only about the next meeting
leaves it and the policy rules out: given both, the model compared the 2-year with the fed funds
rate instead of using the bill.

### 3. The economy against the Fed's two goals

| Goal | What it reports |
|---|---|
| Stable prices | Core PCE inflation over 12 months, against the 2% goal, and whether it's rising or falling |
| Maximum employment | Unemployment against the CBO's estimate of its normal level, and the trend |
| | Average monthly job gains over 3 months |
| | Real GDP growth last quarter, and GDP against the CBO's estimate of potential |

The Fed's 2% goal is for all PCE prices. Core PCE leaves out food and energy, which swing a lot,
so it shows the underlying trend better. "Rising" or "falling" means a change of more than 0.1 point
over three months. The CBO's estimate of normal unemployment is only available in this data from
February 2011; before that, the tool says it's missing rather than use a later estimate.

### 4. Policy rules

A policy rule says where the rate would be if the Fed reacted to inflation and the economy by a
fixed formula. The Taylor rule:

> rate = neutral real rate + inflation + 0.5 × (inflation − 2) + 0.5 × output gap

The "balanced approach" rule is the same, but with 1.0 on the output gap. The neutral real rate,
the rate that neither speeds up nor slows down the economy, isn't known. So it's shown at two
values: 0.5%, a low estimate, and 2%, Taylor's original. That gives four answers, compared with the
actual range. They're labelled as background, because the Fed follows no rule and moves gradually.

### 5. The latest minutes

The direction the minutes point, with up to two quoted sentences, and whether the Fed staff
revised its inflation and growth forecasts up or down at that meeting.

**Example 1, as of August 25, 2024** (the September 2024 cut came next):
- **Minutes:** the AI scored the July 2024 minutes −0.75, a lean toward cuts. Quote: "The vast
  majority observed that ... it would likely be appropriate to ease policy at the next meeting."
- **Market:** the 6-month bill was 4.9%, 0.4 point below the fed funds rate of 5.3%, so markets
  expected a cut soon.
- **Reading:** "the minutes and the 6-month bill both point to a cut over the next few meetings."
- **Economy:** core inflation 2.6% and falling, unemployment 4.3% and rising, job gains 170,000 a
  month.
- **Rules:** 4.0% to 6.0%, against an actual range of 5-1/4 to 5-1/2: one rule above it, one within
  it, two below.

Both had it right here: the Fed cut at the next meeting. (Before the scorer picked a rubric row,
the AI scored these minutes 0.00, a hold, and only the market pointed to the cut.)

**Example 2, as of October 7, 2026:**
- **Minutes:** the AI scored the September 2026 minutes +1, a lean toward further increases.
  Quote: "most participants assessed that another increase ... would likely be appropriate by year end."
- **Market:** the bill was 0.4 point above the fed funds rate, so an increase soon.
- **Reading:** both point to an increase. After earlier minutes with the same pattern, the next
  meeting raised 16 times and held twice (of 18).
- **Rules:** 4.7% to 6.9%, all four above the actual 3-3/4 to 4.

**What could be wrong:**
- **The bill and the fed funds rate are quoted differently.** The bill yield is quoted on a
  365-day year and the fed funds rate on a 360-day year. At 5% rates the bill looks about 0.07
  point higher for the same expectations, which tilts the signal toward "increase". At rates near
  zero it doesn't matter.
- **Bills move for other reasons too:** debt-ceiling standoffs, heavy Treasury bill issuance, and
  investors fleeing to safety (2008, March 2020).
- **Six months covers three or four meetings.** It says "within six months" more than "at the next
  meeting".
- **The policy rules** use core PCE (Taylor used a different price index), an estimate of
  potential GDP that is later revised, and no allowance for the Fed moving gradually.
- **The base rates** come from small samples of neighboring meetings, which overlap. They're
  labelled "history, not a forecast", but a reader may still take them as odds.
- **"Rising" or "falling" at 0.1 point** may be too sensitive for unemployment, which moves by
  about 0.2 point a month from survey noise alone.

---

## getOutlook: what the rate moves may mean ahead

**It answers:** "What do recent Fed moves mean for mortgage rates and spending?" "How will higher
rates affect inflation?" "What did the 2022 increases do to mortgage rates?" "What do rate
increases mean for interest on the federal debt?"

It makes no forecast of its own. It gathers three kinds of evidence and tells the model to say
what the evidence shows, never what will happen. A question that names only past years ("the 2022
increases") gets the evidence as it stood at the end of the latest year named.

### 1. The Fed staff's forecast

Before each meeting, the Fed staff updates its forecast. For the last 4 meetings, it reports
whether the staff revised inflation and growth up, down or about the same, plus the staff's latest
view of the risks. It reports only the direction of revisions; the minutes rarely give the
forecast itself in numbers. Unemployment revisions are left out, because the wording ("a smaller
decline") is too varied to read reliably.

### 2. How far the current run has reached

A rate change reaches the economy in steps: market rates move first, then borrowing costs, then
spending, then prices. For each step it gives the value now, just before the run began, and six
months before that (markets often move ahead of the Fed):

| Step | What it reports |
|---|---|
| Market rates | 2-year and 10-year Treasury yields |
| Borrowing costs | 30-year mortgage rate, and the extra yield on Baa corporate bonds over the 10-year |
| Spending | Real consumer spending, growth over 12 months |
| Prices | Core PCE inflation, and what consumers expect inflation to be in a year |
| Federal debt | The average interest rate the Treasury pays on its debt |

If a monthly figure is from before the run began, it says it's too early to show the change.
Credit card and car loan rates, and the total interest the government pays, aren't in the data,
and the model is told to say so.

### 3. What happened after earlier runs

For each earlier run in the same direction since 1990: a year and two years after its first change,
did mortgage rates, spending growth, core inflation and the Treasury's average rate (from 2001) go
up or down? It reports a count and the middle value, such as "mortgage rate higher in 4 of 6 (median +0.4 point)".

**Example, as of October 7, 2026** (three weeks after the first increase):
- **Staff forecast:** inflation revised up in 3 of the last 4 meetings, and the staff sees the risks
  to inflation tilted up.
- **So far:** the 30-year mortgage rate was 7.28%, up from 6.76% just before the increase and
  6.11% six months before. The 10-year was 5.27%, up from 5.01% and 4.23%. Much of the rise came
  before the Fed moved, as markets anticipated it: 0.65 of the mortgage rate's 1.17 points, and
  0.78 of the 10-year's 1.04.
- **Too early:** spending, core inflation and the Treasury's average rate are all August figures,
  from before the increase.
- **Earlier runs of increases** (1994, 1997, 1999, 2004, 2015, 2022): a year after the first
  increase, the mortgage rate was higher in 4 of 6 (median +0.4 point) and core inflation higher in
  4 of 6 (median +0.1 point).

**What could be wrong:**
- **Before and after isn't cause and effect.** Mortgage rates follow the 10-year yield, which also
  moves with inflation expectations and investor demand. Spending and inflation have their own
  causes. The tool says "so far", but it can't separate the Fed's effect from everything else.
- **Few earlier runs, and very different ones:** six in each direction since 1990. The single 1997
  increase and the 11 in 2022 count the same. Spending growth has data for only 2 of the 6, since
  the series starts in 2007.
- **Where the run starts changes everything.** "Just before the run" for the 2022 increases means
  early 2022, right after the reopening boom. As of August 2024 it reports spending growth falling
  from 6.7% to 2.6%, mostly the boom fading rather than the Fed.
- **The Baa spread measures credit risk.** It widens in downturns whatever the Fed does, so it's a
  weak sign that rate changes are getting through.
- **The Treasury's average rate moves slowly**, because the debt takes about six years on average
  to roll over. A small change since the first increase is expected.

---

## How the minutes' direction is read

Both assessEconomy and the next-meeting reading need one answer from the latest minutes: do
participants lean toward raising, cutting or holding?

**The AI's score.** Ahead of time, Qwen3 4B reads the paragraphs of each set of minutes about the
rate path (code picks them, since the full minutes don't fit the model's window) and scores it from
−1 (lean to cuts) to +1 (lean to increases), using the rubric in the `fomc-score` skill. It
must quote the sentences behind its score, and code checks the quotes are really in the minutes.
A score of +0.5 or more reads as "increase", −0.5 or less as "cut", anything between as "hold".
When rates are already at zero, a lean to cuts reads as "hold", since the rate can't go lower.

**The word rules (the fallback).** For minutes whose AI score failed its checks (none of the 150
saved scores now), code reads the sentences about future rate moves and weighs them by how many held each view: "all
participants" counts most, then "most", "many", "several", "a few", "one". The most widely held
view that isn't conditional on the data gives the lean.

**How well each did.** Right about the next decision, with cutoffs chosen on 2008 to 2018 and
then tested unchanged on 2019 onward:

| | 2008 to 2018 (87 meetings) | 2019 onward (62 meetings) |
|---|---|---|
| AI score (word rules where it failed) | 83% | 79% |
| Word rules alone | 71% | 76% |
| 6-month bill | 93% | 84% |
| Always guess "hold" | 85% | 65% |

From 2019 onward, of 22 moves, the AI caught 20 and called 11 that didn't happen; the word rules
caught 18 and also called 11 that didn't; the bill caught 14 and called 2. So the AI catches the
most moves but calls as many that didn't happen as the word rules. The bill is best for the very
next meeting, which is why the reading uses the minutes for direction and the bill for timing.
Calling a move only when both point the same way was right 85% from 2019 onward (14 caught,
1 false).

**What could be wrong:**
- **The score mixes this meeting's decision with what comes next.** The rubric puts a rate
  increase at +0.5 to +1 and a cut at −0.5 to −1, at or past the cutoff, and the scorer is told the
  decision. So every meeting that moved reads as another move next, partly saying "they just cut,
  so they'll cut again". The October and December 2025 cuts read as "cut next", though the
  minutes expected a pause.
- **Hindsight.** The model was trained on text written after most of these meetings, and may know
  what the Fed did next. That would make its scores of older minutes look better than they are.
- **The scores are coarse.** The model picks a row of the rubric rather than writing a number,
  and for the rate path it mostly picks the strongest rows: a hold with a lean scores −0.75 or +1,
  so a hold that says little either way and one that all but promises a move score the same.
  The holds near zero from 2009 to 2014 mostly score −0.75 (any lean to cuts there reads as a
  hold, since the rate can't go lower).
- **Scores used to vary from run to run.** At temperature 0.2, 6 of 15 meetings scored three times
  moved by 0.25. The saved scores were made again on 2026-11-05 at temperature 0, which gives the
  same score each time.
- **The cutoff was chosen on few moves.** 2008 to 2018 had only 13 rate changes, most of that time
  at zero.

---

## Open questions

1. **When should a run end?** Right now a run goes on through any number of holds. The 2019 cuts
   and the March 2020 emergency cuts count as one run. From 2009 to 2015, "just before the run"
   still meant September 2007. Should a run end after, say, 4 meetings with no change?
2. **Should the bill be put on the same footing as the fed funds rate** (a 360-day year) before
   comparing them? Is 0.275 right both near zero and at 5%?
3. **Policy rules:** keep core PCE and CBO potential? Add a rule that moves gradually, which tracks
   the Fed better? Is 0.5% and 2% the right pair for the neutral rate?
4. **The minutes' direction:** keep the score as it is, or score only what participants expect next?
5. **Base rates:** are counts like "raised 15 times, held twice (of 17)" useful, or do they invite
   reading them as odds? Should the minimum be more than 3?
6. **Trend threshold:** is 0.1 point over three months too sensitive for unemployment?
7. **getOutlook's steps:** is this the right set? Should the Baa spread go, or the inflation-adjusted
   10-year yield be added?
8. **"Is now a good time to buy a house?"** runs getOutlook. The tool gives evidence, not advice,
   but should a question like that run it at all?

**Code:** `src/+fomc/+tools/getPolicyPath.m`, `assessEconomy.m` (→ `fomc.data.economyAssessment`,
`nextMeetingReading`, `billSignal`), `getOutlook.m` (→ `fomc.data.outlookAssessment`,
`forecastRevisions`), and `fomc.data.minutesDirection` (→ `policyViews`, `data/scores/`). The full
interface is in `docs/agent_interface.md`.
