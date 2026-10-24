<!-- Lưu trữ nguyên văn bản đặc tả v0.4.1 từ phiên làm việc. Xem docs/spec/README.md để biết cách đọc. -->

# Đặc tả gameplay MVP v0.4.1: các mục sửa

**Phạm vi bản sửa:**
- Chỉ các mục dưới đây thay đổi. Mọi mục khác **giữ nguyên v0.4**.
- **Quyết định kiến trúc (mục 5 của bạn) được giữ:** dùng `content/catalog.json`, giữ schema level v1. Khi thiếu metadata để chứng minh màu tương thích thì vẫn **từ chối** khôi phục tiến độ cũ (`stale_palette_unverified`). Không triển khai công cụ nội dung.

---

## 0.2 Tham số: thêm một dòng

| Tham số | Mặc định | Ghi chú |
|---|---|---|
| `OUTBOX_RETRY_MIN_INTERVAL_S` | 60 giây | Khoảng cách tối thiểu giữa hai lần thử chuyển lại sự kiện trong cùng một phiên (GS-14.9) |

---

## 12. Lưu tiến độ

### GS-12.2 Giao thức ghi và điểm commit (thay thế)

Một lần ghi tiến độ của level `L` gồm các bước sau, thực hiện tuần tự:

1. **Ghi file tạm.** Ghi toàn bộ nội dung vào `L.json.tmp`, sau đó flush và sync file này.
2. **Sao lưu bản cũ (chỉ khi `L.json` đang tồn tại).**
   - Chép `L.json` sang `L.json.bak.tmp`, rồi flush và sync bản chép.
   - Đổi tên `L.json.bak.tmp` thành `L.json.bak`. Lệnh đổi tên này thay thế hẳn `.bak` cũ.
3. **Đổi tên `L.json.tmp` thành `L.json`.** Đây là **điểm commit**.
4. **Sync thư mục** nếu nền tảng hỗ trợ.

**Một lần ghi được xem là đã commit** khi lệnh đổi tên ở bước 3 trả về thành công. Sau thời điểm đó, `L.json` là bản chính thức. Độ bền sau khi mất nguồn còn phụ thuộc vào bước 4 (xem R-8).

**Hệ quả nếu tiến trình bị dừng giữa chừng:**
- Dừng ở bước 1 hoặc bước 2: `L.json` vẫn là bản cũ còn nguyên.
- Dừng sau bước 3: `L.json` là bản mới.
- Không có thời điểm nào thiếu cả `L.json` lẫn `L.json.bak`, trừ trước lần ghi đầu tiên.

**File có thẩm quyền:** chỉ `L.json`, và `L.json.bak` khi được chọn theo GS-13.4. File `.tmp` và `.bak.tmp` **không bao giờ** được dùng làm tiến độ (GS-13.13).

### GS-12.7 Khi ghi thất bại (mới)

- Nếu một lần ghi thất bại (lỗi I/O, đầy bộ nhớ, không có quyền ghi):
  - Trạng thái trong bộ nhớ được giữ nguyên.
  - Việc ghi được thử lại ở lần đặt hạt hoặc Undo kế tiếp, và khi app xuống nền.
  - Mỗi phiên hiện một cảnh báo không chặn: "Chưa lưu được tiến độ".
- Khi ghi thất bại, **không** được xoá hay đổi tên bất kỳ file nào.
- Sự kiện bền vững của các thao tác chưa commit chỉ nằm trong bộ nhớ. Chúng chỉ được bảo đảm sau khi có một lần ghi commit thành công.

---

## 13. Khôi phục

### GS-13.3 Các file của một level (thay thế)

Tất cả nằm trong thư mục `progress/`. Chỉ xét những file có tên bắt đầu bằng `L.json`, với `L` là level đang mở.

| Tên file | Vai trò |
|---|---|
| `L.json` | Bản chính thức |
| `L.json.bak` | Bản sao lưu của lần commit trước |
| `L.json.tmp`, `L.json.bak.tmp` | Chưa commit; không bao giờ là nguồn tiến độ (GS-13.13) |
| `<tên gốc>.stale.<UTC>` | Đã lưu trữ: file hợp lệ nhưng không tương thích, `outbox` đã chuyển hết |
| `<tên gốc>.corrupt.<UTC>` | Đã lưu trữ: file hỏng, `outbox` đã chuyển hết hoặc không chuyển được |
| `<tên gốc>.pending-stale.<UTC>`, `<tên gốc>.pending-corrupt.<UTC>` | Chờ lưu trữ: `outbox` **chưa** chuyển xong (GS-13.11) |
| `<tên gốc>.orphan.<UTC>` | Chỉ có trong bản debug: file tạm còn sót, giữ lại để chẩn đoán |

`<tên gốc>` là `L.json` hoặc `L.json.bak`.

- **Không bao giờ** đọc, đổi tên hay ghi file mang tên của level khác.
- Các file `.stale`, `.corrupt` và `.pending-*` không bị xoá tự động trong MVP.

### GS-13.4 Đánh giá và chọn nguồn khôi phục (thay thế)

- **Bước E0: dọn file tạm** theo GS-13.13.
- **Bước E1: đánh giá ứng viên.** Lần lượt đánh giá `[L.json, L.json.bak]` qua đủ các giai đoạn A → B → C → D.
  - Việc đánh giá **chỉ diễn ra trong bộ nhớ**: không đổi tên, không ghi file, không thêm sự kiện.
  - Mỗi ứng viên nhận **một** kết quả:

| Loại | Kết quả cụ thể | Ý nghĩa |
|---|---|---|
| `restorable` | `restored`, `restored_hex_changed`; có thể kèm migration | Khôi phục được |
| `incompatible` | `stale_no_migration`, `stale_layout_changed`, `stale_palette_unverified`, `stale_palette_rejected` | File hợp lệ, đúng level, nhưng không khôi phục được |
| `broken` | `missing`, `unreadable`, `wrong_level`, `invalid`, `invariant_failed` | File không dùng được |

- **Bước E2: chọn nguồn.**
  - Nguồn là **ứng viên đầu tiên có kết quả `restorable`** theo thứ tự `L.json` rồi `L.json.bak`.
  - Nếu `L.json` có kết quả `incompatible` hoặc `broken`, **vẫn thử tiếp `.bak`**.
  - Chỉ tạo tiến độ mới khi **không còn ứng viên nào** `restorable`.
- **Bước E3: áp dụng.** Thực hiện theo đúng thứ tự:
  1. Lưu trữ mọi ứng viên **không được chọn** theo GS-13.11:
     - ứng viên `incompatible` → lưu trữ dạng stale;
     - ứng viên `broken` → lưu trữ dạng corrupt;
     - ứng viên `missing` → bỏ qua.
     - Nếu bất kỳ bước lưu trữ nào thất bại ở mức không thể đổi tên (GS-13.11 ý 4), **dừng toàn bộ việc khôi phục**: không mở level, không thay đổi thêm file nào, hiện thông báo lỗi lưu trữ.
  2. Nếu có nguồn: áp dụng nguồn đó và ghi ngay một `L.json` mới theo GS-12.2. Bắt buộc ghi khi nguồn là `.bak`, khi có migration, hoặc khi kết quả là `restored_hex_changed`.
     - Nếu nguồn là `.bak` thì nó vẫn được giữ nguyên là `L.json.bak`. Lần ghi đầu tiên chỉ tạo `L.json`, vì lúc đó không còn `L.json` cũ để chép sang `.bak`.
  3. Nếu không có nguồn: tạo tiến độ mới và ghi ngay `L.json` ban đầu.
  4. Chạy bộ chuyển sự kiện cho `outbox` của nguồn (GS-14.4).
- **Khi khôi phục từ `.bak`**, tiến độ có thể lùi lại tối đa một lần commit so với `L.json`. Điều này nằm trong mục tiêu GS-12.4.

### GS-13.6 Giai đoạn C: đổi cách diễn đạt kết quả

- Bảng điều kiện giữ nguyên như v0.4.
- Chỉ đổi phần "kết quả": các dòng trước đây ghi "`.stale`, tạo tiến độ mới" nay ghi **"ứng viên `incompatible` (lý do …)"**.
- Việc đổi tên file và việc tạo tiến độ mới **chỉ** diễn ra ở bước E3.

### GS-13.7 Giai đoạn D: đổi cách diễn đạt kết quả

- Nếu sai bất kỳ bất biến nào, ứng viên nhận kết quả `broken (invariant_failed)`, sau đó **tiếp tục đánh giá ứng viên kế tiếp**.
- Phần còn lại giữ nguyên v0.4.

### GS-13.11 Lưu trữ một ứng viên mà không làm mất sự kiện (thay thế)

1. **Ứng viên nào cần chuyển `outbox` trước khi lưu trữ:**
   - Ứng viên `incompatible`.
   - Ứng viên `broken (invalid | invariant_failed)` **có `outbox` hợp lệ về cấu trúc**: mỗi mục đủ các trường, và `event_id` không trùng nhau.
   - Ứng viên `unreadable` và `wrong_level` **không** được chuyển `outbox`. Lý do: dữ liệu không đọc được, hoặc thuộc level khác. Sự mất mát này đã được ghi nhận ở GS-14.6.
2. **Với các ứng viên ở ý 1:** bộ chuyển ghi từng mục vào kho sự kiện theo GS-14.4.
   - Nếu **mọi** mục đã có trong kho, nghĩa là đã ghi và sync xong, hoặc đã có sẵn từ trước theo `event_id`, thì đổi tên ứng viên thành `.stale.<UTC>` (hoặc `.corrupt.<UTC>`).
3. **Nếu ghi vào kho hoặc sync kho thất bại ở bất kỳ mục nào:**
   - Dừng chuyển tiếp ứng viên này, để giữ đúng thứ tự sự kiện.
   - **Không** đổi tên thành `.stale` hay `.corrupt`.
   - Thay vào đó, đổi tên thành `.pending-stale.<UTC>` (hoặc `.pending-corrupt.<UTC>`). Nội dung file **giữ nguyên**, kể cả `outbox`.
   - Nhờ vậy đường dẫn `L.json` được giải phóng để ghi tiến độ mới, mà các sự kiện chưa chuyển vẫn còn trong một file mà bộ chuyển sẽ quét lại (GS-14.9).
4. **Nếu ngay cả việc đổi tên thành `.pending-*` cũng thất bại:**
   - Dừng khôi phục theo GS-13.4 bước E3.1.
   - Không file nào bị thay đổi thêm.
5. **Ứng viên không cần chuyển `outbox`** (`outbox` rỗng, hoặc thuộc nhóm không chuyển ở ý 1) được đổi tên thẳng thành `.stale` hoặc `.corrupt`.

### GS-13.13 File tạm khi khởi động (mới)

- Ở bước E0, mọi file `L.json.tmp` và `L.json.bak.tmp`:
  - được **xoá** trong bản phát hành;
  - được đổi tên thành `.orphan.<UTC>` trong bản debug.
- File tạm **không bao giờ** được đọc như tiến độ. Quy tắc này vẫn đúng kể cả khi `L.json` hỏng và file tạm trông hợp lệ, hoặc có nội dung mới hơn.
- Thao tác chứa trong file tạm được coi là **chưa từng xảy ra**: không có tiến độ và không có sự kiện tương ứng. Điều này nằm trong mục tiêu GS-12.4.

---

## 14. Sự kiện

### GS-14.2 Sự kiện `restore_result` (thay một trường)

Sự kiện có các trường sau:
- `source`: `main | bak | none`.
- `candidates`: danh sách `[{file, class, result}]`.
- `outcome`: nhận các giá trị như v0.4.
- `archived`: danh sách `[{file, as: stale|corrupt|pending-stale|pending-corrupt}]`.

Trường `main_status` của v0.4 được thay bằng `candidates[0]`.

### GS-14.4 Bộ chuyển sự kiện (thay thế)

- **Khi nào chạy:**
  - khi app khởi động;
  - sau mỗi lần commit tiến độ;
  - khi lưu trữ một ứng viên (GS-13.11);
  - khi quét file chờ lưu trữ (GS-14.9).
- **Cách xử lý:** với từng nguồn `outbox`, xử lý các mục **theo thứ tự**. Với mỗi mục:
  1. Nếu `event_id` đã có trong kho thì coi như đã chuyển.
  2. Nếu chưa có thì thêm một dòng vào kho rồi sync.
  3. Nếu thêm dòng hoặc sync thất bại thì **dừng** xử lý nguồn này. Các mục còn lại được giữ nguyên để thử lại.
- **Dọn `outbox` của `L.json`:** các mục đã chuyển chỉ được xoá khỏi `outbox` qua một lần ghi tiến độ đã commit.
- **`outbox` trong file `.pending-*`:** không bị sửa. File được đổi tên thành `.stale` hoặc `.corrupt` khi mọi mục của nó đã có trong kho.

### GS-14.6 Bảo đảm: bổ sung một câu

> Sự kiện nằm trong một ứng viên đang chờ lưu trữ (`.pending-*`) **không bị mất** khi kho sự kiện tạm thời không ghi được. Chúng được chuyển ở một lần thử lại thành công sau đó (GS-14.9).
>
> Bảo đảm vẫn là **ít nhất một lần chuyển, kèm khử trùng theo `event_id`**. Đây không phải exactly-once.

### GS-14.9 Thử lại với file chờ lưu trữ (mới)

- **Khi nào thử lại:**
  - Bộ chuyển quét `progress/*.pending-*` mỗi khi app khởi động.
  - Bộ chuyển cũng quét sau mỗi lần ghi kho thành công, nhưng không quá một lần mỗi `OUTBOX_RETRY_MIN_INTERVAL_S` trong một phiên.
- **Điều kiện hoàn tất:**
  - Mọi `event_id` trong `outbox` của file đã có trong kho.
  - Khi đó, đổi tên từ `.pending-X.<UTC>` thành `.X.<UTC>` (giữ nguyên dấu thời gian).
- **Khi chưa hoàn tất:** file `.pending-*` được giữ nguyên; không có giới hạn số lần thử lại.
- **Chỉ đọc `outbox`:** file `.pending-*` không bao giờ được dùng làm nguồn tiến độ. Bộ chuyển chỉ đọc phần `outbox` của nó.

---

# Test case: các mục sửa và mới

**Quy ước mới cho nhóm 13 (có hiệu lực từ v0.4.1):** trừ khi test ghi rõ khác, không có file `.bak`. Nhờ vậy các kết quả của TC-13.4 đến 13.10 giữ nguyên ý nghĩa.

### 12. Lưu tiến độ

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-12.7 **[S]** | U | **CP-1a:** dừng khi đang ghi dở `L.json.tmp` | `L.json` còn nguyên bản cũ; file tạm bị xoá khi khởi động; tiến độ là bản cũ | GS-12.2, 13.13 |
| TC-12.11 **[M]** | U | **CP-1:** `L.json.tmp` đã ghi đủ và sync xong, chưa đổi tên | Khởi động: file tạm bị xoá (bản phát hành) hoặc thành `.orphan` (bản debug); tiến độ **là bản cũ**; kho **không** có sự kiện của thao tác này | GS-12.2, 13.13 |
| TC-12.12 **[M]** | U | **CP-1b:** đã đổi `.bak.tmp` thành `.bak`, chưa đổi `L.json.tmp` thành `L.json` | `L.json` là bản cũ, `L.json.bak` cũng là bản cũ; khôi phục bản cũ; file tạm bị dọn | GS-12.2, 13.13 |
| TC-12.13 **[M]** | U | `L.json` hỏng, `L.json.tmp` hợp lệ **và mới hơn**, `.bak` hợp lệ | Dùng `.bak`; file tạm **không** được dùng | GS-13.13, 13.4 |
| TC-12.14 **[M]** | U | Dừng **ngay sau** khi đổi tên `L.json.tmp` thành `L.json` thành công (điểm commit) | Khôi phục bản mới | GS-12.2 |
| TC-12.15 **[M]** | U | Giả lập đầy bộ nhớ khi ghi, sau đó lần ghi kế tiếp thành công | Lần đầu: có cảnh báo, trạng thái trong bộ nhớ giữ nguyên, không file nào bị đổi tên hay xoá. Lần sau: commit đầy đủ, `outbox` đủ mục | GS-12.7 |

### 13. Khôi phục

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-13.22 **[M]** | U | `L.json` hợp lệ nhưng `incompatible` (`save_version` mới hơn, không có migration); `.bak` tương thích | Nguồn là `bak`, kết quả `restored`; `L.json` được lưu trữ dạng stale **sau khi** chuyển `outbox` của nó; ghi `L.json` mới | GS-13.4, 13.11 |
| TC-13.23 **[M]** | U | `L.json` qua giai đoạn A–C nhưng `invariant_failed` ở giai đoạn D; `.bak` tốt | Nguồn là `bak`; `L.json` được lưu trữ dạng corrupt (chuyển `outbox` trước nếu `outbox` hợp lệ) | GS-13.4, 13.7, 13.11 |
| TC-13.24 **[M]** | U | Cả hai ứng viên đều `incompatible` (đổi bố cục) | Cả hai thành `.stale` (`L.json.stale.*` và `L.json.bak.stale.*`), **mỗi file sau khi đã chuyển `outbox` của nó**; tạo tiến độ mới | GS-13.4, 13.11 |
| TC-13.25 **[M]** | U | Như TC-13.22, nhưng `outbox` của `L.json` và `.bak` có chung một `event_id` | Kho có đúng 1 bản ghi của `event_id` đó | GS-13.4, 14.4, 14.5 |
| TC-13.26 **[M]** | U | Dừng tiến trình giữa bước E1 (đang đánh giá) | Không file nào bị đổi tên hay sửa; lần khởi động sau ra cùng kết quả | GS-13.4 |
| TC-13.27 **[M]** | U | `L.json` `incompatible`; `.bak` có nội dung của level khác (G1) | `L.json` → stale; `.bak` → corrupt **không** chuyển `outbox`; tạo tiến độ mới; file của `other_01` không đổi | GS-13.3, 13.4, 13.11 |
| TC-13.20 **[S]** | U | `L.json` `unreadable`; `.bak` hợp lệ nhưng `incompatible` | `L.json` → corrupt (không chuyển `outbox`); `.bak` → stale sau khi chuyển `outbox`; tạo tiến độ mới | GS-13.4, 13.11 |
| TC-13.21 **[S]** | U | Thay bằng TC-13.23 | — | — |

### 14. Sự kiện

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-14.6 **[S]** | U | **CP-1** trong lúc ghi lần hoàn thành tranh (file tạm có `completed` và `level_complete`, chưa đổi tên) | Khởi động: file tạm bị dọn; `completed = false`; kho **không** có `level_complete`. Đặt lại hạt cuối thì kho có đúng 1 bản ghi | GS-4.5, 12.2, 13.13, 14.6 |
| TC-14.15 **[M]** | U | Lưu trữ ứng viên stale có 3 mục `outbox`; **ghi vào kho thất bại** ở mục thứ 2 | Mục 1 có trong kho; ứng viên thành `.pending-stale`; nội dung `outbox` còn đủ 3 mục; tạo tiến độ mới bình thường | GS-13.11, 14.4 |
| TC-14.16 **[M]** | U | Như TC-14.15 nhưng **sync thất bại** ở mục 1 | Không đổi tên thành `.stale`; thành `.pending-stale`; mục 1 được coi là chưa chuyển | GS-13.11, 14.4 |
| TC-14.17 **[M]** | U | Tiếp nối TC-14.15: khởi động lại khi kho đã ghi được | Mục 2 và 3 được chuyển; mục 1 không trùng; file đổi thành `.stale.<UTC>` với cùng dấu thời gian | GS-14.9, 14.5 |
| TC-14.18 **[M]** | U | Kho vẫn lỗi; trong phiên có nhiều lần ghi kho thành công cho sự kiện khác | Mỗi `OUTBOX_RETRY_MIN_INTERVAL_S` chỉ thử lại 1 lần; file `.pending-*` giữ nguyên | GS-14.9 |
| TC-14.19 **[M]** | U | Đổi tên thành `.pending-stale` thất bại | Không mở level; không file nào bị thay đổi; có thông báo lỗi; mở lại sau thì chạy lại đúng quy trình | GS-13.11, 13.4 |
| TC-14.20 **[M]** | U | Ứng viên `invalid` có `outbox` hợp lệ; ứng viên `unreadable` | `invalid`: chuyển `outbox` rồi thành `.corrupt`. `unreadable`: thành `.corrupt` ngay, không chuyển | GS-13.11 |
| TC-14.21 **[M]** | U | File `.pending-*` có `placed` hợp lệ, nhưng không có `L.json` hay `.bak` | Tạo tiến độ mới; **không** dùng file `.pending-*` làm nguồn; chỉ chuyển `outbox` của nó | GS-14.9 |
| TC-14.5 **[S]** | U | Chạy từng nhánh E1–E3 | `restore_result` có đủ `candidates`, `source`, `outcome`, `archived` | GS-14.2 |

---

# Ma trận đối chiếu v0.4.1 (đầy đủ)

| Mục | Quy tắc → test |
|---|---|
| 0.2 | Ràng buộc thứ tự tham số: TC-5.23 · `PALETTE_RECOLOR_MAX_DE`: TC-13.5d · `OUTBOX_RETRY_MIN_INTERVAL_S`: TC-14.18 |
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
| 12 | 12.1: TC-12.1, 12.3–12.6, 12.8, 12.10 · **12.2: TC-12.7, 12.11, 12.12, 12.14, 14.6** · 12.3: TC-12.6 · 12.4: TC-12.1, 12.2 · 12.5: TC-16.1 · 12.6: TC-12.9, 13.12 · **12.7: TC-12.15** |
| 13 | 13.1: TC-13.1, 13.3, 13.6b · 13.2: TC-13.1, 13.2 · **13.3: TC-13.15, 13.19, 13.27** · **13.4: TC-13.11–13.13b, 13.17–13.20, 13.22–13.27, 12.13, 14.19** · 13.5: TC-13.7–13.10 · 13.6: TC-13.4–13.6c · **13.7: TC-13.14, 13.16, 13.23** · 13.8: TC-13.5e, 13.6c · 13.9: TC-13.5–13.5f · 13.10: TC-13.7 · **13.11: TC-13.8, 13.20, 13.22–13.24, 13.27, 14.12, 14.15, 14.16, 14.19, 14.20** · 13.12: TC-13.5, 13.5b, 13.12 · **13.13: TC-12.7, 12.11–12.13, 14.6** |
| 14 | 14.1: TC-14.1, 14.13 · **14.2: TC-14.1, 14.5, 6.8** · 14.3: TC-4.6, 12.10, 14.1 · **14.4: TC-4.8, 13.25, 14.7, 14.8, 14.10, 14.12, 14.15, 14.16** · 14.5: TC-13.25, 14.4, 14.8, 14.9, 14.11, 14.17 · 14.6: TC-14.2, 14.6–14.9, 14.14 · 14.7: TC-4.7, 14.2 · 14.8: TC-14.3, 10.3 · **14.9: TC-14.17, 14.18, 14.21** |
| 15–16 | 15.1: TC-15.1, 15.2, 6.7 · 15.2: TC-15.3 · 15.3: TC-15.4 · 16.1: TC-16.1 · 16.2: TC-16.2 · 16.3: TC-16.3, 8.3 · 16.4: TC-2.11 |
| 17 | H1–H8: TC-17.1–17.8 |

**Kết quả rà soát ma trận:**

- **Mọi quy tắc đều có test**, kể cả ba quy tắc mới: GS-12.7, 13.13, 14.9.
- **Mọi test trỏ tới quy tắc có thật:**
  - TC-13.21 chỉ còn là dòng "thay bằng TC-13.23" và đã được bỏ khỏi ma trận.
  - Không còn tham chiếu nào tới `main_status` hay `completion_reported`.
- **Đã kiểm tra kết quả test khớp với quy tắc**, đặc biệt các test phụ thuộc vào việc "có thử `.bak` không":
  - **TC-13.4 đến 13.10:** khớp, nhờ quy ước "không có `.bak`".
  - **TC-13.11 và 13.13:** `L.json` hỏng nên thử `.bak` → khớp với GS-13.4.
  - **TC-13.20:** sửa phần kết quả mong đợi để mỗi ứng viên được lưu trữ đúng theo GS-13.11.
  - **TC-14.6 (CP-1):** sửa để trỏ tới GS-13.13. File tạm không bao giờ được dùng làm nguồn, nên thao tác trong nó coi như chưa xảy ra.

---

# Danh sách thay đổi so với v0.4

1. **Thứ tự thử ứng viên (GS-13.4, 13.6, 13.7):**
   - Đánh giá **đầy đủ, chỉ trong bộ nhớ** cả `L.json` lẫn `.bak` trước khi đổi tên bất kỳ file nào.
   - Chọn ứng viên `restorable` đầu tiên. `L.json` không tương thích hoặc `invariant_failed` thì **vẫn thử `.bak`**.
   - Chỉ tạo tiến độ mới khi không còn ứng viên nào khôi phục được.
   - Mọi thao tác trên file chỉ diễn ra ở bước E3.
2. **Lưu trữ mà không mất sự kiện (GS-13.11, 14.4, 14.6, 14.9):**
   - Thêm trạng thái chờ lưu trữ `.pending-stale` / `.pending-corrupt` dùng khi ghi hoặc sync kho thất bại.
   - Chỉ được đổi tên thành `.stale` hoặc `.corrupt` khi mọi `event_id` đã có trong kho.
   - Định nghĩa điều kiện thử lại và điều kiện hoàn tất. Không đổi tên được thì dừng khôi phục.
   - Chuyển `outbox` của ứng viên `invalid` hoặc `invariant_failed` nếu `outbox` hợp lệ về cấu trúc.
3. **Ghi atomic và file tạm (GS-12.2, 12.7, 13.13):**
   - Giao thức 4 bước: `.bak` được tạo bằng cách **chép rồi đổi tên**, nên luôn còn `L.json`.
   - Điểm commit là lệnh đổi tên `L.json.tmp` thành `L.json`.
   - File tạm bị xoá khi khởi động (bản phát hành) hoặc giữ thành `.orphan` (bản debug), và **không bao giờ** là nguồn tiến độ.
   - Thêm quy tắc xử lý khi ghi thất bại.
4. **`restore_result`:** thay `main_status` bằng `candidates` và `archived`.
5. **Test:**
   - Mới: TC-12.11–12.15, 13.22–13.27, 14.15–14.21.
   - Sửa: TC-12.7, 13.20, 14.5, 14.6.
   - Bỏ: TC-13.21, thay bằng TC-13.23.
   - Thêm quy ước "không có `.bak`" cho nhóm 13; cập nhật toàn bộ ma trận.
6. **Tham số:** thêm `OUTBOX_RETRY_MIN_INTERVAL_S`.

---

# Rủi ro còn lại

- **R-1 (đã chốt hướng):** chưa có catalog và công cụ nội dung, nên mọi lần đổi màu đều làm người chơi bắt đầu lại. Đây là hành vi có chủ đích theo quyết định của bạn.
- **R-2.** File kho sự kiện hỏng hoặc bị xoá thì mất lịch sử. Sự kiện trong file `unreadable` hoặc `wrong_level` cũng mất. Cả hai đều đã ghi nhận ở GS-14.6.
- **R-3.** Chốt chặn ΔE00 không bắt được việc tráo hai màu gần nhau.
- **R-4.** Các điểm gây lỗi CP-1, CP-1a, CP-1b cần hook trong build test. Hành vi rename và sync trên iOS phải xác minh trên thiết bị.
- **R-5.** File `.stale`, `.corrupt`, `.pending-*` không bao giờ bị xoá, nên tích tụ dần. Cần chính sách dọn sau MVP.
- **R-6.** File tiến độ kèm `outbox` lớn dần nếu kho sự kiện lỗi kéo dài. Cần đo ở TC-16.1.
- **R-7.** Các rủi ro đã nêu ở v0.3 và v0.4 vẫn giữ nguyên:
  - Haptic và Reduce Motion trên Godot iOS chưa được xác minh.
  - Cả hai level nội bộ đều bắt buộc zoom ở 24pt.
  - Container này không có Mac để chạy test trên thiết bị.
  - Bước 2 vẫn chưa được commit.
- **R-8 (mới).** Godot có thể không cho sync thư mục (GS-12.2 bước 4). Khi đó, bước đổi tên trên APFS vẫn là atomic, nhưng có thể chưa ghi bền xuống đĩa nếu mất nguồn ngay sau đó. Hệ quả là lần commit cuối có thể bị mất (vẫn trong mục tiêu GS-12.4). Cần kiểm tra API thực tế, và có thể cần plugin native.
- **R-9 (mới).** Khi `L.json` hợp lệ nhưng `incompatible` mà `.bak` lại tương thích, tiến độ được khôi phục từ `.bak` sẽ **cũ hơn một lần commit**, và người chơi không được báo. Cần bạn quyết định có muốn thêm một thông báo nhẹ cho trường hợp `source = bak` hay không.

---

**Trạng thái repo**, đã kiểm tra thực tế trong lượt này bằng lệnh chỉ đọc:
- HEAD `8feed74` trên nhánh `claude/cloud-session-connection-check-hksw4v`; không có stash.
- `git status`, hash của phần thay đổi chưa commit và hash của các file chưa được theo dõi đều trùng khớp với mốc đã ghi.
- Lượt này không tạo hay sửa file nào trong repo.

Tôi dừng ở đây để bạn duyệt v0.4.1. Điểm cần bạn quyết là R-9.
