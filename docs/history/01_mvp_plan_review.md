<!-- Lưu trữ nguyên văn báo cáo từ phiên làm việc. -->

Tôi đã đọc hết tài liệu. Chưa sửa gì trong repo; mọi thử nghiệm đều nằm trong scratchpad.

**Kết luận chính: level mực hiện tại chưa đạt.** Gameplay prototype đã có không khớp với yêu cầu của tài liệu (nhất là việc chọn màu), và phần web React không còn đúng engine đã chốt.

## 1. Phạm vi MVP tôi hiểu như sau

- Game làm bằng **Godot 4.x + GDScript**, chạy trên iPhone trước. Giao diện phải co giãn được để sau này lên iPad.
- Lưu tiến độ ngay trên máy, không có backend, không đăng nhập, không mua hàng trong app.
- Có 2 chế độ: **Journey** (qua bàn) và **Zen** (không giới hạn thời gian, không chấm điểm).
- Người chơi **tự chọn màu trong khay rồi chạm vào ô**, chưa có kéo thả. Chọn sai màu thì chỉ báo nhẹ nhàng, không phạt.
- Bắt buộc có: zoom/pan, lưu và khôi phục tiến độ, gợi ý cơ bản (đính 1 ô hoặc chỉ ra 1 ô), âm thanh hiệu ứng và âm nền chỉnh riêng được, mỗi ô hiện số hoặc ký hiệu màu cho người khó phân biệt màu.
- Việc đầu tiên là một vertical slice: chọn màu → đính hạt → nghe ASMR → lưu → hoàn thành. Chỉ khi slice này ổn mới làm 20–30 tranh.

## 2. Môi trường và repo

- **Godot 4.4.1 chạy được headless trong container này.** Tôi viết được GDScript và chạy test logic ngay ở đây.
- **Không có macOS/Xcode.** Bước "app trống chạy trên iPhone thật" của tuần 1 bạn phải tự làm trên máy Mac. Tôi chuẩn bị sẵn project và cấu hình export.
- Repo hiện có:
  - `tools/`: pipeline Python, khớp với tài liệu, giữ lại và nâng cấp.
  - `web/`: prototype React, lệch engine đã chốt. Tôi đề xuất chỉ giữ làm bản tham khảo để chỉnh cảm giác chơi và âm thanh, không port từng dòng sang Godot.

## 3. Kiểm tra level mực

**Dữ liệu (cả 3 level đều lỗi):**
- Thiếu các trường `id`, `title`, `difficulty`, `modes` mà tài liệu yêu cầu.
- Số lượng ô của từng màu thì khớp.

**Palette — lỗi nghiêm trọng khi người chơi phải tự chọn màu:**
- Easy có 2 màu xanh giống hệt nhau (`#267aa1` và `#267ba2`, ΔE = 0,4).
- Relax có 3 màu xanh giống hệt nhau (ΔE từ 0,6 đến 1,3).
- Nguyên nhân: bước gộp màu tôi viết trước đó dựa trên số lượng ô, đáng lẽ phải dựa trên khoảng cách màu mà mắt nhìn thấy (ΔE). Khi gộp theo ΔE < 12 thì Easy còn 3 màu phân biệt rõ và hết hạt lẻ.

**Silhouette:**
- **Easy:** san hô không bị nhập vào con mực (0 ô), mực là 1 mảng liền. Nhưng ở 14×13 ô thì nó chỉ là "một mảng đỏ": mất mắt, mất đường cong xúc tu, còn viền xám là nhiễu từ bước tách nền. **Không đạt** tiêu chí "dễ nhận ra ở kích thước thumbnail".
- **Challenge:** 53/55 ô san hô bị tô cùng màu đỏ với mực, nên khó tách đâu là chủ thể. Một màu có tới 22 hạt lẻ.
- **Thử pipeline mới (28 cột, palette 5 màu theo ý nghĩa):** đã có mắt và bóng đổ. Nhưng xúc tu vẫn đứt đoạn, vì cách tách chủ thể theo màu bỏ sót phần xúc tu màu hồng nhạt.
- **Nhận định:** tranh này nhiều chi tiết mảnh. Thuật toán nào thu nhỏ xuống dưới khoảng 20 cột cũng sẽ mất đặc điểm nhận dạng của con mực.

**Logic chọn ô của prototype hiện tại (dùng làm spec khi chuyển sang Godot):**
- Người chơi không được chọn màu: thứ tự màu bị ép sẵn (`web/src/game/engine.ts:30`).
- Chạm sai màu thì bị bỏ qua im lặng, không có phản hồi nào (`engine.ts:74`).
- Hạt được đặt ngay khi chạm xuống (`BeadBoard.tsx:174`). Khi có thêm pan/zoom thì kéo màn hình sẽ đặt nhầm hạt, trái tiêu chí nghiệm thu về cảm ứng.
- Ô chưa đính hiện màu ngẫu nhiên (`engine.ts:24`), không có số hay ký hiệu và không làm nổi các ô hợp lệ.
- Các nút trợ giúp quá mạnh: đũa phép đính 3 ô, cọ đính 40%, nam châm đính hết một màu (`engine.ts:114–118`). Tài liệu chỉ cần gợi ý 1 ô.
- Có lỗi layout: canvas lấy chiều rộng tính cả padding (`BeadBoard.tsx:50`) nên tràn khung 20px.
- Ở 14–24 cột trên iPhone, mỗi ô chỉ khoảng 15–26pt, nhỏ hơn mức 44pt Apple khuyến nghị cho vùng chạm. Vì vậy zoom là bắt buộc, không phải tính năng thêm.

## 4. Kiến trúc đề xuất

Giữ cấu trúc trong tài liệu, bổ sung ba điểm:
1. **`BoardModel` thuần logic**, không phụ thuộc Node của Godot, để test headless được.
2. **Vẽ cả lưới trong một lần `_draw()` hoặc dùng MultiMesh**, không dùng mỗi ô một Node. Challenge có 1444 ô nên cần vậy để giữ 60 FPS.
3. **`TouchController` phân biệt chạm với kéo/chụm:** chỉ đặt hạt khi nhấc tay ra, ngón tay di chuyển dưới khoảng 10px, và chỉ có 1 ngón chạm.

Pipeline nhận thêm một file **mask chủ thể** đã được duyệt cho mỗi tranh, thay vì đoán chủ thể bằng màu. Bước validator tự động kiểm tra: schema, ΔE tối thiểu giữa các màu, hạt lẻ và độ khớp silhouette.

## 5. Các bước nhỏ (mỗi bước chạy và kiểm thử được)

1. **Chuẩn hoá schema level v1 và viết validator.**
   - File: `tools/validate_level.py`, sửa `tools/image_to_beadgrid.py`.
   - Test: validator báo lỗi đúng với 3 level hiện tại.
   - Rủi ro: thấp.
2. **Tạo lại 1 level mực duy nhất:** gộp màu theo ΔE, palette theo ý nghĩa, dùng mask. Bạn duyệt bằng mắt.
   - File: `tools/`, `content/levels/squid_01.json`.
   - Rủi ro: silhouette vẫn kém. Xem quyết định B bên dưới.
3. **Khởi tạo project Godot và `BoardModel`** (chọn màu, đặt ô, xử lý sai màu, tự chuyển màu khi hết, gợi ý 1 ô).
   - Test: test headless chạy trong container. Bạn build project trống lên iPhone.
4. **Render lưới và `TouchController`** (chạm, pan, zoom, nút đưa về toàn cảnh).
   - Test: chạy kịch bản chạm/kéo tự động, kiểm tra không đặt nhầm.
5. **`SaveManager`**, sau đó **`AudioManager`** (port các âm ASMR, tách âm lượng hiệu ứng và âm nền, giới hạn số âm phát chồng).

## Cần bạn quyết định

- **A. Engine:** xác nhận làm Godot từ bước 3, và để `web/` lại làm bản tham khảo (hay xoá đi)?
- **B. Level đầu tiên và tier Easy:** tôi đề xuất vertical slice dùng chính tranh này ở khoảng 24–28 cột, có zoom. Riêng **Easy nên làm từ một bản vẽ mực đơn giản, nét to và nhìn thẳng** (tạo bằng AI rồi bạn duyệt), thay vì thu nhỏ tranh chi tiết này. Bạn đồng ý không?
- **C. Mask chủ thể:** bạn chấp nhận mỗi tranh có thêm một file mask được duyệt (tạo bằng công cụ tách nền rồi chỉnh tay) không?

Nếu bạn đồng ý, tôi bắt đầu bước 1 (schema và validator) vì bước này không phụ thuộc vào các quyết định trên.
