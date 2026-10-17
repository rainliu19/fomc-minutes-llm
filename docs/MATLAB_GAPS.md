# MATLAB gaps

What the agent needed that MATLAB (R2026b) or the "Large Language Models (LLMs) with MATLAB" add-on (4.9.0) did not provide, and the workaround. Python is used only for the web page (gap 8).

| # | Needed | What was missing | Workaround | Status |
|---|--------|------------------|------------|--------|
| 1 | A list-valued tool parameter (several series ids) | `openAIFunction`/`addParameter` accept only string, number, integer, object, boolean, null: no array type | `getSeries` takes `seriesIds` as one comma-separated string | Works |
| 2 | A parameter named `end` | `addParameter` needs a valid variable name, and `end` is a keyword | Use `startDate` and `endDate` | Works |
| 3 | A bigger context window for the local model | `ollamaChat` forwards a fixed set of options without `num_ctx`; Ollama's default window can cut off long prompts | `models/qwen3/Modelfile` builds a model with `num_ctx 8192` (one `ollama create`) | Works; one manual step outside MATLAB |
| 4 | An evaluation framework like Inspect AI | `matlab.unittest` covers deterministic checks, but nothing for model-graded scorers, repeated runs or trace viewing | Plain functions and `matlab.unittest` classes; a scorer harness is planned in `fomc.rubric` | Open |
| 5 | The same tool-call format from every backend | The add-on returns tool-call arguments as a decoded struct for Ollama, but its OpenAI example decodes a JSON string | `fomc.tools.dispatch` accepts either (only the Ollama shape is tested) | Works for Ollama |
| 6 | Long model calls from the MATLAB MCP server | `evaluate_matlab_code` moves calls over 120 s to a background task | Start the run, collect the result when it finishes | Tooling limit |
| 7 | Turning off Qwen3's "thinking" pass | `ollamaChat` has no `think` option; `/no_think` had no effect, and `think: false` sent straight to Ollama put the reasoning in the answer. Thinking cost 3 to 5 minutes per call | Use `qwen3:4b-instruct`, which does not think: calls take 5 to 30 s | Works; tied to that model family |
| 8 | A local web server for a chat page (like the course demos) | Base MATLAB has no easy HTTP server; MATLAB Production Server is a separate product | `app.py` and `server/runtime.py`: a thin FastAPI shell that calls the agent through the MATLAB Engine API for Python (`matlabengine`). No agent logic in Python | Works; `fomc.chat()` needs no Python |

## Observed, not blocking

- MATLAB regular expressions read `\b` as a backspace, not a word boundary, so `\bword\b` silently matches nothing. Use lookarounds, `(?<![A-Za-z])word(?![A-Za-z])` (see `fomc.data.decisionCards`).
- The MATLAB MCP server tool dropped when the desktop was closed and did not reconnect when MATLAB reopened. Tests were run through the MATLAB Engine for Python instead.
- `openAIChat` calls only the Chat Completions endpoint, and its `ReasoningEffort` accepts `auto, none, minimal, low, medium, high, xhigh`. OpenAI's model pages say some models support tool calling only through the Responses API and list a `max` effort. Matters only if a hosted OpenAI model is used later (read from the add-on source and OpenAI's pages; not tested).
- `messageHistory` stores Chat Completions style messages, so it cannot hold the reasoning items a Responses API client must pass back.
