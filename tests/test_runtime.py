"""Tests for the memory guard and input safety. No model, no MATLAB.

    uv run python -m unittest tests/test_runtime.py
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from server import runtime  # noqa: E402
from app import clean_session_id  # noqa: E402


# Helper: a made-up memory reading to feed the checker
def status(free, swap, level=1):
    return {"free_pct": free, "swap_used_mb": swap, "swap_total_mb": 4096.0, "pressure": level}


# Does the memory check say ok, warn or refuse in the right situations?
class MemoryVerdict(unittest.TestCase):
    def test_plenty_of_memory_is_ok(self):
        self.assertEqual(runtime.memory_verdict(status(60, 800), model_loaded=False)[0], "ok")

    def test_a_loaded_model_leaves_free_memory_low_on_a_healthy_machine(self):
        # Measured live: 4 to 7% free while the model ran, with normal pressure: not a reason to stop.
        self.assertEqual(runtime.memory_verdict(status(5, 2300, 1), model_loaded=True)[0], "ok")

    def test_low_free_memory_before_the_model_loads_is_refused(self):
        verdict, message = runtime.memory_verdict(status(10, 800), model_loaded=False)
        self.assertEqual(verdict, "refuse")
        self.assertIn("Close other apps", message)

    def test_tight_memory_before_the_model_loads_warns(self):
        self.assertEqual(runtime.memory_verdict(status(35, 800), model_loaded=False)[0], "warn")

    def test_warning_pressure_warns(self):
        self.assertEqual(runtime.memory_verdict(status(30, 1000, 2))[0], "warn")

    def test_critical_pressure_is_refused(self):
        self.assertEqual(runtime.memory_verdict(status(30, 1000, 4))[0], "refuse")

    def test_runaway_swap_is_refused_even_with_normal_pressure(self):
        self.assertEqual(runtime.memory_verdict(status(60, 3600, 1))[0], "refuse")

    def test_the_state_that_froze_the_machine_is_refused(self):
        # 8% free and 3.1 GB swap: caught at start by free % (model not loaded) and mid-run by pressure level
        self.assertEqual(runtime.memory_verdict(status(8, 3132, 1), model_loaded=False)[0], "refuse")
        self.assertEqual(runtime.memory_verdict(status(8, 3132, 4), model_loaded=True)[0], "refuse")

    def test_unknown_memory_does_not_block(self):
        self.assertEqual(runtime.memory_verdict(status(None, None, None))[0], "ok")

    def test_thresholds_are_ordered(self):
        self.assertLess(runtime.REFUSE_FREE_PCT, runtime.WARN_FREE_PCT)
        self.assertLess(runtime.WARN_SWAP_MB, runtime.REFUSE_SWAP_MB)
        self.assertLess(runtime.REFUSE_SWAP_MB, runtime.PANIC_SWAP_MB)

    def test_live_status_has_the_expected_keys(self):
        s = runtime.memory_status()
        self.assertEqual(set(s), {"free_pct", "swap_used_mb", "swap_total_mb", "pressure"})

    def test_top_apps_lists_the_biggest_first(self):
        apps = runtime.top_apps(3)
        self.assertLessEqual(len(apps), 3)
        self.assertEqual(apps, sorted(apps, reverse=True))


# Is an open MATLAB found in a list of running programs?
class OpenMatlab(unittest.TestCase):
    DESKTOP = "/Applications/MATLAB_R2026b.app/bin/maca64/../../Contents/MacOS/MATLAB_maca64\n"

    def test_an_open_matlab_is_detected(self):
        ps = "/usr/bin/python3\n" + self.DESKTOP + "/Applications/Safari.app/Contents/MacOS/Safari\n"
        self.assertTrue(runtime.matlab_running(ps))

    def test_no_matlab_is_not_detected(self):
        self.assertFalse(runtime.matlab_running("/usr/bin/python3\n/Applications/Safari.app/Contents/MacOS/Safari\n"))

    def test_other_programs_with_matlab_in_their_name_are_not_confused_for_it(self):
        self.assertFalse(runtime.matlab_running("/Users/me/matlab-notes/viewer\n/opt/MATLAB_helper_script\n"))

    def test_empty_process_list(self):
        self.assertFalse(runtime.matlab_running(""))


# The memory-saving Ollama settings stay in place
class OllamaSettings(unittest.TestCase):
    def test_model_memory_is_released_soon_after_use(self):
        self.assertEqual(runtime.OLLAMA_ENV["OLLAMA_KEEP_ALIVE"], "3m")

    def test_one_model_and_one_request_at_a_time(self):
        self.assertEqual(runtime.OLLAMA_ENV["OLLAMA_NUM_PARALLEL"], "1")
        self.assertEqual(runtime.OLLAMA_ENV["OLLAMA_MAX_LOADED_MODELS"], "1")


# Session ids become file names, so unsafe ones must be replaced
class SessionIds(unittest.TestCase):
    def test_a_plain_id_is_kept(self):
        self.assertEqual(clean_session_id("aaaaaaaa-1111-2222-3333-444444444444"),
                         "aaaaaaaa-1111-2222-3333-444444444444")

    def test_a_path_is_replaced_because_ids_become_file_names(self):
        for bad in ["../../etc/passwd", "a/b", "x" * 100, "", None, "ABC DEF"]:
            cleaned = clean_session_id(bad)
            self.assertRegex(cleaned, r"^[0-9a-f-]{8,40}$")
            self.assertNotEqual(cleaned, bad)


if __name__ == "__main__":
    unittest.main()
