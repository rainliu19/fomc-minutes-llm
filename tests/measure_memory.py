"""Measure how much memory each model takes when loaded, and save it into the evaluations.

    python tests/measure_memory.py              # needs Ollama running and no other model in use

For each model in models/models.json: load it with a one-word prompt, read the size Ollama reports for
the loaded model (/api/ps: weights plus the context window set in its Modelfile), then unload it. The
size goes into evals/<id>.json and evals/<id>-baseline.json as model_memory_mb, which the Evaluation page
and the CSV show. The hidden MATLAB the app also runs adds about 1 GB on top. Run it alone: another model
loaded at the same time would be counted too.
"""
import json
import time
import urllib.request
from pathlib import Path

REPO = Path(__file__).parent.parent
OLLAMA = "http://127.0.0.1:11434"
RAM_MB = 8192                                   # the laptop this is measured for


def call(path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(OLLAMA + path, data, {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=300))


def loaded_size_mb(name):
    """Load a model, return the size Ollama reports for it, then unload it."""
    call("/api/generate", {"model": name, "prompt": "Hi", "stream": False, "options": {"num_predict": 1}, "keep_alive": "5m"})
    time.sleep(1)
    size = next((m["size"] for m in call("/api/ps")["models"] if m["name"].split(":")[0] == name.split(":")[0]), None)
    call("/api/generate", {"model": name, "keep_alive": 0})              # unload before the next one
    time.sleep(3)
    return round(size / 1024 / 1024) if size else None


def main():
    for m in json.loads((REPO / "models" / "models.json").read_text()):
        mb = loaded_size_mb(m["name"])
        print(f"{m['id']:10s} {m['label']:32s} {mb} MB = {100 * mb / RAM_MB:.0f}% of {RAM_MB // 1024} GB")
        for suffix in ("", "-baseline"):                                 # the full app and the bare-model row use the same model
            path = REPO / "evals" / f"{m['id']}{suffix}.json"
            if path.exists():
                d = json.loads(path.read_text())
                d["summary"]["model_memory_mb"] = mb
                d["summary"]["model_memory_pct_of_8gb"] = round(100 * mb / RAM_MB, 1)
                path.write_text(json.dumps(d, indent=1))


main()
