# Tiến trình dự án Pixel Bead Art ASMR

Cập nhật: 2026-10-27. Nhánh làm việc: `claude/cloud-session-connection-check-hksw4v`.

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
| Đặc tả | Đặc tả gameplay MVP v0.1 → v0.4.9 trong `docs/spec/` | `2eeb09b` |
| Nghiên cứu | `docs/research/gameplay_research.md` | `2eeb09b` |
| Probe | `tools/probes/godot_storage/` (hành vi lưu trữ của Godot 4.4.1 trên Linux) | `2eeb09b` |
| Catalog + hash | `tools/level_hash.py`, `tools/build_catalog.py`, `content/catalog.json`, fixture dùng chung | `dac35bc` |
| Game Godot (demo chơi được) | Project ở gốc repo, code trong `game/`: luật chơi, màn chơi, lưu/khôi phục theo đặc tả, sự kiện | xem `git log` |
| Chế độ "Gỡ hạt" | Lối chơi theo video tham khảo (Jewel Color Sort), hai lần chạm: chạm mảng hạt sai màu (hoặc hạt trong khay) để nhấc lên, rồi chạm chỗ trống cùng màu để đặt hoặc chạm khay để cất tạm (6 khay × 9 ô, có sẵn một phần hạt lúc bắt đầu); chế độ mặc định của demo | xem `git log` |

Các báo cáo từng bước nằm trong `docs/history/`.

## Bản demo web

- Âm thanh, font, icon và nguồn/giấy phép: `docs/ASSETS.md`.
- Build lại bản web (cần export template `web_nothreads_release.zip` của 4.4.1 trong `~/.local/share/godot/export_templates/4.4.1.stable/`):

```bash
godot --headless --path . --export-release "Web" build/web/index.html
# host thường (GitHub Pages, itch.io, máy chủ tĩnh): phục vụ build/web nguyên trạng
# host giới hạn 15 MB/file và loại file (artifact claude.ai):
cp -r build/web build/web_split && python3 tools/web/package_web.py build/web_split --pck-alias index.pck.wasm
```

## Quyết định đã chốt

- **A.** Chuyển sang Godot; giữ `web/` làm tham khảo.
- **B.** Easy dùng hình bạch tuộc đơn giản; Relax và Challenge dùng mực anime.
- **C.** Mỗi tranh có một subject mask đã duyệt, giữ được mắt, xúc tu và các chi tiết nhận diện.
- **KT-1 đến KT-7:** xem `docs/spec/README.md`.

## Đang chờ

1. **Âm thanh**: đã có bộ tạm (Kenney CC0 + âm tự tạo); thay bằng file của bạn trong `game/audio/<tên>/` khi có.
2. **Mac + iPhone** (đang chuẩn bị) → export iOS, test cấp D (Phần B của v0.4.9).
3. Duyệt đặc tả **v0.4.9**.
4. Chọn hướng chính: đặc tả v0.4.9 mô tả lối "tô theo số"; chế độ "Gỡ hạt" chưa có đặc tả. Cần quyết định có viết đặc tả cho "Gỡ hạt" (độ khó, số khay, luật thua/kẹt) hay giữ cả hai chế độ.
5. Ảnh thumbnail 96 px của Easy vẫn nhỏ: mặt chỉ còn vài chấm.

Danh sách chi tiết những gì đã làm và chưa làm so với đặc tả: `docs/IMPLEMENTATION_STATUS.md`.

## Cách chạy kiểm tra hiện có

```bash
# Test Python (82 test, đạt ngày 2026-10-25)
python3 -B -m unittest discover -s tools/tests -p 'test_*.py'
python3 tools/build_catalog.py --check

# Test Godot 4.4.1 headless (129 test, đạt ngày 2026-10-27)
godot --headless --path . -s res://game/tests/run_unit.gd

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

- Các TC cấp U/I đã chạy trên Linux headless; chưa có test nào chạy trên iOS.
- Chưa có kết quả trên macOS hay iOS. Mọi năng lực lưu trữ đều ở mức `assumed`; không có `durable (verified)`.
- Container không có Mac hay Xcode.
