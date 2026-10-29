"""Local web chat for the FOMC minutes agent.

    uv run app.py        then open http://localhost:8787

A thin web shell: it serves the page and passes each message to the MATLAB agent (fomc.web.turn).
No agent logic lives here. server/runtime.py starts and guards Ollama and MATLAB.
"""
import json
import re
import threading
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

import uvicorn
from fastapi import Depends, FastAPI, Request, Response
from fastapi.responses import FileResponse
from pydantic import BaseModel

from server import runtime
from server.chats import ChatStore

# --- CONFIGURATION ---

HERE = Path(__file__).parent
PORT = 8787

# --- STATE ---

engine = None                                # the MATLAB session, started with the app
engine_lock = threading.Lock()               # MATLAB runs one call at a time
watchdog = None
store = ChatStore(runtime.LOGS / "chats")       # saved chats, one file each
EFFORTS = ("low", "medium", "high")
OWNER_COOKIE = "fomc_owner"                  # a random id per browser; its chats are only visible to it


# --- MATLAB ---

def matlab_call(name: str, *args, nargout: int = 1):
    """Call a MATLAB function (one that returns text unless nargout=0), one call at a time."""
    with engine_lock:
        return engine.feval(name, *args, nargout=nargout)


def clean_session_id(session_id: str | None) -> str:
    """Session ids become file names, so only accept a plain id."""
    if session_id and re.fullmatch(r"[0-9a-f-]{8,40}", session_id):
        return session_id
    return uuid.uuid4().hex


def owner_of(request: Request, response: Response) -> str:
    """This browser's owner id from its cookie; a browser without one gets a new one."""
    owner = request.cookies.get(OWNER_COOKIE, "")
    if not re.fullmatch(r"[0-9a-f]{32}", owner):
        owner = uuid.uuid4().hex
        set_owner_cookie(response, owner)
    return owner


def set_owner_cookie(response: Response, owner: str) -> None:
    response.set_cookie(OWNER_COOKIE, owner, max_age=3600 * 24 * 365, httponly=True, samesite="lax")


# --- APP ---

@asynccontextmanager
async def lifespan(app: FastAPI):
    global engine, watchdog
    # Startup, in order: check memory, make sure Ollama is running, start MATLAB, start the memory watchdog
    runtime.check_memory_at_start()
    # Make sure Ollama is up (the watchdog may have stopped it), then run the question in MATLAB while the watchdog watches memory
    runtime.ensure_ollama()
    try:
        runtime.ensure_model(runtime.model_entry(None))
    except RuntimeError as e:
        raise SystemExit(str(e))
    engine = runtime.start_matlab()
    watchdog = runtime.Watchdog()
    # Ask MATLAB for a few facts to confirm it works, then hand control to the server
    info = json.loads(matlab_call("fomc.web.info"))
    print(f"MATLAB: ready. {info['meetings']} meetings, default anchor {info['latestAnchor']}")
    print(f"\nOpen http://localhost:{PORT}\n")
    # The server runs here; the lines after it run when the server stops
    yield
    runtime.shutdown(engine)


app = FastAPI(lifespan=lifespan)


class ChatRequest(BaseModel):
    message: str
    session_id: str | None = None
    as_of: str = ""                          # YYYY-MM-DD; only used when a session starts
    effort: str = "low"                      # "low", "medium" or "high"
    model: str = ""                          # a model id from models/models.json; "" is the default


@app.get("/")
def index(request: Request):
    # Give a new browser its owner id now, so the page's first requests all use the same one
    response = FileResponse(HERE / "static" / "index.html")
    response.headers["Cache-Control"] = "no-cache"    # recheck the page after an update; Safari kept an old copy
    if not re.fullmatch(r"[0-9a-f]{32}", request.cookies.get(OWNER_COOKIE, "")):
        set_owner_cookie(response, uuid.uuid4().hex)
    return response


@app.get("/info")
def info(model: str = ""):
    if not engine_lock.locked():             # not while a question is running
        threading.Thread(target=runtime.warm_model, args=(model,), daemon=True).start()
    data = json.loads(matlab_call("fomc.web.info"))
    data["models"] = [{"id": m["id"], "label": m["label"]} for m in runtime.load_models()]
    return data


@app.get("/evaluation")
def evaluation_page():
    return FileResponse(HERE / "static" / "evals.html", headers={"Cache-Control": "no-cache"})


@app.get("/evals")
def evals():
    """Every model's saved evaluation (evals/<modelId>.json from tests/bench_live.py), smallest model first."""
    runs = []
    for path in sorted((HERE / "evals").glob("*.json")):
        if path.name != "key.json":
            runs.append(json.loads(path.read_text(encoding="utf-8")))
    runs.sort(key=lambda r: r["summary"].get("params_b") or 0)
    return runs


@app.get("/evals/key")
def evals_key():
    """The 50 questions, so the Evaluation page can show each question's text."""
    return json.loads((HERE / "evals" / "key.json").read_text(encoding="utf-8"))


@app.post("/chat")
def chat(request: ChatRequest, owner: str = Depends(owner_of)):
    session_id = clean_session_id(request.session_id)
    effort = request.effort if request.effort in EFFORTS else "low"
    entry = runtime.model_entry(request.model)
    failed = {"session_id": session_id, "structured": None, "citations": [], "warning": "",
              "tool_calls": [], "seconds": 0, "anchor": request.as_of}
    if store.owned_by_other(session_id, owner):         # never touch another browser's chat
        return {**failed, "answer": "That chat belongs to another browser. Start a new chat."}
    verdict, message = runtime.memory_verdict(model_loaded=True)
    if verdict == "refuse":
        return {**failed, "answer": message}
    runtime.LOGS.mkdir(exist_ok=True)
    trace = str(runtime.LOGS / f"web-{session_id}.jsonl")
    try:
        runtime.ensure_ollama()              # restarts the model server if the watchdog had to stop it
        runtime.ensure_model(entry)          # builds the chosen model the first time it is used
        with watchdog:
            result = json.loads(matlab_call("fomc.web.turn", session_id, request.message, request.as_of,
                                            effort, entry["name"], trace, store.seed(session_id, owner)))
    except Exception as e:                   # MATLAB errors come back as a message, not a crash
        reason = f" ({runtime.panic_reason})" if runtime.panic_reason else ""
        return {**failed, "answer": f"Agent error{reason}: {str(e)[:300]}"}
    reply = {"answer": result["answer"], "structured": result["structured"], "citations": result["citations"],
             "warning": result["warning"], "tool_calls": result["toolCalls"], "seconds": result["seconds"],
             "anchor": result["anchorDate"]}
    store.append(session_id, owner, {"as_of": result["anchorDate"], "model": entry["id"], "effort": effort},
                 request.message, reply)
    return {"session_id": session_id, **reply, "memory": message}


@app.get("/chats")
def list_chats(owner: str = Depends(owner_of)):
    store.claim_unowned(owner)               # chats saved before owners existed go to the first browser
    return store.list(owner)


@app.get("/chats/{chat_id}")
def get_chat(chat_id: str, owner: str = Depends(owner_of)):
    return store.get(clean_session_id(chat_id), owner) or {}


@app.post("/chats/{chat_id}/rename")
def rename_chat(chat_id: str, title: str, owner: str = Depends(owner_of)):
    return {"ok": store.rename(clean_session_id(chat_id), owner, title)}


@app.delete("/chats/{chat_id}")
def delete_chat(chat_id: str, owner: str = Depends(owner_of)):
    chat_id = clean_session_id(chat_id)
    deleted = store.delete(chat_id, owner)
    if deleted and engine is not None:
        matlab_call("fomc.web.clear", chat_id, nargout=0)   # also forget the agent's memory of it
    return {"status": "ok" if deleted else "not found"}


@app.get("/progress")
def progress(session_id: str, after: int = 0, owner: str = Depends(owner_of)):
    """New trace events since line `after`, so the page can show tool calls while the model works."""
    if store.owned_by_other(clean_session_id(session_id), owner):
        return {"events": [], "next": 0}
    # Read the session's trace file and return the lines added since the page last asked
    path = runtime.LOGS / f"web-{clean_session_id(session_id)}.jsonl"
    events = []
    if path.exists():
        lines = path.read_text(encoding="utf-8").splitlines()
        for line in lines[after:]:
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue
            events.append({k: e.get(k) for k in ("type", "kind", "series", "name", "args", "ok", "ms", "round",
                                                 "nToolCalls", "attempt", "stats")})
        after = len(lines)
    return {"events": events, "next": after}


if __name__ == "__main__":
    # 127.0.0.1 = this machine only; 8787 = the port for this app
    # Run only when started directly. 127.0.0.1 means this machine only; 8787 is the port
    uvicorn.run(app, host="127.0.0.1", port=PORT)
