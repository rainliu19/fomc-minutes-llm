"""Tests for saved chats and the model list. No model, no MATLAB.

    uv run python -m unittest tests/test_chats.py
"""
import json
import re
import contextlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent.parent))

from server.chats import ChatStore  # noqa: E402

REPO = Path(__file__).parent.parent


def reply(text, ids=()):
    return {"answer": text, "structured": None, "warning": "", "tool_calls": [], "seconds": 3, "anchor": "2020-04-08",
            "citations": [{"id": i, "ok": True} for i in ids]}


ME, YOU = "a" * 32, "b" * 32                  # two different browsers


class Store(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = ChatStore(Path(self.tmp.name) / "chats")
        self.settings = {"as_of": "2020-04-08", "model": "qwen3", "effort": "low"}

    def tearDown(self):
        self.tmp.cleanup()

    def test_a_new_chat_is_titled_from_its_first_question(self):
        self.store.append("c1", ME, self.settings, "What did the Committee decide?", reply("A cut."))
        self.assertEqual(self.store.list(ME)[0]["title"], "What did the Committee decide?")

    def test_messages_alternate_user_then_assistant(self):
        self.store.append("c1", ME, self.settings, "Q1", reply("A1"))
        self.store.append("c1", ME, self.settings, "Q2", reply("A2"))
        roles = [m["role"] for m in self.store.get("c1", ME)["messages"]]
        self.assertEqual(roles, ["user", "assistant", "user", "assistant"])

    def test_the_list_is_newest_first(self):
        self.store.append("old", ME, self.settings, "first", reply("a"))
        self.store.append("new", ME, self.settings, "second", reply("b"))
        self.store.append("old", ME, self.settings, "again", reply("c"))
        self.assertEqual([c["id"] for c in self.store.list(ME)], ["old", "new"])

    def test_rename_changes_the_title_and_ignores_blank(self):
        self.store.append("c1", ME, self.settings, "Q", reply("A"))
        self.assertTrue(self.store.rename("c1", ME, "  March 2020   cut  "))
        self.assertEqual(self.store.get("c1", ME)["title"], "March 2020 cut")
        self.assertFalse(self.store.rename("c1", ME, "   "))
        self.assertFalse(self.store.rename("missing", ME, "x"))

    def test_delete_removes_the_chat(self):
        self.store.append("c1", ME, self.settings, "Q", reply("A"))
        self.assertTrue(self.store.delete("c1", ME))
        self.assertIsNone(self.store.get("c1", ME))
        self.assertFalse(self.store.delete("c1", ME))          # deleting twice is fine

    def test_seed_is_empty_for_a_new_chat(self):
        self.assertEqual(self.store.seed("nothing", ME), "")

    def test_seed_keeps_the_last_four_pairs_and_the_verified_ids(self):
        for i in range(6):
            self.store.append("c1", ME, self.settings, f"Q{i}", reply(f"A{i}", ids=[f"2020-01-29/policyAction/{i}"]))
        seed = json.loads(self.store.seed("c1", ME))
        self.assertEqual([p["q"] for p in seed], ["Q2", "Q3", "Q4", "Q5"])
        self.assertEqual(seed[-1]["ids"], ["2020-01-29/policyAction/5"])

    def test_a_damaged_file_is_ignored(self):
        self.store.append("c1", ME, self.settings, "Q", reply("A"))
        (self.store.folder / "bad.json").write_text("{not json")
        self.assertEqual([c["id"] for c in self.store.list(ME)], ["c1"])


class Privacy(unittest.TestCase):
    """One browser must never see, change or continue another browser's chats."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = ChatStore(Path(self.tmp.name) / "chats")
        self.settings = {"as_of": "2020-04-08", "model": "qwen3", "effort": "low"}
        self.store.append("mine", ME, self.settings, "my private question", reply("my answer"))

    def tearDown(self):
        self.tmp.cleanup()

    def test_the_other_browser_sees_an_empty_list(self):
        self.assertEqual(self.store.list(YOU), [])

    def test_the_other_browser_cannot_open_rename_delete_or_seed_it(self):
        self.assertIsNone(self.store.get("mine", YOU))
        self.assertFalse(self.store.rename("mine", YOU, "hijacked"))
        self.assertFalse(self.store.delete("mine", YOU))
        self.assertEqual(self.store.seed("mine", YOU), "")
        self.assertEqual(self.store.get("mine", ME)["title"], "my private question")

    def test_the_other_browser_cannot_add_to_it(self):
        self.assertTrue(self.store.owned_by_other("mine", YOU))
        self.assertFalse(self.store.owned_by_other("mine", ME))
        with self.assertRaises(PermissionError):
            self.store.append("mine", YOU, self.settings, "intruder", reply("x"))
        self.assertEqual(len(self.store.get("mine", ME)["messages"]), 2)

    def test_each_browser_keeps_its_own_chats_with_the_same_titles(self):
        self.store.append("yours", YOU, self.settings, "my private question", reply("your answer"))
        self.assertEqual([c["id"] for c in self.store.list(ME)], ["mine"])
        self.assertEqual([c["id"] for c in self.store.list(YOU)], ["yours"])

    def test_a_chat_without_an_owner_is_nobodys(self):
        (self.store.folder / "old.json").write_text(json.dumps({"id": "old", "title": "x", "created": 1, "updated": 1, "messages": []}))
        for owner in (ME, YOU):
            self.assertNotIn("old", [c["id"] for c in self.store.list(owner)])
            self.assertIsNone(self.store.get("old", owner))


class OwnerCookie(unittest.TestCase):
    """The app hands each new browser an owner id and keeps using it."""

    def request(self, cookie=None):
        from starlette.requests import Request
        headers = [(b"cookie", cookie.encode())] if cookie else []
        return Request({"type": "http", "headers": headers})

    def test_a_new_browser_gets_a_random_owner_and_a_cookie(self):
        from starlette.responses import Response
        import app
        response = Response()
        owner = app.owner_of(self.request(), response)
        self.assertRegex(owner, r"^[0-9a-f]{32}$")
        self.assertIn(f"{app.OWNER_COOKIE}={owner}", response.headers["set-cookie"])
        self.assertIn("HttpOnly", response.headers["set-cookie"])

    def test_two_new_browsers_get_different_owners(self):
        from starlette.responses import Response
        import app
        self.assertNotEqual(app.owner_of(self.request(), Response()), app.owner_of(self.request(), Response()))

    def test_a_returning_browser_keeps_its_owner(self):
        from starlette.responses import Response
        import app
        response = Response()
        self.assertEqual(app.owner_of(self.request(f"{app.OWNER_COOKIE}={ME}"), response), ME)
        self.assertNotIn("set-cookie", response.headers)

    def test_a_made_up_cookie_is_replaced(self):
        from starlette.responses import Response
        import app
        owner = app.owner_of(self.request(f"{app.OWNER_COOKIE}=../../etc"), Response())
        self.assertRegex(owner, r"^[0-9a-f]{32}$")


class ApiPrivacy(unittest.TestCase):
    """The endpoints themselves, called as two different browsers."""

    def setUp(self):
        import app
        self.app = app
        self.tmp = tempfile.TemporaryDirectory()
        self.original = app.store
        app.store = ChatStore(Path(self.tmp.name) / "chats")
        self.logs = mock.patch.object(app.runtime, "LOGS", Path(self.tmp.name) / "logs")   # never the repo's own logs
        self.logs.start()
        app.store.append("c" * 32, ME, {"as_of": "2020-04-08", "model": "qwen3", "effort": "low"}, "secret", reply("hidden"))

    def tearDown(self):
        self.logs.stop()
        self.app.store = self.original
        self.tmp.cleanup()

    def test_listing_opening_renaming_and_deleting_are_limited_to_the_owner(self):
        cid = "c" * 32
        self.assertEqual([c["id"] for c in self.app.list_chats(owner=ME)], [cid])
        self.assertEqual(self.app.list_chats(owner=YOU), [])
        self.assertEqual(self.app.get_chat(cid, owner=YOU), {})
        self.assertFalse(self.app.rename_chat(cid, "x", owner=YOU)["ok"])
        self.assertEqual(self.app.delete_chat(cid, owner=YOU)["status"], "not found")
        self.assertTrue(self.app.get_chat(cid, owner=ME)["messages"])

    def test_progress_of_another_browsers_chat_is_hidden(self):
        self.assertEqual(self.app.progress("c" * 32, 0, owner=YOU), {"events": [], "next": 0})

    def test_progress_passes_the_agent_events_through(self):
        events = [{"type": "route", "route": "household", "agents": ["minutes", "market"]},
                  {"type": "handoff", "to": "minutes", "stage": 1, "tools": ["getDecision"]},
                  {"type": "tool_call", "name": "getDecision", "agent": "minutes", "ok": True, "ms": 5},
                  {"type": "handback", "agent": "minutes", "ok": False, "ms": 9, "error": "boom"},
                  {"type": "critic", "round": 1, "pass": True, "issues": ""}]
        path = self.app.runtime.LOGS / ("web-" + "c" * 32 + ".jsonl")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(json.dumps(e) for e in events) + "\n", encoding="utf-8")
        got = self.app.progress("c" * 32, 0, owner=ME)["events"]
        for want, have in zip(events, got):
            for key, value in want.items():
                self.assertEqual(have[key], value, key)

    def test_progress_passes_the_timeline_fields_clips_results_and_stops_at_before(self):
        events = [{"type": "message", "agent": "writer", "role": "user", "text": "Q", "from": ["minutes"]},
                  {"type": "handoff", "to": "consumer", "reads": ["minutes", "market"]},
                  {"type": "agent_model", "agent": "market", "skipped": True, "reason": "under"},
                  {"type": "tool_call", "name": "getSnapshot", "result": "x" * 5000, "ok": True},
                  {"type": "model_response", "content": "later"}]
        path = self.app.runtime.LOGS / ("web-" + "c" * 32 + ".jsonl")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(json.dumps(e) for e in events) + "\n", encoding="utf-8")
        got = self.app.progress("c" * 32, 1, before=4, owner=ME)
        self.assertEqual([e["type"] for e in got["events"]], ["handoff", "agent_model", "tool_call"])
        self.assertEqual(got["events"][0]["reads"], ["minutes", "market"])
        self.assertTrue(got["events"][1]["skipped"])
        self.assertLessEqual(len(got["events"][2]["result"]), 1503)
        self.assertEqual(got["next"], 4)

    def test_a_chat_reply_says_which_trace_lines_it_made_and_whether_a_team_answered(self):
        app = self.app
        sid = "d" * 32
        trace = app.runtime.LOGS / f"web-{sid}.jsonl"
        trace.parent.mkdir(parents=True, exist_ok=True)
        trace.write_text("old\n", encoding="utf-8")
        seen = {}

        def fake_matlab(name, *args, nargout=1):
            seen["args"] = args
            with trace.open("a", encoding="utf-8") as f:
                f.write("one\ntwo\n")
            return json.dumps({"answer": "A", "structured": None, "citations": [], "warning": "", "toolCalls": [],
                               "seconds": 1, "anchorDate": "2020-04-08"})

        with mock.patch.object(app, "matlab_call", fake_matlab), mock.patch.object(app, "watchdog", contextlib.nullcontext()), \
                mock.patch.object(app.runtime, "ensure_ollama"), mock.patch.object(app.runtime, "ensure_model"), \
                mock.patch.object(app.runtime, "memory_verdict", return_value=("ok", "")):
            one = app.chat(app.ChatRequest(message="hi", session_id=sid, agents="one"), owner=ME)
            default = app.chat(app.ChatRequest(message="again", session_id=sid), owner=ME)
        self.assertEqual(one["trace"], [1, 3])
        self.assertEqual(one["agents"], "one")
        self.assertEqual(seen["args"][-1], "team")           # the default is the team
        self.assertEqual(default["trace"], [3, 5])
        saved = app.get_chat(sid, owner=ME)
        self.assertEqual(saved["agents"], "team")
        self.assertEqual([m.get("trace") for m in saved["messages"] if m["role"] == "assistant"], [[1, 3], [3, 5]])

    def test_chatting_into_another_browsers_chat_is_refused(self):
        req = self.app.ChatRequest(message="hi", session_id="c" * 32)
        answer = self.app.chat(req, owner=YOU)
        self.assertIn("another browser", answer["answer"])


class ModelList(unittest.TestCase):
    def setUp(self):
        self.models = json.loads((REPO / "models" / "models.json").read_text())

    def test_every_model_has_a_modelfile_with_a_from_line(self):
        for m in self.models:
            text = (REPO / "models" / m["id"] / "Modelfile").read_text()
            self.assertRegex(text, r"(?m)^FROM\s+\S+", m["id"])

    def test_ids_and_ollama_names_are_unique(self):
        self.assertEqual(len({m["id"] for m in self.models}), len(self.models))
        self.assertEqual(len({m["name"] for m in self.models}), len(self.models))

    def test_the_first_model_is_the_default_and_three_are_offered(self):
        self.assertEqual(self.models[0]["id"], "fast")      # IBM Granite 3.3 2B: the best accuracy for its memory
        self.assertEqual([m["id"] for m in self.models if m.get("offered", True)], ["fast", "qwen3", "q25-05"])

    def test_every_model_has_a_parameter_count_for_the_evaluation(self):
        for m in self.models:
            self.assertGreater(m["params_b"], 0, m["id"])


class Evaluation(unittest.TestCase):
    """The key and the saved evaluations that the /evaluation page shows."""

    def test_the_key_has_57_cases_with_questions_and_checks(self):
        # 50 drawn from the decision cards, and 7 forward-looking ones fixed by hand (4 nextmove, 3 outlook)
        key = json.loads((REPO / "evals" / "key.json").read_text())
        self.assertEqual(len(key), 57)
        self.assertEqual(len({c["id"] for c in key}), 57)
        self.assertEqual(sum(c["category"] == "nextmove" for c in key), 4)
        self.assertEqual(sum(c["category"] == "outlook" for c in key), 3)
        for c in key:
            self.assertTrue(c["questions"] and c["as_of"], c["id"])
            for rx in c["checks"] + c["forbid"]:
                re.compile(rx)                       # every pattern is a valid regex

    def test_the_lookahead_route_returns_each_held_out_set_with_its_key_and_runs(self):
        import app
        got = app.evals_lookahead()
        self.assertEqual(set(got), {"fresh", "unseen"})      # the development key and retired runs (archive) are not served
        for name, d in got.items():
            self.assertTrue(d["key"], name)
            for r in d["runs"]:
                self.assertIn("overall", r["summary"])
                self.assertEqual(len(r["cases"]), r["summary"]["n_done"])

    def test_every_run_has_tokens_and_a_cloud_api_cost_that_matches_the_price_table(self):
        import app
        prices = json.loads((REPO / "models" / "api_prices.json").read_text())["models"]
        runs = app.evals()
        self.assertEqual(len(runs), len(list((REPO / "evals").glob("*.json"))) - 1)    # every run but key.json
        for r in runs:
            t = r["summary"]["tokens"]
            self.assertGreaterEqual(t["in_per_question"], 0)
            for p in prices:
                self.assertGreater(p["usd_per_mtok_in"], 0)
                want = (t["total_in"] * p["usd_per_mtok_in"] + t["total_out"] * p["usd_per_mtok_out"]) / 1e6 / r["summary"]["n_cases"] * 1000
                self.assertAlmostEqual(t["api_cost_per_1000"][p["id"]], want, delta=0.01, msg=r["summary"]["model"])


if __name__ == "__main__":
    unittest.main()
