# Trạng thái hiện thực so với đặc tả

Cập nhật: 2026-10-25. Đối chiếu với đặc tả v0.3 → v0.4.9 (`docs/spec/`). Mọi test dưới đây là test cấp U/I chạy headless trên Linux; **chưa có test nào chạy trên iOS**.

## Cách chạy

```bash
# Test Python (công cụ nội dung, hash, catalog)
python3 -B -m unittest discover -s tools/tests -p 'test_*.py'
python3 tools/build_catalog.py --check

# Test Godot (cần Godot 4.4.1-stable)
godot --headless --path . -s res://game/tests/run_unit.gd            # tất cả
godot --headless --path . -s res://game/tests/run_unit.gd -- restore # lọc theo tên

# Chạy game (desktop, chuột giả lập chạm; con lăn chuột để zoom)
godot --path .
```

## Đã hiện thực

| Phần | Code | Test chính |
|---|---|---|
| Dữ liệu level, cùng mã lỗi với Python (mục 2) | `game/core/level_loader.gd` | TC-2.1–2.3, 2.10 (manifest chung `tests/fixtures/levels`), 2.11 |
| Hash chuẩn hoá (GS-13.1/13.2), catalog (GS-13.8) | `tools/level_hash.py`, `tools/build_catalog.py`, `game/core/level_hash.gd` | TC-13.1–13.3 (Python và Godot) |
| Luật chơi: chọn màu, tap, Undo, Tìm, hoàn thành (mục 3, 4, 6, 9, 10) | `game/core/board_state.gd` | TC-4.x, 6.x, 9.x, 10.x, 6.9, 6.10 (10.000 thao tác ngẫu nhiên) |
| Cử chỉ, chạm-để-zoom (mục 5) | `game/core/gesture_tracker.gd`, `game/scenes/board_view.gd` | TC-5.1–5.12, 5.17–5.21, 5.23 |
| Màn chơi, khay, nút, thông báo (mục 7, 8, 11) | `game/scenes/*.gd` | TC-8.1, 8.3, 9.4, 9.6, 10.9, 11.9, 4.6 |
| `StorageBackend` + hợp đồng rename (GS-12.8) | `game/storage/*.gd` | TC-12.33–12.35, 12.38 (a–m), 12.40, 12.41, 12.59 |
| Giao thức ghi, bảng WE/WK, bước R, đường U, `save_blocked` (GS-12.2, 12.7) | `game/save/progress_writer.gd` | TC-12.7, 12.12–12.21, 12.34, 12.42, 12.49, 12.55 |
| Khôi phục E0–E3, lưu trữ, thông báo `.bak` (GS-13.3–13.15) | `game/save/restore.gd` | TC-13.4–13.6, 13.12, 13.13, 13.17, 13.22, 13.24, 13.28, 13.31, 13.32, 12.13, 12.56 |
| Outbox, kho sự kiện, bộ chuyển, file `.pending-*` (mục 14) | `game/save/progress_session.gd`, `game/events/*.gd`, `game/save/pending_scan.gd` | TC-14.4, 14.9, 14.15, 14.22–14.30, 4.6/14.2 |
| Chế độ "Gỡ hạt" (ngoài đặc tả, theo video tham khảo): luật chọn → đích, khay 54 ô cố định, bộ sinh đề có kiểm tra giải được, màn chơi, lưu riêng file `<id>.sort` | `game/core/sort_state.gd`, `game/core/sort_puzzle.gd`, `game/scenes/sort_play.gd` | `test_sort_mode.gd` (chạm 1 chỉ chọn, đặt/cất khay, phần dư giữ chọn, bảo toàn hạt, giải được, chơi ngẫu nhiên, lưu/đọc, màn chơi mở lại) |
| Lưu thật qua `GodotFileBackend` (Linux) | `game/storage/godot_file_backend.gd` | `test_persistence.gd` |

## Chưa hiện thực hoặc mới làm một phần

| Mục | Ghi chú |
|---|---|
| Hồ sơ bằng chứng, `revocation_list`, danh sách `suspended` (GS-12.8) | Năng lực luôn trả về mức `assumed`; không có cơ chế nâng lên `verified` |
| Migration (GS-13.10) | Chưa đăng ký migration nào (đúng như MVP); chưa có migration mẫu cho TC-13.7 |
| Chế độ Journey (khoá tranh), đổi chế độ, tắt phản hồi chạm sai trong Zen (mục 15, GS-6.8) | Hiện chỉ có Zen; mọi tranh đều mở |
| Âm nền, bật/tắt haptic trong UI, Reduce Motion (GS-11.3–11.6) | Đã có cờ `reduce_motion` nhưng chưa đọc từ hệ điều hành |
| Âm thanh thật | Đã có hook; đặt file vào `game/audio/<tên>/` (`place`, `wrong`, `lift`, `pick`, `color_complete`, `level_complete`) |
| TC-12.24 liệt kê đủ mọi trạng thái trung gian | Mới có các điểm crash chính và một ca mất nguồn cơ bản |
| File `.orphan` ở bản debug (GS-13.13) | Hiện luôn xoá file tạm |
| Trợ năng VoiceOver (GS-16.3), đo hiệu năng (GS-12.5, 16.1) | Chưa làm |
| Export iOS, test cấp D (GS-12.10) | Cần Mac và iPhone |

## Lệch so với đặc tả, có chủ đích

- **GS-2.2:** Godot đọc mọi số JSON thành `float`, nên `1.0` được chấp nhận (đúng với GS-2.2), trong khi `validate_level.py` từ chối. Khoá JSON trùng nhau cũng chỉ bị Python bắt. Pipeline nội dung luôn chạy Python trước.
- **GS-13.4 giai đoạn A:** các kiểm tra phụ thuộc bố cục (độ dài bitset, hạt trên ô `-1`, `selected` ngoài phạm vi) chạy **sau** khi `layout_hash` đã khớp. Nhờ vậy bản lưu của bố cục cũ được báo là `stale_layout_changed` thay vì `invalid`.
- **Chế độ "Gỡ hạt"** không có trong đặc tả v0.4.9. Bản lưu của nó dùng lại `ProgressWriter` (ghi nguyên tử + `.bak`) nhưng không qua giai đoạn khôi phục E0–E3; bản lưu hỏng hoặc khác `content_hash` thì sinh đề mới.
- **Số trên ô và swatch** hiển thị theo `id + 1` (bắt đầu từ 1) cho dễ đọc.
