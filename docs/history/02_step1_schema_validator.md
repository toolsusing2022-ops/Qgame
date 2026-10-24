<!-- Lưu trữ nguyên văn báo cáo từ phiên làm việc. -->

Bước 1 đã xong, đã commit và push lên nhánh (`8feed74`). Validator bắt được lỗi ở cả 3 level hiện có: **0/3 file hợp lệ**.

## File đã sửa

| File | Thay đổi |
|---|---|
| `tools/validate_level.py` (mới) | Validator schema v1, ΔE CIEDE2000, CLI (`--strict` để cảnh báo cũng làm fail) |
| `tools/tests/test_validate_level.py` (mới) | 42 test bằng `unittest` |
| `tools/LEVEL_SCHEMA.md` (mới) | Hợp đồng dữ liệu và quy tắc mã hoá ô cho cả Python và Godot |
| `tools/image_to_beadgrid.py` | Chỉ sửa phần ghi đầu ra: xuất đúng v1, bắt buộc có `--id`/`--title`/`--difficulty`, chạy validator và **không ghi file nếu có lỗi** |
| `.gitignore` (mới) | Bỏ qua `__pycache__/` |

Không đụng tới 3 file level, `web/` và code gameplay.

## Schema v1

```json
{ "schema_version": 1, "id": "squid_easy_01", "title": "Mực đỏ",
  "difficulty": "easy|relax|challenge", "modes": ["journey","zen"],
  "width": 14, "height": 13,
  "palette": [{"id": 0, "hex": "#rrggbb", "count": 79, "name": "tuỳ chọn"}],
  "cells": [ ...width*height số nguyên... ],
  "mask":  [ ...tuỳ chọn, 0/1... ] }
```

Quy tắc mã hoá ô:
- `cells` là mảng phẳng theo hàng: ô ở cột `x`, hàng `y` nằm tại `cells[y*width + x]`.
- `-1` là vị trí không có hạt.
- ID màu bằng đúng vị trí của màu đó trong `palette`.
- Godot đọc mọi số trong JSON thành `float`, nên khi nạp phải ép `int()`. Tôi đã chạy thử trên Godot 4.4.1 để xác nhận (`width` đọc ra `3.0`), và ép `int()` cho ra cùng toạ độ `x`/`y` như phía Python.

**Lỗi (level không được dùng):** thiếu trường, sai kích thước, sai mã hex, ID màu lệch vị trí, ô dùng mã màu không có trong palette, ô thiếu dữ liệu hoặc không phải số nguyên, màu không ô nào dùng, `count` sai, hai màu trùng hex, mask sai, khoá JSON bị trùng, NaN.

**Cảnh báo (validator không tự gộp màu):** ΔE00 < 3 là gần như trùng, ΔE00 < 10 là khó phân biệt trên hạt nhỏ.

## Kết quả test (đã chạy thật)

- **`unittest`: 42/42 pass.** Gồm các trường hợp bạn yêu cầu: dữ liệu hợp lệ, thiếu trường, sai kích thước, mã màu sai, màu trùng, màu không dùng, cùng với mask, file JSON hỏng, mã thoát của CLI và kiểm tra đầu ra của pipeline.
- **Kiểm tra test có tác dụng thật:** tôi cố tình gài 5 lỗi vào bản sao của validator, cả 5 lần test đều fail.
- **CIEDE2000:** khớp 9 cặp tham chiếu Sharma (2005) đến 4 chữ số thập phân.
- **CLI trên 3 level thật:** 0/3 hợp lệ, mã thoát 1.

| Level | Lỗi | Cảnh báo | Chi tiết |
|---|---|---|---|
| Easy | 9 | 4 | Định dạng cũ, thiếu metadata, `cells` 2D; 2 màu xanh gần như trùng (ΔE00 = 0,4) |
| Relax | 9 | 9 | Như trên; 3 màu xanh gần như trùng nhau (ΔE00 0,3–1,1) |
| Challenge | 9 | 6 | Như trên; 4 cặp màu khó phân biệt (ΔE00 5,5–9,0) |

Khi chuyển tạm 3 file sang v1 (chỉ trong scratchpad), cả 3 đều 0 lỗi: số đếm khớp, không có mã màu lạ, không có màu thừa. Vấn đề thực chất chỉ còn định dạng và palette.

## Lỗi còn tồn tại

1. **3 level hiện có vẫn ở định dạng cũ.** Tôi cố ý chưa tạo lại theo yêu cầu "không sửa hàng loạt tranh". Bản sao trong `web/src/data/` cũng giữ nguyên.
2. **Pipeline vẫn sinh ra màu gần trùng.** Chạy thử Relax ra 11 cảnh báo, trong đó 6 cặp gần như trùng. Pipeline cũng vẫn còn tuỳ chọn gộp màu theo số lượng ô (`--min-color-frac`, mặc định tắt), trái với yêu cầu 4 của bạn.
3. **Cách tách chủ thể theo màu vẫn làm mất xúc tu.** Cần thay bằng mask đã được duyệt.
4. **Validator chỉ kiểm mask có hợp lệ hay không**, chưa biết mask có làm mất mắt hay xúc tu không. Phần đó cần so silhouette với mask nguồn và bạn duyệt bằng mắt.
5. **Màu gần như trùng (ΔE00 < 3) hiện chỉ là cảnh báo**, đúng theo yêu cầu 4. Với cơ chế người chơi tự chọn màu, tôi đề xuất bước kiểm tra trước khi phát hành chạy với `--strict`. Quyết định này là của bạn.

## Bước tiếp theo đề xuất: Bước 2, sửa pipeline cho đúng một level

- **Mục tiêu:**
  - Pipeline nhận thêm một file mask chủ thể đã duyệt (`--mask`), bỏ hẳn bước gộp màu theo số lượng ô.
  - Pipeline xuất thêm `mask` ở độ phân giải lưới, một con số đo độ khớp silhouette, và ảnh preview có đánh mã màu từng ô để duyệt.
  - Tạo ra **đúng một** level `squid_relax_01` từ tranh hiện tại.
- **File:** `tools/image_to_beadgrid.py`, một file mask mới, `content/levels/squid_relax_01.json`.
- **Cách test:** test cho phần mask, chạy validator ở chế độ `--strict` trên level mới, bạn duyệt ảnh preview.
- **Rủi ro:** mask đầu tiên do tôi tạo bằng công cụ có thể vẫn hụt xúc tu, nên bạn phải duyệt bằng mắt trước khi dùng.

**Tranh Easy đơn giản (quyết định B):** cần ảnh nguồn mới. Bạn có thể tự gửi ảnh, hoặc tôi tạo bằng công cụ sinh ảnh Higgsfield đang kết nối. Cách thứ hai tốn credit của bạn, nên tôi sẽ không dùng nếu bạn chưa đồng ý.
