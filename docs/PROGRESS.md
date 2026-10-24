# Tiến trình dự án Pixel Bead Art ASMR

Cập nhật: 2026-10-24. Nhánh làm việc: `claude/cloud-session-connection-check-hksw4v`.

## Mục tiêu

Game Pixel Bead Art ASMR, ưu tiên iPhone, iPad làm sau.
- Engine: **Godot 4.x + GDScript**, ghim bản 4.4.1-stable cho MVP.
- `web/` là prototype React, chỉ giữ để tham khảo, không port từng dòng.
- Pipeline nội dung bằng Python, xuất level JSON theo schema v1.

## Đã xong

| Bước | Nội dung | Commit |
|---|---|---|
| Prototype web | `web/` (React) | `5dfb1fe` |
| Bước 1 | Schema level v1 (`tools/LEVEL_SCHEMA.md`) và validator `tools/validate_level.py` (CIEDE2000, WCAG, `--strict`) | `8feed74` |
| Bước 2 | Sinh level theo mask (`tools/image_to_beadgrid.py`), `tools/draft_mask.py`, `tools/level_review.py`; level `content/levels/squid_relax_01.json` (32×32, 14 màu) và `content/trials/squid_easy_01.json` (20×15, 8 màu), kèm preview | `6fe07e8` |
| Đặc tả | Đặc tả gameplay MVP v0.1 → v0.4.9 trong `docs/spec/` | commit hiện tại |
| Nghiên cứu | `docs/research/gameplay_research.md` | commit hiện tại |
| Probe | `tools/probes/godot_storage/` (hành vi lưu trữ của Godot 4.4.1 trên Linux) | commit hiện tại |

Các báo cáo từng bước nằm trong `docs/history/`.

## Quyết định đã chốt

- **A.** Chuyển sang Godot; giữ `web/` làm tham khảo.
- **B.** Easy dùng hình bạch tuộc đơn giản; Relax và Challenge dùng mực anime.
- **C.** Mỗi tranh có một subject mask đã duyệt, giữ được mắt, xúc tu và các chi tiết nhận diện.
- **KT-1 đến KT-7:** xem `docs/spec/README.md`.

## Đang chờ

1. Duyệt đặc tả **v0.4.9** (`docs/spec/gameplay_mvp_v0.4.9.md`).
2. Cho phép bắt đầu **Giai đoạn 1**: viết code Godot (storage backend, progress writer, restore, event store) và chạy unit test trong container.
3. Ảnh thumbnail 96 px của Easy vẫn nhỏ: mặt chỉ còn vài chấm. Đã đề xuất đơn giản hoá ảnh nguồn hoặc dùng thumbnail từ ảnh gốc.

## Cách chạy kiểm tra hiện có

```bash
# Test Python của công cụ nội dung (68 test, đạt ngày 2026-10-24)
python3 -B -m unittest discover -s tools/tests -p 'test_*.py'

# Kiểm tra level
python3 tools/validate_level.py --strict content/levels/squid_relax_01.json content/trials/squid_easy_01.json
```

**Lệnh sinh lại level** (chi tiết trong `docs/history/03_*` và `04_*`):
- Relax: `--cols 32 --keep-tips 0.25`.
- Easy: `--cols 20 --crop-to-mask 0.04 --keep-tips 0.25`.
- Mask Relax: `tools/draft_mask.py ... --include-ellipse 611,552,40,58 --include-ellipse 630,512,24,18`.
- Mask Easy: `--attach-r 6`.

## Lộ trình kiểm chứng

Xem Phần B của `docs/spec/gameplay_mvp_v0.4.9.md`.
- **Giai đoạn 1:** unit test Godot headless trên Linux.
- **Giai đoạn 2:** macOS (ảnh đĩa APFS, `fs_usage`).
- **Giai đoạn 3:** iPhone dành riêng cho test (cấp D).
- **Giai đoạn 4:** hồ sơ bằng chứng và cổng Q1/Q2.

## Chưa kiểm chứng

- Chưa có code Godot của game; chưa có TC-12.x, 13.x, 14.x nào được chạy.
- Chưa có kết quả trên macOS hay iOS. Mọi năng lực lưu trữ đều ở mức `assumed`; không có `durable (verified)`.
- Container không có Mac hay Xcode.
