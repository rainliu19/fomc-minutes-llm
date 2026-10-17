"""Saved chats: one JSON file per chat, so the page can list, reopen, rename and delete them.

Plain files in logs/chats/ (not in git). No MATLAB or model needed, so it is easy to test.
Each chat belongs to one browser (its "owner" id, kept in a cookie): every operation takes the
owner and only touches that owner's chats. This keeps people sharing one running copy from seeing
each other's chats. It is not a login, so it is not protection against someone on the same browser.
"""
import json
import time
from pathlib import Path

KEEP_PAIRS = 4                                # earlier questions replayed when a chat is continued


class ChatStore:
    def __init__(self, folder: Path):
        self.folder = folder

    def _path(self, chat_id: str) -> Path:
        return self.folder / f"{chat_id}.json"

    def _read(self, chat_id: str) -> dict | None:
        try:
            return json.loads(self._path(chat_id).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None

    def get(self, chat_id: str, owner: str) -> dict | None:
        """The whole chat, or None if it does not exist, cannot be read, or belongs to someone else."""
        chat = self._read(chat_id)
        return chat if chat and chat.get("owner") == owner else None

    def owned_by_other(self, chat_id: str, owner: str) -> bool:
        """True if a chat with this id exists and belongs to another owner."""
        chat = self._read(chat_id)
        return bool(chat) and chat.get("owner") != owner

    def claim_unowned(self, owner: str) -> None:
        """Give chats saved before owners existed to this owner (the first browser to ask)."""
        for path in self.folder.glob("*.json") if self.folder.exists() else []:
            chat = self._read(path.stem)
            if chat and "owner" not in chat:
                chat["owner"] = owner
                self._save(chat)

    def _save(self, chat: dict) -> None:
        # Write to a temporary file first, so a crash never leaves a half-written chat
        self.folder.mkdir(parents=True, exist_ok=True)
        tmp = self._path(chat["id"]).with_suffix(".tmp")
        tmp.write_text(json.dumps(chat), encoding="utf-8")
        tmp.replace(self._path(chat["id"]))

    def list(self, owner: str) -> list[dict]:
        """Id, title and last-updated time of this owner's chats, newest first."""
        rows = []
        for path in self.folder.glob("*.json") if self.folder.exists() else []:
            chat = self.get(path.stem, owner)
            if chat:
                rows.append({"id": chat["id"], "title": chat["title"], "updated": chat["updated"]})
        return sorted(rows, key=lambda r: r["updated"], reverse=True)

    def append(self, chat_id: str, owner: str, settings: dict, question: str, reply: dict) -> None:
        """Add a question and the answer to the owner's chat, creating it (titled from the question) if new."""
        if self.owned_by_other(chat_id, owner):
            raise PermissionError("That chat belongs to another browser.")
        chat = self.get(chat_id, owner) or {"id": chat_id, "owner": owner, "title": question.strip()[:60] or "New chat",
                                            "created": time.time(), "messages": []}
        chat.update(settings)                 # anchor date, model and effort of the latest message
        chat["messages"] += [{"role": "user", "text": question}, {"role": "assistant", **reply}]
        chat["updated"] = time.time()
        self._save(chat)

    def rename(self, chat_id: str, owner: str, title: str) -> bool:
        chat = self.get(chat_id, owner)
        title = " ".join(title.split())[:80]
        if not chat or not title:
            return False
        chat["title"] = title
        self._save(chat)
        return True

    def delete(self, chat_id: str, owner: str) -> bool:
        """Delete the owner's chat; False (and nothing deleted) if it is not theirs or does not exist."""
        if not self.get(chat_id, owner):
            return False
        self._path(chat_id).unlink(missing_ok=True)
        return True

    def seed(self, chat_id: str, owner: str) -> str:
        """The last few questions and answers as JSON for fomc.web.turn, or "" for a new chat."""
        chat = self.get(chat_id, owner)
        if not chat:
            return ""
        msgs = chat["messages"]
        pairs = []
        for i in range(0, len(msgs) - 1, 2):
            ids = [c["id"] for c in msgs[i + 1].get("citations", []) if c.get("ok")]
            pairs.append({"q": msgs[i]["text"], "a": msgs[i + 1]["answer"], "ids": ids})
        return json.dumps(pairs[-KEEP_PAIRS:]) if pairs else ""
