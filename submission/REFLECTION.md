# Reflection — Lab 19

**Tên:** Nguyễn Vũ Hà An
**Cohort:** AICB-P2T2 (Day 19)
**Path đã chạy:** lite (fastembed + Qdrant in-memory + SQLite Feast)

---

## Câu hỏi (≤ 200 chữ)

> Trên golden set 50 queries, mode nào thắng ở loại query nào (`exact` /
> `paraphrase` / `mixed`), và tại sao? Khi nào bạn **không** dùng hybrid
> (i.e. khi nào pure BM25 hoặc pure vector là lựa chọn đúng)?

- **Exact queries:** BM25 thắng hoặc tương đương (96.7%) vì các từ khóa chuyên môn ("Kubernetes", "OAuth", "B-tree") được khớp từ điển chính xác mà không bị nhiễu ngữ nghĩa.
- **Paraphrase queries:** cả 3 mode đều yếu (kw 33.3% / sem 24.0% / hyb 32.0%) — bất ngờ là semantic **không** thắng mà còn thấp nhất, do corpus tiếng Việt nhưng model embedding `bge-small-en-v1.5` là tiếng Anh nên vector paraphrase kém; BM25 khớp phần từ khóa còn sót lại vẫn nhỉnh hơn.
- **Mixed queries & Toàn cục:** Hybrid RRF (k=60) đạt kết quả cao nhất (100% trên mixed, 78.6% tổng thể) nhờ bù trừ hoàn hảo điểm yếu của từng phương pháp.
- **Khi nào KHÔNG dùng hybrid:**
  1. Khi cần độ trễ cực thấp (P99 < 5ms): BM25 chỉ mất ~2ms trong khi Hybrid mất ~80–150ms (chi phí embedding model).
  2. Tra cứu mã định danh/mã lỗi cụ thể (ID, UUID, SKU).
  3. Hệ thống giới hạn tài nguyên CPU/Memory không thể load model embedding.

---

## Điều ngạc nhiên nhất khi làm lab này

Thuật toán RRF (Reciprocal Rank Fusion) có công thức cực kỳ đơn giản `1/(k+rank)` nhưng lại vượt trội so với chuẩn hóa điểm số (score normalization) vốn rất dễ bị lệch phân phối giữa BM25 và Cosine.

---

## Bonus challenge

- [ ] Đã làm bonus (xem `bonus/`)
- [ ] Pair work với:
