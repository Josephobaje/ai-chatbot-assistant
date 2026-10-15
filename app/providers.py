"""LLM providers. Any OpenAI-compatible API works (OpenAI, Groq, OpenRouter, Ollama, LM Studio)."""
from __future__ import annotations

import os
from typing import Protocol

import httpx

from .retrieval import Doc

SYSTEM_PROMPT = (
    "You are a friendly customer support assistant for a Nigerian business. Answer ONLY using the context. "
    "If the answer is not in the context, say you are not sure and suggest contacting support. Keep answers short."
)


class Provider(Protocol):
    name: str

    def reply(self, message: str, history: list[dict], context: list[Doc]) -> str: ...


class OfflineProvider:
    """No API key needed: answers with the best-matching FAQ entry."""

    name = "offline-tfidf"

    def reply(self, message: str, history: list[dict], context: list[Doc]) -> str:
        low = message.lower().strip(" !.?")
        if low in {"hi", "hello", "hey", "good morning", "good afternoon", "good evening"}:
            return "Hello! 👋 I can help with opening hours, delivery, payments, returns and order tracking. What do you need?"
        if not context:
            return ("I'm not sure about that yet. Please contact support at support@example.com "
                    "or WhatsApp 0800 000 0000 and a human will help you.")
        return context[0].answer


class OpenAICompatibleProvider:
    name = "openai-compatible"

    def __init__(self, api_key: str, base_url: str = "https://api.openai.com/v1", model: str = "gpt-4o-mini",
                 client: httpx.Client | None = None, fallback: Provider | None = None):
        self.api_key, self.base_url, self.model = api_key, base_url.rstrip("/"), model
        self.client = client or httpx.Client(timeout=30)
        self.fallback = fallback or OfflineProvider()

    def reply(self, message: str, history: list[dict], context: list[Doc]) -> str:
        ctx = "\n".join(f"Q: {d.question}\nA: {d.answer}" for d in context) or "(no matching entries)"
        messages = [{"role": "system", "content": f"{SYSTEM_PROMPT}\n\nContext:\n{ctx}"}]
        messages += [{"role": m["role"], "content": m["content"]} for m in history[-10:]]
        messages.append({"role": "user", "content": message})
        try:
            r = self.client.post(f"{self.base_url}/chat/completions",
                                 headers={"Authorization": f"Bearer {self.api_key}"},
                                 json={"model": self.model, "messages": messages, "temperature": 0.2})
            r.raise_for_status()
            return r.json()["choices"][0]["message"]["content"].strip()
        except (httpx.HTTPError, KeyError, IndexError, ValueError):
            # Network or quota problem: degrade gracefully instead of failing the chat.
            return self.fallback.reply(message, history, context)


def provider_from_env() -> Provider:
    key = os.getenv("LLM_API_KEY", "").strip()
    if not key:
        return OfflineProvider()
    return OpenAICompatibleProvider(key, os.getenv("LLM_BASE_URL", "https://api.openai.com/v1"),
                                    os.getenv("LLM_MODEL", "gpt-4o-mini"))
