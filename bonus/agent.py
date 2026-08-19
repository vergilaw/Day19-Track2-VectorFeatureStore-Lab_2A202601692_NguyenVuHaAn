"""HybridMemoryAgent — the bonus challenge POC (see ../BONUS-CHALLENGE.md).

A minimal personal-assistant memory layer that fuses the two halves of Day 19:

    episodic memory   -> Qdrant vector store, filtered per user_id   (NB1/NB5)
    stable profile    -> Feast online store                          (NB4)
    recent activity   -> in-agent streaming buffer (sub-second push)

`recall()` assembles a context string from all three; it deliberately does NOT
call a real LLM — the lesson is retrieval + feature assembly, and the lab must
run with no API key. Everything here REUSES lab modules rather than re-deriving:
`Embedder` (app.embeddings), the RRF formula (app.search), the payload-filtered
ANN pattern (app.filters), and the Feast graceful-degrade pattern (app.agent).
"""
from __future__ import annotations

import re
import time
import warnings
from pathlib import Path

import numpy as np
from qdrant_client import QdrantClient, models
from rank_bm25 import BM25Okapi

from app.embeddings import Embedder

_REPO_ROOT = Path(__file__).resolve().parent.parent
COLLECTION = "bonus_memories"

# Which slow-moving profile features to pull from Feast. Names match the schema
# defined in app/feast_repo/feature_views.py (user_profile_features).
PROFILE_FEATURES = [
    "user_profile_features:topic_affinity",
    "user_profile_features:preferred_language",
    "user_profile_features:reading_speed_wpm",
]


class HybridMemoryAgent:
    """remember() adds episodic memory; recall() assembles per-user context."""

    def __init__(self, feast_repo: str | Path | None = None) -> None:
        # Reuse the lab embedder (fastembed / bge-small / 384d by default) so
        # memories live in the SAME vector space the rest of the lab uses.
        self.embedder = Embedder()

        # A dedicated in-memory collection just for user memories — kept apart
        # from the 1000-doc corpus so episodic recall never leaks corpus docs.
        self.client = QdrantClient(":memory:")
        self.client.create_collection(
            collection_name=COLLECTION,
            vectors_config=models.VectorParams(
                size=self.embedder.dim, distance=models.Distance.COSINE
            ),
        )
        # A KEYWORD index on user_id is what lets a real Qdrant server filter
        # INSIDE the ANN walk (filtered-ANN, NB5) — this is the privacy boundary
        # between users. Local in-memory Qdrant ignores it but warns; silence it.
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            self.client.create_payload_index(
                COLLECTION, "user_id", field_schema=models.PayloadSchemaType.KEYWORD
            )

        # Feast online store for the stable profile. Wrapped so the POC still
        # runs (profile = "unknown") if a student never ran `feast apply` — same
        # graceful-degrade contract as app/agent.py::build_context.
        repo = Path(feast_repo) if feast_repo else _REPO_ROOT / "app" / "feast_repo"
        try:
            from feast import FeatureStore
            self.fs = FeatureStore(repo_path=str(repo))
        except Exception:                                   # noqa: BLE001
            self.fs = None

        self._next_id = 0
        # Per-user memory texts, kept so BM25 can be rebuilt over just this
        # user's memories at recall time (small corpus — clarity over speed).
        self._mem: dict[str, list[tuple[int, str]]] = {}
        # Streaming feature view, in-process: timestamps of recent queries per
        # user. This is the "sub-second push" freshness tier (see ARCHITECTURE).
        self._activity: dict[str, list[float]] = {}

    # ── write path ──────────────────────────────────────────────────────
    def remember(self, text: str, user_id: str = "u_001") -> None:
        """Chunk -> embed -> upsert one piece of episodic memory for a user."""
        chunks = _chunk(text)
        vectors = list(self.embedder.embed(chunks))
        points = []
        for chunk, vec in zip(chunks, vectors):
            points.append(models.PointStruct(
                id=self._next_id,
                vector=vec.tolist(),
                payload={"user_id": user_id, "text": chunk, "ts": time.time()},
            ))
            self._mem.setdefault(user_id, []).append((self._next_id, chunk))
            self._next_id += 1
        self.client.upsert(collection_name=COLLECTION, points=points)

    # ── read path ───────────────────────────────────────────────────────
    def recall(self, query: str, user_id: str = "u_001", top_k: int = 3) -> str:
        """Assemble context: stable profile + recent activity + top memories."""
        # Streaming push: log this query, then read the fresh 1h count back.
        self._activity.setdefault(user_id, []).append(time.time())
        profile = self._profile(user_id)
        queries_last_hour = self._queries_last_hour(user_id)
        memories = self._hybrid_recall(query, user_id, top_k)

        lines = [
            f'[Context for {user_id}]  query="{query}"',
            f"─ Profile (Feast, batch / 30d TTL): "
            f"language={profile['preferred_language']}, "
            f"reading_speed={profile['reading_speed_wpm']}wpm, "
            f"topic_affinity={profile['topic_affinity']}",
            f"─ Recent activity (streaming, live): "
            f"{queries_last_hour} query trong 1h qua",
            "─ Top memories (hybrid BM25⊕vector RRF, filtered by user_id):",
        ]
        if memories:
            lines += [f"   {i}. {t}" for i, t in enumerate(memories, 1)]
        else:
            lines.append("   (chưa có memory nào cho user này)")
        return "\n".join(lines)

    # ── stable profile (Feast) ──────────────────────────────────────────
    def _profile(self, user_id: str) -> dict:
        out = {"topic_affinity": "unknown", "preferred_language": "unknown",
               "reading_speed_wpm": "unknown"}
        if self.fs is None:
            return out
        try:
            feats = self.fs.get_online_features(
                features=PROFILE_FEATURES,
                entity_rows=[{"user_id": user_id}],
            ).to_dict()
            for key in out:
                val = (feats.get(key) or [None])[0]
                if val is not None:              # None => TTL expired / no row
                    out[key] = val
        except Exception:                                   # noqa: BLE001
            pass                                            # keep the "unknown" defaults
        return out

    # ── recent activity (streaming buffer) ──────────────────────────────
    def _queries_last_hour(self, user_id: str) -> int:
        now = time.time()
        return sum(1 for t in self._activity.get(user_id, []) if now - t <= 3600)

    # ── episodic recall (hybrid, per-user) ──────────────────────────────
    def _hybrid_recall(self, query: str, user_id: str, top_k: int) -> list[str]:
        mem = self._mem.get(user_id, [])
        if not mem:
            return []

        # Vector ranking: filtered-ANN so a user only ever sees their own rows.
        qv = np.asarray(next(self.embedder.embed([query])), dtype=np.float32)
        user_filter = models.Filter(must=[models.FieldCondition(
            key="user_id", match=models.MatchValue(value=user_id))])
        hits = self.client.query_points(
            collection_name=COLLECTION, query=qv.tolist(),
            query_filter=user_filter, limit=len(mem),
        ).points
        vec_rank = [h.id for h in hits]

        # Keyword ranking: BM25 over just this user's memory texts.
        ids = [i for i, _ in mem]
        texts = {i: t for i, t in mem}
        bm25 = BM25Okapi([_tokenize(t) for t in texts.values()])
        scores = bm25.get_scores(_tokenize(query))
        kw_rank = [ids[j] for j in sorted(range(len(ids)), key=lambda j: -scores[j])]

        fused = _rrf([kw_rank, vec_rank])[:top_k]
        return [texts[i] for i in fused]


# ── module-level helpers (shared with the lab's own patterns) ───────────
_SENT_RE = re.compile(r"(?<=[.!?。])\s+|\n+")


def _chunk(text: str, min_len: int = 30) -> list[str]:
    """Per-sentence chunks, merging fragments shorter than `min_len` chars.

    A pragmatic middle ground between per-message (too granular) and
    per-conversation (too coarse) — the tradeoff discussed in ARCHITECTURE.md.
    """
    parts = [p.strip() for p in _SENT_RE.split(text.strip()) if p.strip()]
    chunks: list[str] = []
    for p in parts:
        if chunks and len(chunks[-1]) < min_len:
            chunks[-1] = f"{chunks[-1]} {p}"
        else:
            chunks.append(p)
    return chunks or [text.strip()]


def _tokenize(text: str) -> list[str]:
    # Whitespace split — same baseline as app/search.py::_tokenize. A real VN
    # system would use pyvi/underthesea (see ARCHITECTURE.md, VN-context).
    return text.lower().split()


def _rrf(rankings: list[list[int]], k: int = 60) -> list[int]:
    """Reciprocal Rank Fusion, 1/(k+rank) — identical to app/search.py."""
    scores: dict[int, float] = {}
    for ranking in rankings:
        for rank, doc_id in enumerate(ranking, start=1):
            scores[doc_id] = scores.get(doc_id, 0.0) + 1.0 / (k + rank)
    return sorted(scores, key=lambda d: -scores[d])
