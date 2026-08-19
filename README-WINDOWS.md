# Hướng dẫn chạy Lab trên Windows (PowerShell)

Tài liệu này hướng dẫn chi tiết cách chạy Day 19 Lab trên hệ điều hành **Windows** bằng **PowerShell**.

---

## 1. Yêu cầu hệ thống trên Windows

- **Python 3.10 – 3.14** (Khuyến nghị: Python 3.11 hoặc 3.12, nhớ tích chọn **"Add Python to PATH"** khi cài đặt).
- **Git for Windows** (đã cài đặt).
- **Docker Desktop** *(chỉ cần nếu bạn chọn Path Docker Full Stack; với Path Lite thì KHÔNG cần Docker)*.

---

## 2. Lựa chọn đường dẫn cài đặt (Path)

| Path | Mô tả | Lệnh cài đặt nhanh (PowerShell) |
|---|---|---|
| **Lite (Mặc định - Khuyên dùng)** | Chạy in-process với fastembed + Qdrant in-memory + SQLite Feast + FastAPI. Không cần Docker. | `.\setup-lite.ps1` |
| **Docker (Full Stack)** | Qdrant Server + Redis + PostgreSQL + embedding bge-m3. | `.\setup-docker.ps1` |

---

## 3. Các bước thực hiện nhanh (Quick Start)

1. Mở cửa sổ **PowerShell** tại thư mục dự án:
   ```powershell
   # Nếu PowerShell báo lỗi Execution Policy, chạy lệnh này trước trong session:
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

   # Chạy script cài đặt tự động (tạo venv, cài packages, sinh dữ liệu corpus, test khói)
   .\setup-lite.ps1
   ```

2. Sử dụng công cụ điều khiển `.\run.ps1`:
   ```powershell
   # Khởi động FastAPI server trên port 8000
   .\run.ps1 api

   # Mở Jupyter Lab trên port 8888 để làm bài tập
   .\run.ps1 lab

   # Chạy benchmark kiểm tra Precision@10 và P99 latency
   .\run.ps1 benchmark

   # Chạy toàn bộ unit tests
   .\run.ps1 test

   # Chạy tự động tất cả các notebook để chấm điểm
   .\run.ps1 notebooks
   ```

3. Kích hoạt virtualenv thủ công trong PowerShell (khi cần):
   ```powershell
   .venv\Scripts\Activate.ps1
   ```

---

## 4. Danh sách lệnh `run.ps1` trên Windows

| Mục đích | Lệnh PowerShell |
|---|---|
| Cài đặt Lite | `.\run.ps1 setup-lite` |
| Kiểm tra Smoke test Lite | `.\run.ps1 verify-lite` |
| Sinh lại dữ liệu corpus | `.\run.ps1 seed` |
| Chạy FastAPI Server (:8000) | `.\run.ps1 api` |
| Mở Jupyter Lab (:8888) | `.\run.ps1 lab` |
| Đo Benchmark Precision@10 & Latency | `.\run.ps1 benchmark` |
| Chạy pytest | `.\run.ps1 test` |
| Sinh dữ liệu nâng cao (NB6 + NB8) | `.\run.ps1 gen-advanced` |
| Chạy headless tất cả notebook | `.\run.ps1 notebooks` |
| Dọn dẹp môi trường Lite | `.\run.ps1 clean-lite` |
| Cài đặt Docker Full Stack | `.\run.ps1 setup-docker` |
| Khởi động Docker containers | `.\run.ps1 docker-up` |
| Tắt Docker containers | `.\run.ps1 docker-down` |
| Xóa Docker volumes | `.\run.ps1 docker-clean` |
| Kiểm tra kết nối Docker | `.\run.ps1 verify-docker` |

---

## 5. Các lưu ý & xử lý lỗi phổ biến trên Windows

### 1. Lỗi PowerShell: `cannot be loaded because running scripts is disabled on this system`
- **Nguyên nhân:** Chính sách bảo mật Execution Policy mặc định của PowerShell chặn file `.ps1`.
- **Cách khắc phục:** Chạy lệnh sau trong PowerShell trước khi gọi file script:
  ```powershell
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
  ```

### 2. Lỗi cổng (Port 8000, 8888, 6333, 6379, 5432) đang bị chiếm
- Nếu port 8000 hoặc 8888 đã có ứng dụng khác sử dụng, bạn có thể chỉ định port khác:
  ```powershell
  .venv\Scripts\uvicorn.exe app.main:app --reload --port 8001
  .venv\Scripts\jupyter.exe lab --notebook-dir=notebooks --port 8889
  ```

### 3. Làm bài trên Jupyter Notebook hoặc VS Code
- Các file notebook gốc nằm tại `notebooks/*.py` và được tự động convert thành `notebooks/*.ipynb` khi chạy `setup-lite` hoặc `run lab`.
- Bạn có thể mở trực tiếp các file `.ipynb` trong VS Code (chọn kernel là Python trong `.venv\Scripts\python.exe`) hoặc qua giao diện web Jupyter Lab (`http://localhost:8888/lab`).
