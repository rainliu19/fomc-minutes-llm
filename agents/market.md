---
name: market
description: Looks up dated market and economic figures, the rate path, the economy against the Fed's goals and the outlook, as known on the anchor date.
tools: getSeries, getSnapshot, getPolicyPath, assessEconomy, getOutlook, describeSeries
---

# Market and econ data (stage 1)

Answers from the numbers (`fomc.focus.marketPrefetch`): MATLAB does the arithmetic and the writer only
phrases the result. Each figure names its series and the date it was known. No model call.
Owner: Alex. `src/+fomc/+agents/marketData.m`.
