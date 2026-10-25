"""Start, watch and stop what the web app depends on: Ollama, MATLAB and memory.

On an 8 GB Mac the model, MATLAB and the browser compete for memory, and the model's memory
cannot be swapped out. So the app checks memory before it starts, watches it while a question
runs, and cleans up every process it started.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

import matlab.engine

HERE = Path(__file__).parent.parent          # the repo root: src/ (MATLAB), data/, models/, logs/
LOGS = HERE / "logs"

OLLAMA_URL = "http://127.0.0.1:11434"
MODELS_DIR = HERE / "models"                 # one folder per model, each with a Modelfile; models.json lists them
OLLAMA_ENV = {
    "OLLAMA_FLASH_ATTENTION": "1",           # less memory for the attention cache
    "OLLAMA_KV_CACHE_TYPE": "q8_0",          # half-size cache
    "OLLAMA_NUM_PARALLEL": "1",              # one request at a time: no extra caches
    "OLLAMA_MAX_LOADED_MODELS": "1",
    "OLLAMA_KEEP_ALIVE": "3m",               # free the model's memory 3 minutes after the last answer
}

# Memory limits. The macOS pressure level (1 normal, 2 warning, 4 critical) is the signal that
# matters. Free percentage is meaningful only before the model loads (a loaded model leaves it at
# 4 to 7% on a healthy machine); swap in use backs it up.
REFUSE_FREE_PCT, WARN_FREE_PCT = 20, 40      # at start, before the model is loaded
WARN_SWAP_MB, REFUSE_SWAP_MB, PANIC_SWAP_MB = 2500, 3500, 3800
PANIC_SAMPLES = 2                            # critical pressure this many 5-second checks in a row

ollama_process = None                        # set only if this app started Ollama
panic_reason = None                          # set by the watchdog if it had to stop the model


# --- MEMORY ---

def memory_status() -> dict:
    """Pressure level, free memory percentage and swap in use, from macOS. Missing values are None."""
    # Start with unknowns; fill each in from a macOS command, and leave it unknown if the command fails
    status = {"free_pct": None, "swap_used_mb": None, "swap_total_mb": None, "pressure": None}
    try:
        # Pressure level (1 normal, 2 warning, 4 critical)
        out = subprocess.run(["sysctl", "-n", "kern.memorystatus_vm_pressure_level"],
                             capture_output=True, text=True, timeout=5).stdout.strip()
        if out.isdigit():
            status["pressure"] = int(out)
        # Percentage of memory free
        out = subprocess.run(["memory_pressure"], capture_output=True, text=True, timeout=10).stdout
        m = re.search(r"free percentage:\s*(\d+)%", out)
        if m:
            status["free_pct"] = int(m.group(1))
        # Swap in use: memory pushed out to disk
        out = subprocess.run(["sysctl", "-n", "vm.swapusage"], capture_output=True, text=True, timeout=5).stdout
        m = re.search(r"total = ([\d.]+)M\s+used = ([\d.]+)M", out)
        if m:
            status["swap_total_mb"], status["swap_used_mb"] = float(m.group(1)), float(m.group(2))
    except (OSError, subprocess.SubprocessError):
        pass
    return status


def top_apps(n: int = 6) -> list[tuple[int, str]]:
    """The apps using the most memory, as (MB, name), so the user knows what to close."""
    try:
        # List every process with its memory use (in KB), then keep the biggest
        out = subprocess.run(["ps", "-axo", "rss=,comm="], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    rows = []
    for line in out.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0].isdigit():
            rows.append((int(parts[0]) // 1024, Path(parts[1]).name))
    return sorted(rows, reverse=True)[:n]


def memory_verdict(status: dict | None = None, model_loaded: bool = True) -> tuple[str, str]:
    """('ok' | 'warn' | 'refuse', message) for the current memory state.

    Before the model loads, free percentage is a fair signal; once loaded, pressure level and swap are used.
    """
    # Describe the state in one line of text
    status = status or memory_status()
    free, swap, level = status["free_pct"], status["swap_used_mb"], status.get("pressure")
    parts = []
    if free is not None: parts.append(f"{free}% free")
    if swap is not None: parts.append(f"{swap:.0f} MB swap")
    if level is not None: parts.append({1: "pressure normal", 2: "pressure warning", 4: "pressure critical"}.get(level, f"pressure {level}"))
    summary = ", ".join(parts) or "memory unknown"
    # Refuse when pressure is critical or swap is very high (before the model loads, also when little is free)
    if level == 4 or (swap is not None and swap > REFUSE_SWAP_MB) or \
            (not model_loaded and free is not None and free < REFUSE_FREE_PCT):
        return "refuse", f"Not enough memory ({summary}). Close other apps, especially MATLAB and browsers, and try again."
    # Warn when memory is tight but usable
    if (level is not None and level >= 2) or (swap is not None and swap > WARN_SWAP_MB) or \
            (not model_loaded and free is not None and free < WARN_FREE_PCT):
        return "warn", f"Memory is tight ({summary}). Closing other apps will make answers faster."
    return "ok", summary


def matlab_running(ps_output: str) -> bool:
    """True if a process list (ps -axo comm=) shows a MATLAB running, desktop or hidden."""
    return any(Path(line.strip()).name == "MATLAB_maca64" for line in ps_output.splitlines() if line.strip())


def check_matlab_at_start() -> None:
    """Refuse to start next to an open MATLAB this app cannot reuse.

    An open MATLAB desktop uses about 1.8 GB; with the model and a hidden MATLAB on top, an 8 GB Mac
    runs out of memory. If it has shared its session (matlab.engine.shareEngine), the app reuses it.
    """
    try:
        out = subprocess.run(["ps", "-axo", "comm="], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return
    # No MATLAB open: nothing to worry about
    if not matlab_running(out):
        return
    # An open MATLAB that has shared its session can be reused
    if matlab.engine.find_matlab():
        print("MATLAB: found an open session that is shared; it will be reused")
        return
    # An open MATLAB that cannot be reused: stop, unless the user forces it
    print("MATLAB is already open and is not shared. Two MATLABs plus the model is too much for 8 GB.")
    print("Either close MATLAB, or run   matlab.engine.shareEngine   in it so this app can reuse it.")
    if os.environ.get("FOMC_FORCE") != "1":
        raise SystemExit("Stopping so the machine does not freeze. Set FOMC_FORCE=1 to start anyway.")


def check_memory_at_start() -> None:
    # Check MATLAB first, then memory; print the biggest memory users if memory is short
    check_matlab_at_start()
    verdict, message = memory_verdict(model_loaded=False)
    if verdict == "ok":
        print(f"Memory: {message}")
        return
    print(f"Memory: {message}")
    print("Using the most memory right now:")
    for mb, name in top_apps():
        print(f"  {mb:6d} MB  {name}")
    if verdict == "refuse" and os.environ.get("FOMC_FORCE") != "1":
        raise SystemExit("Stopping so the machine does not freeze. Set FOMC_FORCE=1 to start anyway.")


class Watchdog:
    """Stop the model if memory becomes critical while a question runs.

    Critical pressure (a low free percentage alone is normal with a loaded model) or runaway swap
    stops the Ollama this app started. The call then fails fast, and the next question restarts Ollama.
    """

    def __init__(self):
        # A flag that is set while a question runs, and a background thread that checks memory every 5 seconds
        self._busy = threading.Event()
        threading.Thread(target=self._watch, daemon=True).start()

    def __enter__(self):
        global panic_reason
        panic_reason = None
        self._busy.set()

    def __exit__(self, *exc):
        self._busy.clear()

    def _watch(self):
        global panic_reason
        critical_in_a_row = 0
        # Only watch while a question runs and only if this app started Ollama
        while True:
            time.sleep(5)
            if not self._busy.is_set() or ollama_process is None:
                critical_in_a_row = 0
                continue
            s = memory_status()
            swap = s["swap_used_mb"]
            # Stop Ollama after repeated critical pressure or runaway swap, so the machine stays usable
            critical_in_a_row = critical_in_a_row + 1 if s["pressure"] == 4 else 0
            if critical_in_a_row >= PANIC_SAMPLES or (swap is not None and swap > PANIC_SWAP_MB):
                panic_reason = "memory critical (" + memory_verdict(s)[1] + ")"
                print(f"Watchdog: {panic_reason}; stopping Ollama")
                stop_ollama()
                critical_in_a_row = 0


# --- MODELS ---

def load_models() -> list[dict]:
    """The models the page offers, from models/models.json: id, label, name (the Ollama name).

    Entries with "offered": false are only for the evaluation (tests/bench_live.py); use load_all_models for those.
    """
    return [m for m in load_all_models() if m.get("offered", True)]


def load_all_models() -> list[dict]:
    """Every model in models/models.json, including the evaluation-only ones."""
    return json.loads((MODELS_DIR / "models.json").read_text(encoding="utf-8"))


def model_entry(model_id: str | None) -> dict:
    """The entry for an id (evaluation-only models included); the first model in the list is the default."""
    models = load_all_models()
    return next((m for m in models if m["id"] == model_id), models[0])


def base_model(entry: dict) -> str:
    """The model a Modelfile starts from (its FROM line), which must be downloaded first."""
    text = (MODELS_DIR / entry["id"] / "Modelfile").read_text(encoding="utf-8")
    return re.search(r"^FROM\s+(\S+)", text, re.MULTILINE).group(1)


def ensure_model(entry: dict) -> None:
    """Build the project model from its Modelfile if Ollama does not have it yet."""
    installed = subprocess.run([ollama_bin(), "list"], capture_output=True, text=True).stdout
    if re.search(rf"^{re.escape(entry['name'])}(:latest)?\s", installed, re.MULTILINE):
        return
    base = base_model(entry)
    if base not in installed:
        raise RuntimeError(f"The base model is missing. Download it once with:  ollama pull {base}")
    print(f"Ollama: building {entry['name']} from models/{entry['id']}/Modelfile")
    subprocess.run([ollama_bin(), "create", entry["name"], "-f", str(MODELS_DIR / entry["id"] / "Modelfile")], check=True)


# --- OLLAMA ---

def ollama_up() -> bool:
    try:
        # Ollama answers its version page when it is running
        urllib.request.urlopen(f"{OLLAMA_URL}/api/version", timeout=2)
        return True
    except OSError:
        return False


def ollama_bin() -> str:
    # Find the ollama program
    path = shutil.which("ollama") or "/opt/homebrew/bin/ollama"
    if not Path(path).exists():
        raise SystemExit("Ollama is not installed. Install it with: brew install ollama")
    return path


def ensure_ollama() -> None:
    """Start Ollama if it is not running."""
    global ollama_process
    # Start Ollama if it is not running, with the memory-saving settings above; wait up to 30 seconds
    if ollama_up():
        if ollama_process is None:
            print("Ollama: already running (started by you, so it will be left running)")
    else:
        print("Ollama: starting...")
        LOGS.mkdir(exist_ok=True)
        ollama_process = subprocess.Popen(
            [ollama_bin(), "serve"], env={**os.environ, **OLLAMA_ENV},
            stdout=open(LOGS / "ollama-serve.log", "ab"), stderr=subprocess.STDOUT)
        for _ in range(60):
            if ollama_up():
                break
            time.sleep(0.5)
        else:
            raise SystemExit("Ollama did not start within 30 seconds. See logs/ollama-serve.log.")
        print("Ollama: started (it will be stopped when this app exits)")


def warm_model(model_id: str | None = None) -> None:
    """Load the model ahead of the first question, if memory allows.

    The page calls this when it opens, so the 10 to 15 seconds of loading happen while the user types.
    Ollama frees the model after OLLAMA_KEEP_ALIVE.
    """
    # Do nothing if Ollama is down or memory is not clearly fine
    if not ollama_up() or memory_verdict(model_loaded=False)[0] != "ok":
        return
    # An empty prompt makes Ollama load the model without generating anything
    body = json.dumps({"model": model_entry(model_id)["name"], "prompt": "", "keep_alive": OLLAMA_ENV["OLLAMA_KEEP_ALIVE"]}).encode()
    try:
        urllib.request.urlopen(urllib.request.Request(f"{OLLAMA_URL}/api/generate", body,
                                                      {"Content-Type": "application/json"}), timeout=120)
    except OSError:
        pass


def stop_ollama() -> None:
    """Stop Ollama if this app started it."""
    global ollama_process
    if ollama_process is not None:
        # Ask Ollama to stop; force it if it does not stop within 10 seconds
        ollama_process.terminate()
        try:
            ollama_process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            ollama_process.kill()
        ollama_process = None


# --- MATLAB ---

def start_matlab():
    """Connect to an open MATLAB that has shared its session, else start a hidden one.

    Reusing an open MATLAB saves about 1 GB: run matlab.engine.shareEngine in it once.
    FOMC_MATLAB=new always starts a separate one.
    """
    # Prefer an open MATLAB that has shared its session
    if os.environ.get("FOMC_MATLAB") != "new":
        names = matlab.engine.find_matlab()
        if names:
            print(f"MATLAB: using your open session '{names[0]}'")
            engine = matlab.engine.connect_matlab(names[0])
            engine.addpath(str(HERE / "src"), nargout=0)
            return engine
    # Otherwise start a MATLAB with no window; either way, put src/ on its path
    print("MATLAB: starting a hidden session (about 10 seconds)...")
    engine = matlab.engine.start_matlab("-nodesktop -nosplash")
    engine.addpath(str(HERE / "src"), nargout=0)
    return engine


# --- SHUTDOWN ---

def shutdown(engine) -> None:
    """Stop what this app started, memory-hungry parts first, then any leftover children."""
    stop_ollama()
    if engine is not None:
        # Quit MATLAB, waiting at most 15 seconds
        t = threading.Thread(target=engine.quit, daemon=True)
        t.start()
        t.join(timeout=15)
    # Any direct child still alive (a stuck hidden MATLAB); matching on parent id cannot hit anything else.
    # Finish off any child process still alive
    subprocess.run(["pkill", "-TERM", "-P", str(os.getpid())], capture_output=True)


sys.stdout.reconfigure(line_buffering=True)  # show startup messages straight away
