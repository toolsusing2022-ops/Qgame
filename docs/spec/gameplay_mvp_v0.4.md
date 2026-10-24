<!-- Lưu trữ nguyên văn bản đặc tả v0.4 từ phiên làm việc. Xem docs/spec/README.md để biết cách đọc. -->

# Đặc tả gameplay MVP v0.4: các phần thay thế

Những mục không có trong tài liệu này **giữ nguyên như v0.3**: 1, 2, 5, 6, 7, 8, 10 (trừ ghi chú ở GS-10.6), 11, 15, 16, 17.

Các mục dưới đây **thay thế hoàn toàn** mục cùng mã trong v0.3: 0.2 (thêm 1 tham số), 3, 4.5–4.6, 9.2 (thêm 1 câu), 12.3–12.4, 13, 14, và các bảng test 4, 9, 12, 13, 14 cùng ma trận đối chiếu.

---

## 0.2 Tham số (thêm 1 dòng)

| Tham số | Mặc định | Ghi chú |
|---|---|---|
| `PALETTE_RECOLOR_MAX_DE` | 20 | ΔE00 tối đa giữa màu cũ và màu mới **của cùng một ID** để còn được coi là "chỉnh màu". Đây là chốt chặn an toàn của nội dung, không phải thông số đo trên thiết bị; cần người phụ trách nội dung duyệt |

---

## 3. Trạng thái (thay thế)

| Trường | Lưu qua lần mở app? | Ý nghĩa |
|---|---|---|
| `placed` | Có | Bitset dài `w×h` |
| `remaining[c]` | Không | Luôn tính lại từ `cells` và `placed` |
| `selected` | Có | |
| `completed` | Có | **Trạng thái của level**, không liên quan tới việc sự kiện đã được ghi hay chưa |
| `colors_ever_completed` | Có | Bitset dài bằng số màu |
| `content_version`, `palette_snapshot` | Có | Lấy từ catalog và palette **tại thời điểm lưu** (GS-13.8) |
| `outbox` | Có | Hàng đợi các sự kiện bền vững **chưa được chuyển** vào kho sự kiện (GS-14.3) |
| `last_placed`, `find_visited`, `camera`, `wrong_streak` | Không | |

> Trường `completion_reported` của v0.3 **bị bỏ**. Việc "đã ghi nhận hoàn thành" giờ thể hiện bằng sự kiện `level_complete` nằm trong `outbox` hoặc đã có trong kho sự kiện, tách hẳn khỏi `completed`.

- **GS-3.1. Bất biến:**
  - `remaining[c] = count(i: cells[i]=c ∧ ¬placed[i])`
  - `placed[i] ⇒ cells[i] ≥ 0`
  - `completed ⇔ Σ remaining = 0`
  - `colors_ever_completed ⊇ {c : remaining[c]=0}`
  - Mỗi `event_id` xuất hiện **tối đa một lần** trong `outbox`.
- **GS-3.2. Phiên chơi:** giữ nguyên như v0.3.

---

## 4. Luồng màn chơi (chỉ thay GS-4.5 và GS-4.6)

- **GS-4.5. Hết tranh.** Khi lần đặt hạt làm `Σ remaining` về 0:
  1. Trong bộ nhớ: đặt `completed = true`; cập nhật `colors_ever_completed`; thêm vào `outbox` các sự kiện của lần đặt này (`bead_placed`, `color_complete`, `level_complete`).
  2. Ghi **tất cả** vào **một lần ghi atomic** của file tiến độ (GS-12.2).
  3. Chỉ sau khi ghi xong mới khoá đặt hạt, Undo và Tìm; phát tiếng hoàn thành; hiện màn hoàn thành. Journey mở khoá tranh kế tiếp, suy ra từ `completed`.
  4. Bộ chuyển sự kiện xử lý `outbox` (GS-14.4).
  - Nếu tiến trình dừng **trước khi bước 2 xong**, khi khởi động lại level vẫn ở trạng thái chưa xong, và **không có** sự kiện `level_complete` nào. Người chơi đặt lại hạt cuối (GS-12.4).
- **GS-4.6. Mở lại level đã xong:** chỉ hiện tranh hoàn thành. **Không** thêm sự kiện mới vào `outbox`. Bộ chuyển vẫn xử lý những mục còn sót trong `outbox`, nếu có. MVP không có tính năng đặt lại tiến độ.

---

## 9.2 Camera của nút Tìm (thêm một câu cuối)

> … Có chạm thì dừng ngay, và lần chạm đó không tạo tap (GS-5.3). **Hoạt ảnh dừng do lần chạm này không bao giờ dẫn tới việc đặt hạt; muốn đặt phải có một tap mới, bắt đầu khi camera đã đứng yên** (GS-5.1d, GS-5.11).

---

## 10.6 Ghi chú bổ sung

> `colors_ever_completed` được giữ qua các lần mở app (GS-3), nhưng `last_placed` thì không (D-8). Vì vậy **không thể** hoàn tác một hạt đã đặt ở phiên trước, và một màu đã xong ở phiên trước không thể chuyển sang trạng thái `repeat` trong phiên sau. Chỉ trừ trường hợp phiên sau tự đặt lại hạt cuối của màu đó, mà điều này là không thể vì màu đó đã xong.

---

## 12. Lưu tiến độ (thay GS-12.3 và GS-12.4)

- **GS-12.3. Nội dung file tiến độ** `progress/<level_id>.json`:
  - Định danh và phiên bản: `save_version`, `level_id`, `level_schema_version`, `content_version`.
  - Dấu vân tay: `layout_hash`, `content_hash`.
  - Ảnh chụp palette: `palette_snapshot` = `[{hex, name?}]`, xếp theo ID.
  - Tiến độ: `placed` (bitset mã hoá base64), `selected`, `completed`, `colors_ever_completed`.
  - Hàng đợi sự kiện: `outbox` = `[{event_id, type, payload, ts}]`, giữ đúng thứ tự thêm vào.
  - `updated_at`.
  - **Không lưu:** `last_placed`, `find_visited`, `camera`, `wrong_streak`.
  - `install_id` (UUID tạo một lần cho mỗi bản cài) nằm trong file cấu hình app, tách riêng với file tiến độ.
- **GS-12.4. Mục tiêu mất dữ liệu.** Đây là **mục tiêu thiết kế và kiểm thử, không phải bảo đảm tuyệt đối**:
  - Tiến trình bị dừng ≥ 200 ms sau thao tác cuối: không mất thao tác nào.
  - Bị dừng ngay sau thao tác: mất tối đa 1 thao tác. Các sự kiện bền vững của thao tác đó cũng mất theo, vì chúng nằm trong cùng lần ghi.
  - Mục tiêu này không áp dụng cho: mất nguồn hoặc thiết bị treo khi đang ghi xuống bộ nhớ, lỗi phần cứng lưu trữ, hệ điều hành hoãn ghi.
  - Các yêu cầu sau **không được nới lỏng** vì mục tiêu này: ghi sau mỗi lần đặt hạt hoặc Undo (GS-12.1), ghi atomic và giữ `.bak` (GS-12.2), khôi phục theo GS-13.4.

---

## 13. Dấu vân tay, khôi phục, migration (thay thế toàn bộ)

- **GS-13.1. Chuỗi chuẩn hoá để băm:** giữ nguyên định nghĩa của v0.3, bổ sung một ghi chú.
  - **Ghi chú:** `layout_hash` giống nhau chỉ chứng minh `w`, `h`, số màu `n` và `cells` giống nhau. Nó **không** chứng minh ý nghĩa của từng ID màu còn giữ nguyên.
  - Vì vậy, "`content_hash` khác nhưng `layout_hash` giống" **không** được hiểu là "chỉ đổi `hex`" (xem GS-13.9).
- **GS-13.2. Giá trị tham chiếu:** giữ nguyên các hash của F1, F9, F10 trong v0.3.
- **GS-13.3. Các file của một level.** Tất cả nằm trong `progress/`, tên bắt đầu bằng `<level_id>.json`:
  - File chính `<level_id>.json` và bản sao lưu `<level_id>.json.bak`.
  - `<level_id>.json.stale.<UTC>`: file **hợp lệ nhưng không tương thích** (thiếu migration, đổi bố cục, đổi palette chưa được chứng minh). Đổi tên **sau khi** đã chuyển hết `outbox` của nó.
  - `<level_id>.json.corrupt.<UTC>`: file **không đọc được, sai `level_id`, hoặc không qua kiểm tra**.
  - Chỉ đọc file mang đúng tên của level đang mở. **Không bao giờ** đọc, đổi tên hay ghi file của level khác.
  - `.stale` và `.corrupt` không bị xoá tự động trong MVP.
- **GS-13.4. Giai đoạn A: chọn nguồn khôi phục.** Lần lượt thử `[file chính, .bak]`. Mỗi file được xếp vào một loại:
  - `missing`: không tồn tại.
  - `unreadable`: không phải JSON hợp lệ.
  - `wrong_level`: trường `level_id` khác level đang mở.
  - `invalid`: thiếu trường, sai kiểu, bitset sai độ dài, đánh dấu ô `-1`, `selected` ngoài phạm vi, hoặc `outbox` có `event_id` trùng.
  - `ok`: qua hết các kiểm tra trên.
  - Với ba loại `unreadable`, `wrong_level` và `invalid`, file bị đổi tên thành `.corrupt.<UTC>` rồi thử ứng viên kế tiếp. **Không** chuyển dữ liệu `wrong_level` sang level khác.
  - Ứng viên đầu tiên đạt `ok` được đưa sang giai đoạn B, kèm thông tin nguồn là file chính hay `.bak`.
  - Nếu không có ứng viên nào đạt `ok` thì tạo tiến độ mới:
    - Cả hai file đều `missing`: kết quả `fresh_first_play`.
    - Còn lại: kết quả `corrupt_fresh`.
  - Nếu khôi phục từ `.bak`: thao tác cuối và các sự kiện chứa trong file chính hỏng có thể bị mất (giới hạn đã nêu ở GS-12.4). Sau khi khôi phục xong (giai đoạn D), ghi ngay một file chính mới bằng ghi atomic.
- **GS-13.5. Giai đoạn B: phiên bản và migration.**
  - **`save_version`** khác phiên bản hiện tại:
    - Nếu có chuỗi migration định dạng save đã đăng ký thì chạy. Migration phải giữ nguyên `outbox`.
    - Nếu không có: đổi tên ứng viên thành `.stale`, tạo tiến độ mới, kết quả `stale_no_migration`.
  - **`level_schema_version`** khác schema hiện tại: xử lý tương tự, bằng migration schema level.
  - Sau mỗi migration: kiểm tra lại như giai đoạn A. Nếu không qua thì coi như **không có migration** (`.stale`).
- **GS-13.6. Giai đoạn C: kiểm tra tương thích nội dung.** Đi từ trên xuống, dừng ở dòng đầu tiên khớp:

| Điều kiện | Kết quả |
|---|---|
| `layout_hash` khác | `.stale`, tạo tiến độ mới, `stale_layout_changed`. MVP không có migration bố cục |
| `layout_hash` giống, `content_hash` giống | Khôi phục bình thường: `restored` |
| `layout_hash` giống, `content_hash` khác, **thoả GS-13.9** | Giữ tiến độ, thông báo "Màu của tranh vừa được cập nhật": `restored_hex_changed` |
| `layout_hash` giống, `content_hash` khác, **thiếu metadata** để chứng minh (GS-13.9 a–c không thoả) | `.stale`, tạo tiến độ mới: `stale_palette_unverified`. **Không âm thầm khôi phục** |
| Có metadata nhưng không qua phần kiểm tra tự động (GS-13.9 d–e) | `.stale`, tạo tiến độ mới: `stale_palette_rejected` |

- **GS-13.7. Giai đoạn D: áp dụng và kiểm tra sau cùng.**
  - Tính lại `remaining`.
  - Kiểm tra bất biến GS-3.1.
  - Nếu `colors_ever_completed` thiếu màu đang xong: bổ sung, **không** thêm sự kiện.
  - Đặt `last_placed = none`.
  - Nếu có bất kỳ bất biến nào sai: coi ứng viên là `invalid`, đổi tên `.corrupt`, quay lại giai đoạn A với ứng viên kế tiếp.
  - Khôi phục thành công thì: cập nhật `content_version` và `palette_snapshot` theo bản hiện tại, ghi lại file tiến độ, rồi chạy bộ chuyển sự kiện (GS-14.4).
- **GS-13.8. Catalog nội dung.** Siêu dữ liệu này nằm ngoài level, để **không phải đổi schema v1**.
  - File `content/catalog.json` chứa mỗi level một mục:
    - `level_id`, `file`, `content_version` (số nguyên ≥ 1, **tăng ở mọi lần thay đổi** nội dung level);
    - `palette_compat_from` (tuỳ chọn): phiên bản nội dung cũ nhất mà tiến độ của nó còn tương thích khi chỉ chỉnh màu;
    - `layout_hash`, `content_hash` dự kiến.
  - Công cụ nội dung (sẽ làm sau) chỉ được đặt `palette_compat_from` sau khi **tự kiểm tra** rằng `cells` và số màu không đổi so với phiên bản đó, và in ra ΔE00 của từng ID để người duyệt xem.
  - Khi chạy, game từ chối level nếu hash thực tế khác hash trong catalog (`catalog_mismatch`).
  - Nếu `content_hash` đổi mà `content_version` không tăng: ghi log `content_version_not_bumped` và xử lý như **thiếu metadata**.
- **GS-13.9. Điều kiện để kết luận "chỉ đổi màu".** Cần thoả **tất cả**:
  - (a) Sau giai đoạn B, `level_schema_version` và `save_version` giống nhau.
  - (b) `layout_hash` giống nhau.
  - (c) Catalog có `palette_compat_from`, và `palette_compat_from ≤ content_version đã lưu < content_version hiện tại`.
  - (d) `palette_snapshot` có đúng `n` mục; với **mọi** ID: nếu cả bản cũ và bản mới đều có `name` thì hai `name` phải giống nhau, và ΔE00(`hex` cũ, `hex` mới) ≤ `PALETTE_RECOLOR_MAX_DE`.
  - (e) Level mới đã qua toàn bộ kiểm tra dữ liệu ở mục 2.
  - **Giới hạn của chốt chặn này:** điều kiện (d) bắt được việc **tráo nghĩa** giữa các màu khác xa nhau (ví dụ tráo ID 0 và 1 của F1 có ΔE00 = 49,0). Nhưng nó **không** bắt được việc tráo giữa hai màu gần nhau. Trường hợp đó phải dựa vào lời khẳng định trong catalog (c) cùng bước duyệt của công cụ nội dung. Xem rủi ro R-3.
- **GS-13.10. Migration:** giữ nguyên GS-13.4 của v0.3 (danh sách đăng ký, phải có test, kiểm tra lại sau khi chạy). Bổ sung: migration định dạng save phải giữ nguyên `outbox` (cả thứ tự lẫn `event_id`). MVP chưa đăng ký migration nào.
- **GS-13.11. Chuyển `outbox` trước khi đánh dấu `.stale`.** Trước khi đổi tên một ứng viên thành `.stale`, bộ chuyển sự kiện xử lý `outbox` của ứng viên đó trước, vì đó là các sự kiện đã thực sự xảy ra. Với `.corrupt` thì không làm được, nên chấp nhận mất.
- **GS-13.12. Thông báo cho người chơi:**
  - `stale_*`: "Tranh đã được cập nhật, bắt đầu lại".
  - `corrupt_fresh`: "Không đọc được tiến độ cũ, bắt đầu lại".
  - `restored_hex_changed`: "Màu của tranh vừa được cập nhật".

---

## 14. Sự kiện phân tích (thay thế toàn bộ)

- **GS-14.1. Phân loại sự kiện.** Sự kiện là một luồng riêng, không phụ thuộc vào âm thanh hay haptic. Có hai loại:
  - **Bền vững:** gắn với một thay đổi trạng thái đã lưu. Gồm `bead_placed`, `undo_used`, `color_complete`, `level_complete`.
  - **Cố gắng hết sức:** `wrong_tap`, `tap_to_zoom`, `find_used`, `setting_changed`, `level_start`, `restore_result`, `session_end`.
- **GS-14.2. Danh sách sự kiện:** giống v0.3, với hai thay đổi.
  - `restore_result` đổi thành `{source: main|bak|none, main_status, migrations: [...], outcome}`.
    - `main_status` ∈ {`ok`, `missing`, `unreadable`, `wrong_level`, `invalid`}.
    - `outcome` ∈ {`fresh_first_play`, `restored`, `restored_hex_changed`, `stale_no_migration`, `stale_layout_changed`, `stale_palette_unverified`, `stale_palette_rejected`, `corrupt_fresh`}.
  - `color_complete` có thêm trường `occurrence: first | repeat`.
- **GS-14.3. Outbox: cách ghi sự kiện bền vững.**
  - Sự kiện bền vững được thêm vào `outbox` **trong cùng lần ghi atomic** với thay đổi trạng thái sinh ra nó (GS-4.5, GS-12.1).
  - `event_id` được gán **ngay lúc thêm vào outbox**, và được lưu cùng mục đó:
    - Với `level_complete`, `event_id` là giá trị tất định `lc:<install_id>:<level_id>`.
    - Với các sự kiện khác, `event_id` là một UUID.
  - Sự kiện cố gắng hết sức được ghi thẳng vào kho sự kiện, không qua `outbox`. Có thể mất khi app bị dừng, nhưng không bao giờ bị ghi trùng.
- **GS-14.4. Bộ chuyển sự kiện.** Chạy khi app khởi động, sau mỗi lần ghi tiến độ thành công, và trước khi đổi tên một file thành `.stale`. Với từng mục trong `outbox`, theo đúng thứ tự:
  1. Nếu `event_id` **chưa có** trong kho: thêm một dòng vào kho, rồi flush hoặc sync.
  2. Đánh dấu mục đó là đã chuyển (trong bộ nhớ).
  - Các mục đã chuyển được xoá khỏi `outbox` trong **lần ghi tiến độ kế tiếp**. Lần ghi này có thể gộp với lần ghi tiếp theo của gameplay.
- **GS-14.5. Kho sự kiện:** `events/events.jsonl`.
  - Mỗi dòng gồm `{event_id, type, payload, ts, crc32}`, chỉ được thêm vào cuối file.
  - Khi đọc: bỏ qua dòng cuối bị ghi dở và các dòng sai `crc32`, ghi log những dòng bị bỏ.
  - Chỉ mục `event_id` được dựng lại từ các dòng hợp lệ mỗi khi khởi động. Kho chứa **tối đa một bản ghi cho mỗi `event_id`**.
- **GS-14.6. Bảo đảm thực tế** (**không** phải exactly-once):
  - Sự kiện bền vững:
    - Một khi lần ghi tiến độ chứa nó đã ghi xong xuống bộ nhớ, sự kiện được chuyển vào kho **ít nhất một lần**, và kho **khử trùng** theo `event_id`. Kết quả là kho có đúng một bản ghi.
    - **Không có bảo đảm** trong các trường hợp: file tiến độ chứa `outbox` bị hỏng (`.corrupt`); file kho sự kiện bị hỏng hoặc bị xoá; app bị gỡ cài đặt.
  - Sự kiện cố gắng hết sức: có thể mất; không bị trùng.
- **GS-14.7. `level_complete`:**
  - Chỉ được thêm vào `outbox` trong lần ghi làm `completed` chuyển từ false sang true.
  - Không bao giờ được thêm khi khôi phục, khi mở lại level đã xong, hay khi chạy migration.
  - Lớp chống trùng thứ hai là `event_id` tất định.
- **GS-14.8. `color_complete.occurrence`:**
  - Là `first` nếu màu đó chưa có trong `colors_ever_completed` lúc xảy ra; ngược lại là `repeat`.
  - Được xác định và ghi trong cùng lần ghi với thay đổi trạng thái.
  - `repeat` chỉ xảy ra được trong **cùng phiên**, theo chuỗi: hoàn thành màu → Undo hạt cuối của màu đó → đặt lại (GS-10.6).

---

# Test case: các bảng thay thế

**Bộ dữ liệu bổ sung:**
- **F9:** F1 với màu 1 đổi thành `#c9362f` (ΔE00 = 9,5). Catalog **không** có `palette_compat_from`.
- **F9m:** giống F9 về dữ liệu, nhưng catalog có `content_version: 2`, `palette_compat_from: 1` (tiến độ đã lưu ở `content_version 1`).
- **F15:** F1 tráo `hex` của ID 0 và ID 1 (ΔE00 = 49,0). Catalog **có** khẳng định tương thích.
- **F16:** F9m nhưng `name` của ID 1 đổi.
- **F17:** F1 với màu 1 đổi thành `#f2a33a` (ΔE00 = 28,0 > 20). Catalog có khẳng định tương thích.
- **F18:** F1 thêm 1 màu, và có 1 ô đổi sang dùng màu đó.
- **F19:** F9 với `content_version` **không** tăng.
- **G1:** một file tiến độ hợp lệ của **level khác** (`level_id = other_01`).
- **Bộ gây lỗi có chủ đích (chỉ trong build test):** các điểm dừng có tên `CP-1` đến `CP-6` (mô tả ở TC-14.6).

### 4. Luồng màn chơi (sửa)

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-4.6 **[S]** | U | Hoàn thành F1 | Một lần ghi atomic chứa `completed = true` và 3 mục `outbox` (`bead_placed`, `color_complete`, `level_complete`); việc khoá thao tác diễn ra **sau** lần ghi đó | GS-4.5, 14.3 |
| TC-4.7 **[S]** | U | Mở lại level đã xong (`outbox` rỗng) | Không thêm mục nào vào `outbox`; kho sự kiện không có bản ghi mới | GS-4.6, 14.7 |
| TC-4.8 **[M]** | U | Mở lại level đã xong nhưng `outbox` còn `level_complete` chưa chuyển | Bộ chuyển ghi đúng 1 bản ghi; không tạo thêm sự kiện mới | GS-4.6, 14.4 |

### 9. Nút Tìm (sửa)

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-9.4 **[S]** | I | Bấm Tìm từ zoom toàn cảnh → **chờ camera đứng yên** → chạm ô đích | Zoom ≥ 32pt; lần chạm này đặt được hạt | GS-9.2 |
| TC-9.6 **[S]** | I | Bấm Tìm → chạm vào ô đích **trong lúc** hoạt ảnh đang chạy | Hoạt ảnh dừng; **không** đặt hạt; `last_placed` không đổi | GS-9.2, 5.3, 5.11 |
| TC-9.11 **[M]** | I | Tiếp nối TC-9.6: sau khi camera đứng yên, chạm lại cùng ô | Lần này đặt được hạt (một tap mới) | GS-9.2, 5.1d |

### 12. Lưu tiến độ (sửa và bổ sung)

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-12.2 **[S]** | D | **Kiểm thử độ bền:** tắt hẳn app ngay sau hạt thứ 37, lặp 20 lần | **Tiêu chí mục tiêu** theo GS-12.4: ≥ 36 hạt ở mọi lần. Lần nào không đạt thì điều tra và báo cáo, kèm bằng chứng từ TC-12.6, 12.7. Không coi đây là vi phạm một bảo đảm tuyệt đối | GS-12.4 |
| TC-12.6 **[S]** | U | Đặt → ghi → Undo → ghi → đọc lại file | Khớp trạng thái sau Undo; có đủ các trường của GS-12.3 (kể cả `outbox`, `palette_snapshot`, `content_version`) | GS-12.1, 12.3 |
| TC-12.10 **[M]** | U | 20 lần đặt hạt được gộp trong lúc một lần ghi đang chạy | `outbox` có đủ 20 `bead_placed`, đúng thứ tự, không trùng `event_id` | GS-12.1, 14.3, 3.1 |

> TC-12.1, 12.3–12.5, 12.7–12.9 giữ nguyên như v0.3.

### 13. Khôi phục và migration (thay thế toàn bộ)

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-13.1 | U | Tính hash cho F1, F9, F10 bằng Python và Godot | Khớp giá trị tham chiếu | GS-13.1, 13.2 |
| TC-13.2 | U | Tính hash cho F2, F3 bằng Python và Godot | Hai bên giống hệt | GS-13.2 |
| TC-13.3 | U | Đảo thứ tự khoá JSON; viết `hex` chữ hoa | Hash không đổi | GS-13.1 |
| TC-13.4 | U | Hash và catalog khớp hoàn toàn | `restored` | GS-13.6 |
| TC-13.5 **[S]** | U | Tiến độ cũ của F1 (`content_version` 1), mở với **F9m** | `restored_hex_changed`; giữ `placed`; có thông báo; `palette_snapshot` được cập nhật | GS-13.6, 13.9 |
| TC-13.5b **[M]** | U | Tiến độ cũ của F1, mở với **F9** (catalog không có metadata) | `stale_palette_unverified`; tạo tiến độ mới; **không** khôi phục | GS-13.6, 13.9c |
| TC-13.5c **[M]** | U | Mở với **F15** (tráo ánh xạ, catalog vẫn khẳng định tương thích) | `stale_palette_rejected` | GS-13.9d |
| TC-13.5d **[M]** | U | Mở với **F16** (đổi `name`) và với **F17** (ΔE00 = 28) | `stale_palette_rejected` | GS-13.9d |
| TC-13.5e **[M]** | U | Mở với **F19** (`content_version` không tăng) | Có log `content_version_not_bumped`; `stale_palette_unverified` | GS-13.8 |
| TC-13.5f **[M]** | U | `palette_compat_from` lớn hơn `content_version` đã lưu | `stale_palette_unverified` | GS-13.9c |
| TC-13.6 | U | Mở với F10 (đổi `cells`) | `stale_layout_changed` | GS-13.6 |
| TC-13.6b **[M]** | U | Mở với F18 (thêm màu) | `layout_hash` khác vì `n` khác: `stale_layout_changed` | GS-13.1, 13.6 |
| TC-13.6c **[M]** | U | Hash thực tế của level khác hash trong catalog | Level bị từ chối: `catalog_mismatch` | GS-13.8 |
| TC-13.7 | U | F12 có migration mẫu (chỉ trong test) | Migration chạy rồi khôi phục; `outbox` giữ nguyên thứ tự và `event_id` | GS-13.5, 13.10 |
| TC-13.8 | U | F12 không có migration | `stale_no_migration`; `outbox` được chuyển **trước khi** đổi tên | GS-13.5, 13.11 |
| TC-13.9 | U | Có migration nhưng kết quả không qua kiểm tra | Xử lý như không có migration | GS-13.5 |
| TC-13.10 | U | `save_version` cũ, có và không có migration | Hai kết quả tương ứng với TC-13.7 và TC-13.8 | GS-13.5 |
| TC-13.11 **[S]** | U | File chính `unreadable`, `.bak` hợp lệ | File chính thành `.corrupt`; khôi phục từ `.bak` (`source = bak`, `restored`); ghi ngay file chính mới | GS-13.4 |
| TC-13.12 **[S]** | U | Cả file chính và `.bak` đều `unreadable` | Cả hai thành `.corrupt`; `corrupt_fresh`; không crash; cài đặt vẫn còn | GS-13.4, 12.6 |
| TC-13.13 **[S]** | U | File chính hợp lệ nhưng bitset sai độ dài; `.bak` hợp lệ | File chính `invalid` → `.corrupt`; dùng `.bak` | GS-13.4 |
| TC-13.13b **[M]** | U | File chính đánh dấu ô `-1`; `.bak` thiếu | `.corrupt`; `corrupt_fresh` | GS-13.4 |
| TC-13.17 **[M]** | U | File chính **sai `level_id`**, `.bak` hợp lệ đúng level | File chính `wrong_level` → `.corrupt`; khôi phục từ `.bak` | GS-13.4 |
| TC-13.18 **[M]** | U | Cả file chính và `.bak` đều sai `level_id` | Cả hai thành `.corrupt`; `corrupt_fresh` | GS-13.4 |
| TC-13.19 **[M]** | U | File chính hỏng; `.bak` có **nội dung của G1** (level khác); thư mục cũng có file thật của `other_01` | `.bak` → `.corrupt`; `corrupt_fresh`; các file của `other_01` **không đổi một byte** | GS-13.3, 13.4 |
| TC-13.20 **[M]** | U | `.bak` hợp lệ nhưng không tương thích (đổi bố cục) trong khi file chính hỏng | File chính thành `.corrupt`; `.bak` thành `.stale` sau khi đã chuyển `outbox` | GS-13.4, 13.6, 13.11 |
| TC-13.21 **[M]** | U | Ứng viên qua giai đoạn A nhưng sai bất biến ở giai đoạn D | Ứng viên thành `.corrupt`; thử ứng viên kế tiếp | GS-13.7 |
| TC-13.14 | U | Sau khi khôi phục | `remaining` bằng giá trị tính lại; `last_placed = none` | GS-13.7 |
| TC-13.15 | U | Khởi động và lưu nhiều lần khi đã có `.stale` / `.corrupt` | Các file này không bị xoá | GS-13.3 |
| TC-13.16 | U | `colors_ever_completed` thiếu màu đang xong | Được bổ sung; không thêm sự kiện | GS-13.7 |

### 14. Sự kiện (thay thế toàn bộ)

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-14.1 | U | Một phiên chơi F1 có đủ các loại thao tác | Đúng số lượng từng loại sự kiện; sự kiện bền vững đi qua `outbox`; sự kiện cố gắng hết sức ghi thẳng | GS-14.1, 14.2 |
| TC-14.2 **[S]** | U | Hoàn thành F1, khởi động lại 3 lần | Kho có **đúng 1** bản ghi `level_complete` với `event_id = lc:<install_id>:<level_id>` | GS-14.6, 14.7 |
| TC-14.3 **[S]** | U | **Phiên 1:** hoàn thành màu 2 → `color_complete{first}`; Undo **chính hạt cuối** của màu 2 → màu 2 chưa xong; đặt lại → `color_complete{repeat}`. **Tắt app, mở lại:** màu 2 vẫn xong và vẫn có trong `colors_ever_completed`; Undo bị vô hiệu; bấm Undo không làm gì; không có `color_complete` mới | Đúng như mô tả | GS-14.8, 10.6 |
| TC-14.4 | U | Ghi hai lần cùng một `event_id` | Kho có 1 bản ghi | GS-14.5 |
| TC-14.5 **[S]** | U | Chạy từng nhánh của giai đoạn A–D | `restore_result` đúng `source`, `main_status` và `outcome` | GS-14.2 |
| TC-14.6 **[M]** | U | Dừng tại **CP-1**: đã ghi file tạm, chưa đổi tên | Sau khởi động: `completed = false`; kho **không có** `level_complete`. Đặt lại hạt cuối thì kho có đúng 1 bản ghi | GS-4.5, 12.2, 14.6 |
| TC-14.7 **[M]** | U | Dừng tại **CP-2**: đã đổi tên (file tiến độ có `completed` và `outbox`), chưa thêm vào kho | Khi khởi động, bộ chuyển ghi vào kho: đúng 1 bản ghi | GS-14.4, 14.6 |
| TC-14.8 **[M]** | U | Dừng tại **CP-3**: đã thêm và sync vào kho, chưa xoá khỏi `outbox` | Khi khởi động, bộ chuyển thấy `event_id` đã có nên bỏ qua: vẫn đúng 1 bản ghi; `outbox` được dọn | GS-14.4, 14.5 |
| TC-14.9 **[M]** | U | Dừng tại **CP-4**: dòng ghi vào kho bị dở dang | Dòng dở bị bỏ qua; bộ chuyển ghi lại: đúng 1 bản ghi | GS-14.5 |
| TC-14.10 **[M]** | U | Dừng tại **CP-5**: `outbox` đã được dọn | Không có gì thay đổi; vẫn 1 bản ghi | GS-14.4 |
| TC-14.11 **[M]** | U | **CP-6:** xoá file chỉ mục, hoặc giữa file kho có một dòng sai `crc32` | Chỉ mục được dựng lại; vẫn khử trùng đúng; dòng hỏng bị bỏ qua và ghi log; không crash | GS-14.5 |
| TC-14.12 **[M]** | U | File tiến độ có `outbox` chưa chuyển bị chuyển thành `.stale` (đổi bố cục) | Các sự kiện được ghi vào kho **trước khi** đổi tên | GS-13.11, 14.4 |
| TC-14.13 **[M]** | U | Tắt âm thanh và haptic; chơi lại cùng một chuỗi thao tác | Danh sách sự kiện giống hệt (thay cho TC-11.8) | GS-14.1 |
| TC-14.14 **[M]** | U | Sự kiện cố gắng hết sức: dừng app ngay sau một lần chạm sai | Có thể thiếu `wrong_tap`; không bao giờ có hai bản ghi của cùng một sự kiện | GS-14.6 |

> TC-11.8 của v0.3 được **chuyển** thành TC-14.13, vì nó kiểm tra quy tắc GS-14.1.

---

# Ma trận đối chiếu (bản đầy đủ đã rà soát)

| Mục | Quy tắc → test |
|---|---|
| 0.2 | Ràng buộc tham số: TC-5.23 · `PALETTE_RECOLOR_MAX_DE`: TC-13.5d |
| 2 | 2.1: TC-2.1, 2.2 · 2.2: TC-2.3 · 2.3: TC-2.1, 2.4 · 2.4: TC-2.2, 2.5–2.7 · 2.5: TC-2.8, 2.9 · 2.6: TC-2.2, 2.10 · 2.7: TC-2.1, 6.1 |
| 3 | 3.1: TC-2.1, 6.9, 6.10, 12.10 · 3.2: TC-10.6, 10.7 |
| 4 | 4.1: TC-4.1 · 4.2: TC-4.1–4.3 · 4.3: TC-4.4 · 4.4: TC-4.5 · 4.5: TC-4.6, 6.8, 10.5, 14.6 · 4.6: TC-4.7, 4.8 |
| 5 | 5.1: TC-5.1–5.3, 5.5, 5.16, 9.11 · 5.2: TC-5.4 · 5.3: TC-5.6, 5.7, 9.6 · 5.4: TC-5.8, 5.9, 5.14 · 5.5: TC-5.10 · 5.6: TC-5.11 · 5.7: TC-5.12 · 5.8: TC-5.13 · 5.9: TC-5.15 · 5.10: TC-5.17–5.19, 5.21 · 5.11: TC-5.7, 5.20, 9.6, 9.9 · 5.12: TC-5.22 |
| 6 | 6.1: TC-6.1 · 6.2: TC-6.2, 5.10 · 6.3: TC-6.3, 5.15 · 6.4: TC-6.4 · 6.5: TC-6.5 · 6.6: TC-6.2, 11.3 · 6.7: TC-6.6, 10.11 · 6.8: TC-6.7 |
| 7 | 7.1: TC-7.1, 7.2 · 7.2: TC-7.3, 5.22 · 7.3: TC-7.4 · 7.4: TC-7.5 |
| 8 | 8.1–8.3: TC-8.1, 8.2 · 8.4: TC-8.2, 8.3 |
| 9 | 9.1: TC-9.1–9.3 · 9.2: TC-9.4, 9.6, 9.7, 9.11 · 9.3: TC-9.1, 9.10 · 9.4: TC-9.5, 8.3 · 9.5: TC-9.8 · 9.6: TC-9.9 |
| 10 | 10.1: TC-10.2 · 10.2: TC-10.1, 10.5, 4.1 · 10.3: TC-10.1–10.3 · 10.4: TC-10.9 · 10.5: TC-10.4, 6.2, 6.3, 5.17, 9.9, 4.4 · 10.6: TC-10.5–10.8, 14.3, 15.4 · 10.7: TC-10.10, 12.6 · 10.8: TC-10.11 |
| 11 | 11.1: TC-11.1, 10.3 · 11.2: TC-11.2 · 11.3: TC-11.4 · 11.4: TC-6.1, 11.3, 11.5, 11.9 · 11.5: TC-11.6, 11.7, 10.10 · 11.6: TC-11.4 |
| 12 | 12.1: TC-12.1, 12.3–12.6, 12.8, 12.10 · 12.2: TC-12.7, 14.6 · 12.3: TC-12.6 · 12.4: TC-12.1, 12.2 · 12.5: TC-16.1 · 12.6: TC-12.9, 13.12 |
| 13 | 13.1: TC-13.1, 13.3, 13.6b · 13.2: TC-13.1, 13.2 · 13.3: TC-13.15, 13.19 · 13.4: TC-13.11–13.13b, 13.17–13.20 · 13.5: TC-13.7–13.10 · 13.6: TC-13.4–13.6c · 13.7: TC-13.14, 13.16, 13.21 · 13.8: TC-13.5e, 13.6c · 13.9: TC-13.5–13.5f · 13.10: TC-13.7 · 13.11: TC-13.8, 13.20, 14.12 · 13.12: TC-13.5, 13.5b, 13.12 |
| 14 | 14.1: TC-14.1, 14.13 · 14.2: TC-14.1, 14.5, 6.8 · 14.3: TC-4.6, 12.10, 14.1 · 14.4: TC-4.8, 14.7, 14.8, 14.10, 14.12 · 14.5: TC-14.4, 14.8, 14.9, 14.11 · 14.6: TC-14.2, 14.6–14.9, 14.14 · 14.7: TC-4.7, 14.2 · 14.8: TC-14.3, 10.3 |
| 15–16 | 15.1: TC-15.1, 15.2, 6.7 · 15.2: TC-15.3 · 15.3: TC-15.4 · 16.1: TC-16.1 · 16.2: TC-16.2 · 16.3: TC-16.3, 8.3 · 16.4: TC-2.11 |
| 17 | H1–H8: TC-17.1–17.8 |

**Kết quả rà soát:**
- Mọi quy tắc GS đều có ít nhất một test.
- Mọi test đều trỏ tới một quy tắc có thật.
- Không còn test nào trỏ tới `completion_reported` (đã bỏ), tới GS-13.4/13.5 theo nghĩa cũ, hay tới mã TC-11.8 cũ.

---

# Danh sách thay đổi so với v0.3

1. **Hoàn thành tranh và sự kiện:**
   - Bỏ `completion_reported`; thêm `outbox` lưu trong file tiến độ.
   - Thêm kho sự kiện chỉ ghi nối thêm, có `crc32`, khử trùng theo `event_id`.
   - Thêm bộ chuyển sự kiện; `event_id` tất định cho `level_complete`.
   - Tách hai loại sự kiện: bền vững và cố gắng hết sức.
   - Nêu rõ bảo đảm thực tế là **at-least-once kèm khử trùng, không phải exactly-once** (GS-4.5, 4.6, 14.1–14.8).
2. **Hash và palette:**
   - Thêm ghi chú về giới hạn của `layout_hash` (GS-13.1).
   - Thêm catalog nội dung (`content_version`, `palette_compat_from`, hash dự kiến) mà không phải đổi schema v1 (GS-13.8).
   - Thêm 5 điều kiện để kết luận "chỉ đổi màu", có `palette_snapshot` và chốt chặn ΔE00 (GS-13.9).
   - **Thay đổi hành vi:** tranh v1 không có metadata thì **không** tự giữ tiến độ khi đổi màu nữa. Kết quả mới là `stale_palette_unverified`.
3. **TC-14.3** được viết lại đúng chuỗi trong cùng phiên, và có thêm phần kiểm tra sau khi mở lại app. Thêm ghi chú GS-10.6.
4. **Khôi phục file:**
   - Bốn giai đoạn A–D, với năm loại file (`missing`, `unreadable`, `wrong_level`, `invalid`, `ok`).
   - Quy tắc rõ ràng về khi nào dùng `.corrupt`, `.stale`, `.bak`, và khi nào tạo tiến độ mới.
   - Không bao giờ đụng tới file của level khác (GS-13.3–13.7).
5. **Nút Tìm và cử chỉ:** thêm câu vào GS-9.2; sửa TC-9.4 và TC-9.6; thêm TC-9.11.
6. **Tắt app ngay sau thao tác:** TC-12.2 được ghi rõ là kiểm thử độ bền với tiêu chí mục tiêu. Bổ sung GS-12.4: các yêu cầu ghi không được nới lỏng.
7. **Test:**
   - Sửa: TC-4.6, 4.7, 9.4, 9.6, 12.2, 12.6, 13.5, 13.11–13.13, 14.2, 14.3, 14.5.
   - Thêm mới:
     - Luồng màn chơi, Tìm, lưu: TC-4.8, 9.11, 12.10.
     - Palette và catalog: TC-13.5b đến 13.5f, 13.6b, 13.6c.
     - Khôi phục file: TC-13.13b, 13.17–13.21.
     - Sự kiện: TC-14.6–14.14.
   - Chuyển: TC-11.8 thành TC-14.13.
   - Thêm tham số `PALETTE_RECOLOR_MAX_DE`; cập nhật ma trận đối chiếu.

---

# Các mâu thuẫn đã xử lý

| Trong v0.3 | Vấn đề | Cách xử lý ở v0.4 |
|---|---|---|
| GS-4.5 + `completion_reported` | Cờ "đã báo cáo" nằm trong file tiến độ, nhưng sự kiện lại được ghi ở chỗ khác. Nếu app dừng giữa hai lần ghi, sự kiện có thể **mất** (cờ đã bật nhưng sự kiện chưa ghi) hoặc trạng thái không rõ | Dùng `outbox` trong cùng lần ghi atomic, kèm khử trùng ở kho |
| GS-13.3 bước 6 | Coi `layout_hash` giống là "chỉ đổi `hex`". Trường hợp tráo ánh xạ màu sẽ bị khôi phục âm thầm | Bắt buộc có metadata cộng các kiểm tra tự động (GS-13.9) |
| TC-13.5 | Mong đợi `restored_hex_changed` cho F9, một level v1 không có metadata | Tách thành TC-13.5 (dùng F9m) và TC-13.5b (F9 → `stale_palette_unverified`) |
| TC-14.3 | Kịch bản "Undo hạt cuối của màu khác" không bao giờ tạo ra `repeat`, và không khớp GS-10.6 | Viết lại theo chuỗi trong cùng phiên |
| GS-13.3 bước 1–2 | "`level_id` sai thì coi như hỏng (bước 1)" nhưng không nói rõ có thử `.bak` không, và có thể vòng lặp | Giai đoạn A với danh sách ứng viên cố định |
| TC-9.4 | Chạm ngay sau Tìm có thể rơi vào lúc hoạt ảnh đang chạy, mâu thuẫn với GS-9.2 | Chờ camera đứng yên; thêm TC-9.11 |
| TC-11.8 | Kiểm tra GS-14.1 nhưng lại nằm ở mục 11 | Chuyển thành TC-14.13 |
| GS-13.7 (v0.3) | Giữ `completion_reported`, một trường đã bị bỏ | Thay bằng giữ `outbox` (GS-13.10, 13.11) |

---

# Rủi ro còn lại

- **R-1. D-9 bị giới hạn.** Với schema v1 và chưa có catalog, mọi lần đổi màu đều làm người chơi phải **bắt đầu lại**. D-9 chỉ thật sự có hiệu lực khi đã có `content/catalog.json` cùng công cụ đặt `palette_compat_from`. **Cần bạn xác nhận** hướng catalog này, hay muốn thêm metadata trực tiếp vào schema level.
- **R-2. Kho sự kiện là điểm yếu duy nhất.** File `events.jsonl` hỏng hoặc bị xoá thì mất lịch sử sự kiện. MVP chưa có sao lưu riêng cho kho này.
- **R-3. Chốt chặn ΔE00 không bắt được việc tráo hai màu gần nhau.** Trường hợp đó phụ thuộc vào công cụ nội dung (chưa có) và bước duyệt của con người.
- **R-4. Bộ gây lỗi ở các điểm `CP-1` đến `CP-6`** cần hook trong build test của Godot. Hành vi rename và sync thật trên iOS vẫn phải xác minh bằng TC-12.2 và TC-14.6–14.9 chạy trên thiết bị.
- **R-5. File `.stale` và `.corrupt` không bao giờ bị xoá**, nên có thể tích tụ. Sau MVP cần chính sách dọn dẹp, ví dụ giữ 3 bản mới nhất cho mỗi level.
- **R-6. Ghi file sau mỗi hạt kèm `outbox`:** file tiến độ lớn dần cho tới khi bộ chuyển dọn `outbox`. Cần đo ở TC-16.1 (file 1024 ô có kèm `outbox`).
- **R-7. Các rủi ro còn từ v0.3 vẫn giữ nguyên:**
  - Haptic, Reduce Motion và atomic rename trong Godot trên iOS chưa được xác minh.
  - Cả hai level nội bộ đều bắt buộc zoom ở 24pt.
  - Container này không có Mac để chạy các test trên thiết bị (cấp D).
  - Bước 2 vẫn chưa được commit.

---

**Trạng thái repo**, đã kiểm tra thực tế trong lượt này bằng lệnh chỉ đọc:
- HEAD là `8feed74` trên nhánh `claude/cloud-session-connection-check-hksw4v`; không có stash.
- `git status`, hash của phần thay đổi chưa commit và hash của các file chưa được theo dõi đều trùng khớp với mốc đã ghi trước đó.
- Lượt này chỉ tính ΔE00 trong bộ nhớ (cho F9, F15, F17) và không tạo hay sửa file nào trong repo.

Tôi dừng ở đây để bạn duyệt v0.4. Điểm cần bạn quyết sớm nhất là R-1: dùng catalog hay thêm metadata vào schema level.
