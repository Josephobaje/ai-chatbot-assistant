import json

import httpx
from fastapi.testclient import TestClient

from app.main import create_app
from app.providers import OfflineProvider, OpenAICompatibleProvider, provider_from_env
from app.retrieval import TfidfRetriever, load_markdown_faq, tokenize

KB = "knowledge"


def test_tokenize_stems_and_drops_stopwords():
    assert tokenize("How long do deliveries take?") == ["long", "delivery", "take"]


def test_retrieval_finds_right_faq():
    r = TfidfRetriever(load_markdown_faq(KB))
    assert len(r.docs) == 10
    assert r.search("how much does delivery cost")[0][0].question == "How much is delivery?"
    assert r.search("can I get a refund and return my item")[0][0].question == "Can I return a product?"
    assert r.search("zzzz qqqq") == []


def test_offline_provider_greeting_and_unknown():
    p = OfflineProvider()
    assert "Hello" in p.reply("hi", [], [])
    assert "support" in p.reply("tell me a joke", [], [])


def test_chat_endpoint_offline_with_history():
    c = TestClient(create_app(provider=OfflineProvider(), knowledge_dir=KB))
    assert c.get("/api/health").json()["documents"] == 10
    r = c.post("/api/chat", json={"message": "What payment methods do you accept?"}).json()
    assert "Paystack" in r["reply"]
    assert r["provider"] == "offline-tfidf"
    sid = r["session_id"]
    c.post("/api/chat", json={"message": "Opening hours?", "session_id": sid})
    msgs = c.get(f"/api/history/{sid}").json()["messages"]
    assert [m["role"] for m in msgs] == ["user", "assistant", "user", "assistant"]
    assert "Monday to Saturday" in msgs[3]["content"]
    c.delete(f"/api/history/{sid}")
    assert c.get(f"/api/history/{sid}").status_code == 404


def test_validation_and_ui():
    c = TestClient(create_app(provider=OfflineProvider(), knowledge_dir=KB))
    assert c.post("/api/chat", json={"message": ""}).status_code == 422
    assert "Support Assistant" in c.get("/").text


def _mock_client(handler):
    return httpx.Client(transport=httpx.MockTransport(handler))


def test_openai_provider_sends_context_and_history():
    seen = {}

    def handler(req: httpx.Request):
        seen["auth"] = req.headers["authorization"]
        seen["body"] = json.loads(req.content)
        return httpx.Response(200, json={"choices": [{"message": {"content": " Delivery is free above ₦50,000. "}}]})

    p = OpenAICompatibleProvider("sk-test", "https://llm.example/v1", "demo-model", client=_mock_client(handler))
    docs = load_markdown_faq(KB)[:1]
    out = p.reply("delivery?", [{"role": "user", "content": "hi"}, {"role": "assistant", "content": "hello"}], docs)
    assert out == "Delivery is free above ₦50,000."
    assert seen["auth"] == "Bearer sk-test"
    msgs = seen["body"]["messages"]
    assert msgs[0]["role"] == "system" and docs[0].question in msgs[0]["content"]
    assert [m["role"] for m in msgs[1:]] == ["user", "assistant", "user"]


def test_openai_provider_falls_back_offline_on_error():
    p = OpenAICompatibleProvider("sk-test", client=_mock_client(lambda r: httpx.Response(429, json={})))
    docs = load_markdown_faq(KB)
    assert p.reply("hours", [], docs[:1]) == docs[0].answer


def test_provider_from_env(monkeypatch):
    monkeypatch.delenv("LLM_API_KEY", raising=False)
    assert provider_from_env().name == "offline-tfidf"
    monkeypatch.setenv("LLM_API_KEY", "sk-test")
    assert provider_from_env().name == "openai-compatible"
