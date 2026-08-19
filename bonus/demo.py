"""demo.py — five queries that exercise the three memory sources.

    python bonus/demo.py        # prints assembled context per query, exits 0

Each query is chosen (per BONUS-CHALLENGE.md) to lean on a different source:
episodic vector hit, stable profile, live streaming activity, semantic
paraphrase, or a mix. No LLM is called — recall() returns the context string
an LLM WOULD be prompted with.
"""
from __future__ import annotations

import sys
from pathlib import Path

# The demo output is Vietnamese; the Windows console defaults to a legacy code
# page (cp1258) that cannot encode it. Force UTF-8 so `python bonus/demo.py`
# works on Windows, macOS and Linux alike.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# Path bootstrap — same idea as notebooks/_setup.py: resolve the repo root from
# __file__ so `import bonus.agent` works no matter where python is launched.
_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from bonus.agent import HybridMemoryAgent  # noqa: E402

USER = "u_001"

# Seed episodic memories (Vietnamese, code-switched with EN technical terms —
# exactly the VN-context the assistant must handle). u_001's Feast profile has
# topic_affinity=cloud, so cloud/security memories should surface for "recommend".
MEMORIES = [
    "Kubernetes dùng Horizontal Pod Autoscaler (HPA) để tự động mở rộng số pod "
    "dựa trên CPU và custom metrics.",
    "OAuth2 và JWT là chuẩn phổ biến để xác thực và uỷ quyền giữa các microservice.",
    "Cloud security cần bật mã hoá at-rest, IAM least-privilege và VPC network "
    "policy để giảm bề mặt tấn công.",
    "Chỉ mục B-tree tăng tốc truy vấn range trong cơ sở dữ liệu quan hệ nhưng làm chậm ghi.",
    "Reciprocal Rank Fusion (RRF) hợp nhất BM25 và vector search bằng công thức 1/(k+rank).",
    "Serverless như AWS Lambda hợp với workload bursty; tránh tác vụ chạy dài vì cold start.",
    "Terraform quản lý hạ tầng dưới dạng mã, cho phép mở rộng cụm và rollback qua state.",
    "TLS 1.3 giảm số vòng bắt tay và mã hoá dữ liệu trên đường truyền client–server.",
]

# (query, what it is meant to exercise)
QUERIES = [
    ("Tôi đã đọc gì về Kubernetes?", "vector hit đơn giản"),
    ("Recommend đọc gì tiếp", "cần topic_affinity từ profile"),
    ("Tôi đang quan tâm gì gần đây?", "cần queries_last_hour (streaming)"),
    ("Tài liệu về tự động mở rộng hạ tầng?", "paraphrase — vector/hybrid thắng"),
    ("Cho tôi summary cloud security", "mixed — episodic + profile"),
]


def main() -> int:
    agent = HybridMemoryAgent()
    for m in MEMORIES:
        agent.remember(m, user_id=USER)
    print(f"Seeded {len(MEMORIES)} memories cho {USER}.\n" + "=" * 72)

    for i, (query, purpose) in enumerate(QUERIES, 1):
        print(f"\n### Query {i} — {purpose}")
        print(agent.recall(query, user_id=USER))
    print("\n" + "=" * 72 + "\nDone.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
