"""FastAPI app: /api/chat with session history, served alongside a small web chat UI."""
from __future__ import annotations

import os
import uuid
from collections import defaultdict
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .providers import Provider, provider_from_env
from .retrieval import TfidfRetriever, load_markdown_faq

BASE = Path(__file__).resolve().parent.parent
MAX_HISTORY = 50


class ChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    session_id: str | None = None


class Source(BaseModel):
    question: str
    score: float


class ChatOut(BaseModel):
    session_id: str
    reply: str
    provider: str
    sources: list[Source]


def create_app(provider: Provider | None = None, knowledge_dir: str | Path | None = None) -> FastAPI:
    app = FastAPI(title="AI Chatbot Assistant", version="1.0.0")
    kdir = Path(knowledge_dir or os.getenv("KNOWLEDGE_DIR", BASE / "knowledge"))
    retriever = TfidfRetriever(load_markdown_faq(kdir))
    llm = provider or provider_from_env()
    sessions: dict[str, list[dict]] = defaultdict(list)

    @app.get("/api/health")
    def health():
        return {"ok": True, "provider": llm.name, "documents": len(retriever.docs)}

    @app.post("/api/chat", response_model=ChatOut)
    def chat(body: ChatIn):
        sid = body.session_id or uuid.uuid4().hex
        history = sessions[sid]
        hits = retriever.search(body.message, k=3)
        reply = llm.reply(body.message, history, [d for d, _ in hits])
        history += [{"role": "user", "content": body.message}, {"role": "assistant", "content": reply}]
        del history[:-MAX_HISTORY]
        return ChatOut(session_id=sid, reply=reply, provider=llm.name,
                       sources=[Source(question=d.question, score=round(s, 3)) for d, s in hits])

    @app.get("/api/history/{sid}")
    def get_history(sid: str):
        if sid not in sessions:
            raise HTTPException(404, "Unknown session")
        return {"session_id": sid, "messages": sessions[sid]}

    @app.delete("/api/history/{sid}")
    def clear_history(sid: str):
        sessions.pop(sid, None)
        return {"cleared": True}

    @app.get("/")
    def index():
        return FileResponse(BASE / "app" / "static" / "index.html")

    app.mount("/static", StaticFiles(directory=BASE / "app" / "static"), name="static")
    return app


app = create_app()
