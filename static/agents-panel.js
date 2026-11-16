// The agent timeline: one column per agent, one row per step, in the order things happened, so you can see who
// was asked what, what each agent found, and what it passed on. Adapted from the course demo's context-panel.js
// (wikipedia-deep-research), drawn from this app's trace events (the /progress endpoint) instead of the SDK's hooks.
//   agentsPanel.start()            a new question: clear the panel and show it
//   agentsPanel.add(events)        draw these trace events (call again as more arrive)
//   agentsPanel.open(sid, [a, b])  show an answer already given: trace lines a to b of the chat
//   agentsPanel.close()
const agentsPanel = (() => {
  const panel = document.getElementById("agents"), grid = document.getElementById("agentgrid");
  const FOLD = 700;                       // longer text folds to its start, as in the demo
  let columns = [], row = 1;

  const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };
  const list = (x) => [].concat(x || []);

  // What one trace event draws: rows of {agent, role, label, text, dim}; none for events not worth a row
  function cells(e) {
    const who = e.agent || "";
    switch (e.type) {
      case "route":
        return [{agent: "organizer", role: "user", label: "question", text: e.question},
                {agent: "organizer", role: "note", label: "routed by code", text: `${e.route}: ${list(e.agents).join(" → ")}`}];
      case "handoff":
        return [{agent: "organizer", role: "note", label: `hands over to ${e.to}`,
                 text: `tools: ${list(e.tools).join(", ") || "none"}` +
                       (list(e.reads).length ? `; briefed with the reports of ${list(e.reads).join(", ")}` : "")}];
      case "handback":
        return [{agent: who, role: "assistant", label: e.ok ? `report to the organizer (${e.ms} ms)` : "failed", text: e.ok ? e.text : e.error}];
      case "agent_model":
        return [{agent: who, role: "note", label: "model",
                 text: e.skipped ? `not run: ${e.reason}`
                     : `ran for ${e.ms} ms; ` + (e.fallback ? `its report was not used (${e.reason}): the code's evidence passes instead` : "its report is kept")}];
      case "message": {
        const from = list(e.from);
        return [{agent: who, role: e.role, dim: from.length > 0,
                 label: e.role === "note" ? "" : (e.role === "system" ? "system prompt" : e.role) + (from.length ? ` (from ${from.join(", ")})` : ""),
                 text: e.text}];
      }
      case "model_response":
        return [{agent: who, role: "assistant", label: `reply (${e.ms} ms)`,
                 text: (e.content || "") + (e.nToolCalls ? `\n[asked for ${e.nToolCalls} tool call(s)]` : "") || "(no text)"}];
      case "tool_call":
        return who ? [{agent: who, role: "tool", label: `${e.name}(${Object.entries(e.args || {}).map(([k, v]) => `${k}: ${typeof v === "string" ? v : JSON.stringify(v)}`).join(", ")})`
                       + ` · ${e.ms} ms${e.ok === false ? " · error" : ""}`, text: e.result}] : [];
      case "nudge":
        return [{agent: who, role: "note", label: "", text: "Reminded to read the minutes first"}];
      case "critic":
        return [{agent: "critic", role: "note", label: `round ${e.round}`, text: e.pass ? "passed" : `found a problem: ${e.issues}`}];
      case "parallel_off":
        return [{agent: "organizer", role: "note", label: "", text: `Ran one at a time: ${e.reason}`}];
      default:
        return [];
    }
  }

  function column(agent) {
    let n = columns.indexOf(agent);
    if (n < 0) {
      columns.push(agent);
      n = columns.length - 1;
      const head = el("div", "ahead", agent);
      head.style.gridColumn = n + 1;
      head.style.gridRow = 1;
      grid.append(head);
      grid.style.setProperty("--cols", columns.length);
    }
    return n + 1;
  }

  function draw(c) {
    const cell = el("div", `acell ${c.role}${c.dim ? " dim" : ""}`);
    if (c.label) cell.append(el("div", "arole", c.label));
    const text = String(c.text ?? "");
    if (text.length > FOLD) {
      const d = el("details");
      d.append(el("summary", null, `${text.slice(0, 200)}... (${text.length} characters)`), el("pre", null, text));
      cell.append(d);
    } else {
      cell.append(text);
    }
    cell.style.gridColumn = column(c.agent || "agent");
    cell.style.gridRow = ++row;
    grid.append(cell);
  }

  function clear() { grid.innerHTML = ""; columns = []; row = 1; }

  return {
    start() { clear(); panel.hidden = false; },
    add(events) {
      const atEnd = panel.scrollTop + panel.clientHeight >= panel.scrollHeight - 40;
      events.forEach((e) => cells(e).forEach(draw));
      if (events.length) panel.hidden = false;
      if (atEnd) panel.scrollTop = panel.scrollHeight;
    },
    async open(sessionId, range) {
      clear();
      const r = await (await fetch(`/progress?session_id=${sessionId}&after=${range[0]}&before=${range[1]}`)).json();
      this.add(r.events);
      panel.hidden = false;
      panel.scrollTop = 0;
    },
    close() { panel.hidden = true; },
  };
})();
