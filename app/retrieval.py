"""Tiny dependency-free TF-IDF retriever over a markdown FAQ knowledge base."""
from __future__ import annotations

import math
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

STOPWORDS = set(
    "a an and are as at be by can do does for from how i in is it me my of on or our please the to we what when where "
    "which who why will with you your yours".split()
)


def tokenize(text: str) -> list[str]:
    words = re.findall(r"[a-z0-9₦]+", text.lower())
    out = []
    for w in words:
        if w in STOPWORDS:
            continue
        # light stemming so "deliveries" matches "delivery", "returns" matches "return"
        for suf in ("ies", "es", "s", "ing", "ed"):
            if len(w) > 4 and w.endswith(suf):
                w = w[: -len(suf)] + ("y" if suf == "ies" else "")
                break
        out.append(w)
    return out


@dataclass
class Doc:
    question: str
    answer: str
    source: str


def load_markdown_faq(directory: str | Path) -> list[Doc]:
    docs: list[Doc] = []
    for path in sorted(Path(directory).glob("*.md")):
        blocks = re.split(r"^##\s+", path.read_text(encoding="utf-8"), flags=re.M)
        for block in blocks:
            lines = block.strip().splitlines()
            if len(lines) < 2:
                continue
            docs.append(Doc(lines[0].strip(), " ".join(l.strip() for l in lines[1:] if l.strip()), path.name))
    return docs


class TfidfRetriever:
    def __init__(self, docs: list[Doc]):
        self.docs = docs
        tokenized = [tokenize(d.question + " " + d.question + " " + d.answer) for d in docs]
        n = len(docs)
        df = Counter(t for toks in tokenized for t in set(toks))
        self.idf = {t: math.log((1 + n) / (1 + c)) + 1 for t, c in df.items()}
        self.vectors = [self._vec(toks) for toks in tokenized]

    def _vec(self, toks: list[str]) -> dict[str, float]:
        tf = Counter(toks)
        v = {t: c * self.idf.get(t, 0.0) for t, c in tf.items()}
        norm = math.sqrt(sum(x * x for x in v.values())) or 1.0
        return {t: x / norm for t, x in v.items()}

    def search(self, query: str, k: int = 3) -> list[tuple[Doc, float]]:
        q = self._vec(tokenize(query))
        scored = [(d, sum(w * v.get(t, 0.0) for t, w in q.items())) for d, v in zip(self.docs, self.vectors)]
        scored.sort(key=lambda x: x[1], reverse=True)
        return [s for s in scored[:k] if s[1] > 0]
