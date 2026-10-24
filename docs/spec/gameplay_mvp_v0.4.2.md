<!-- Lưu trữ nguyên văn bản đặc tả v0.4.2 từ phiên làm việc. Xem docs/spec/README.md để biết cách đọc. -->

# Đặc tả gameplay MVP v0.4.2: các mục sửa

**Phạm vi:**
- Chỉ những mục ghi dưới đây thay đổi. Mọi mục khác giữ nguyên như v0.4.1.
- Giữ nguyên quyết định kiến trúc: dùng `content/catalog.json`, giữ schema level v1. Khi thiếu metadata để chứng minh màu tương thích thì vẫn từ chối khôi phục (`stale_palette_unverified`).

Tôi đã dò lại toàn bộ văn bản v0.3, v0.4 và v0.4.1 trong transcript để đối chiếu mã GS/TC.

---

## 0. Quy ước chung (mới)

**Ký hiệu phiên bản lưu:**
- **N** là commit đang nằm trong `L.json`.
- **N−1** là commit đang nằm trong `L.json.bak`.
- **N+1** là trạng thái mới đang được ghi.

**Điểm gây lỗi có chủ đích** (chỉ có trong build test; thay cho cách đặt tên CP-1a/CP-1b của v0.4.1):

| Mã | Ý nghĩa | Tên cũ |
|---|---|---|
| `WK-1`…`WK-5` | App bị dừng giữa các bước của GS-12.2 (bảng ở GS-12.7) | CP-1a = WK-1, CP-1 = WK-2, CP-1b = WK-4, CP-2 = WK-5 |
| `WE-1a`…`WE-4` | Một bước của GS-12.2 trả về lỗi | — |
| `EA`, `ES` | Thêm dòng vào kho sự kiện thất bại (`EA`), sync kho thất bại (`ES`) | — |
| `AK-1`…`AK-3` | App bị dừng giữa lúc đang lưu trữ ứng viên (GS-13.15) | — |
| `CP-3`…`CP-6` | Giữ nguyên nghĩa như v0.4 | — |

**Bản ghi logic:**
- Một bản ghi logic ứng với một `event_id` phân biệt (GS-14.5).
- Trong mọi test, câu "kho có N bản ghi" được hiểu là N bản ghi logic. Số dòng vật lý trong file có thể lớn hơn.

---

## 12. Lưu tiến độ

### GS-12.2 Giao thức ghi (giữ như v0.4.1, sửa 3 câu)

- **Bước 1:** mở `L.json.tmp` ở chế độ ghi đè từ đầu. Vì vậy file tạm còn sót lại từ lần trước luôn bị thay.
- **Bước 2:** chép nguyên từng byte của `L.json`. Bước này bị bỏ qua nếu `L.json` không tồn tại.
- **Câu được sửa:** "Không có thời điểm nào thiếu cả `L.json` lẫn `.bak`." Câu này nay có hai ngoại lệ:
  - trước lần ghi đầu tiên;
  - trong khoảng từ lúc lưu trữ ứng viên (GS-13.15) đến lần ghi đầu tiên sau khôi phục.
- Mọi lỗi và mọi điểm dừng được xử lý theo GS-12.7.

### GS-12.7 Lỗi và điểm dừng trong giao thức ghi (thay thế)

**Câu bị rút lại:** v0.4.1 viết "khi ghi thất bại không được xoá hay đổi tên bất kỳ file nào". Câu này **sai** khi lỗi xảy ra sau bước 2b, vì lúc đó `.bak` đã bị thay.

**Lỗi trả về (WE):**

| Điểm | Trạng thái file sau lỗi | File đáng tin | Xử lý |
|---|---|---|---|
| **WE-1a** Ghi `.tmp` lỗi | `L.json` = N và `.bak` = N−1, không đổi byte nào; `.tmp` ghi dở | `L.json`, rồi đến `.bak` | Cố gắng xoá `.tmp`; giữ N+1 trong bộ nhớ; hiện cảnh báo; thử lại sau |
| **WE-1b** Sync `.tmp` lỗi | Như WE-1a; `.tmp` có thể trông đầy đủ | Như WE-1a | Như WE-1a. **Không** đổi tên `.tmp` |
| **WE-2a** Chép hoặc sync `.bak.tmp` lỗi | `L.json` = N, `.bak` = N−1, không đổi; có `.tmp` = N+1 và `.bak.tmp` ghi dở | `L.json`, `.bak` | Xoá `.bak.tmp` và `.tmp`; **không** chạy bước 3, để `.bak` luôn cách `L.json` tối đa 1 commit |
| **WE-2b** Đổi tên `.bak.tmp` thành `.bak` lỗi | Như WE-2a. Lệnh rename là atomic nên `.bak` vẫn là N−1 | `L.json`, `.bak` | Như WE-2a |
| **WE-3** Đổi tên `.tmp` thành `L.json` lỗi | `L.json` = N, không đổi. **`.bak` đã bị thay bằng bản chép của N; N−1 không còn ở đâu cả.** Có `.tmp` = N+1 | `L.json` (N); `.bak` (N, cùng nội dung) | Xoá `.tmp`; hiện cảnh báo; lần sau thử lại toàn bộ quy trình (bước 2 chép lại N, không gây hại). Chấp nhận mất bản dự phòng N−1. Nếu trước đó không có `L.json` thì `L.json` vẫn thiếu và `.bak` không đổi |
| **WE-4** Sync thư mục lỗi hoặc không hỗ trợ | `L.json` = N+1, `.bak` = N | `L.json` | **Đã commit.** Ghi log `dir_sync_failed` hoặc `dir_sync_unsupported` một lần mỗi phiên; không cảnh báo; bộ chuyển sự kiện chạy bình thường. Mất nguồn sau thời điểm này nằm ngoài GS-12.4 |

**App bị dừng (WK):** khởi động lại luôn chạy GS-13.13 trước tiên.

| Điểm | Trạng thái file | Khôi phục |
|---|---|---|
| **WK-1** Giữa bước 1 | N, N−1, `.tmp` ghi dở | Dọn `.tmp`, dùng N |
| **WK-2** Sau bước 1, trước bước 2 | `.tmp` = N+1 đầy đủ | Dọn `.tmp`, dùng N |
| **WK-3** Trong hoặc sau 2a, trước 2b | `.bak.tmp` còn lại; `.bak` = N−1 | Dọn file tạm, dùng N |
| **WK-4** Sau 2b, trước bước 3 | `L.json` = N, `.bak` = N (bản chép), `.tmp` = N+1 | Dọn `.tmp`, dùng N từ file chính |
| **WK-5** Sau bước 3 | `L.json` = N+1, `.bak` = N | Dùng N+1 |

**Bất biến sau mọi điểm lỗi:**
- `L.json`, nếu tồn tại, luôn là một commit hoàn chỉnh.
- `.bak`, nếu tồn tại, là commit liền trước hoặc **cùng** commit với `L.json`.
- File tạm không bao giờ là nguồn tiến độ.
- `L.json` không bao giờ bị thay bởi một lần ghi chưa commit.

**Thử lại:**
- Trạng thái trong bộ nhớ giữ nguyên.
- Thử lại ở lần đặt hạt hoặc Undo kế tiếp, và khi app xuống nền.
- Cảnh báo "Chưa lưu được tiến độ" hiện một lần mỗi phiên.
- Lần ghi thành công chứa toàn bộ trạng thái và `outbox` đã tích luỹ.
- Việc xoá file tạm chỉ là cố gắng. Nếu xoá thất bại thì để GS-13.13 dọn khi khởi động.

**Sự kiện:** mục `outbox` chưa commit không được chuyển vào kho (GS-14.4).

---

## 13. Khôi phục

### GS-13.3 (bổ sung hai ý)

- **Đổi tên lưu trữ không bao giờ ghi đè file đã có.** Nếu tên đích đã tồn tại, thêm hậu tố `-1`, `-2`, … Lý do: rename trên POSIX ghi đè âm thầm, có thể làm mất một file `.pending-*`.
- **Ngoại lệ duy nhất cho quy tắc "không chạm file của level khác"** là bộ chuyển sự kiện ở GS-14.9.
  - Nó chỉ đọc `outbox` của file `.pending-*` và chỉ đổi tên chính file đó.
  - Ngoại lệ này sửa một mâu thuẫn còn tồn tại ở v0.4.1.

### GS-13.4 (sửa bước E2 và E3.1)

**E2, khi không có nguồn nào khôi phục được.** Lấy `outcome` từ ứng viên **không phải `missing` đầu tiên** theo thứ tự:
- ứng viên `broken` → `corrupt_fresh`;
- ứng viên `incompatible` → mã `stale_*` của chính ứng viên đó;
- cả hai đều `missing` → xem GS-13.15 ý 5.

**E3.1.** Thực hiện theo GS-13.15. Nếu một lệnh đổi tên thất bại (kể cả đổi sang `.pending-*`):
- dừng khôi phục, ghi `outcome = archive_failed`, không mở level;
- hiện thông báo lỗi lưu trữ (GS-13.12);
- các lệnh đổi tên đã hoàn tất trước đó **được giữ nguyên, không rollback**;
- file của ứng viên đang xử lý không bị thay đổi;
- kho sự kiện có thể đã có thêm dòng mới.

### GS-13.11 (sửa ý 2 và ý 4)

- **Ý 2.** Chỉ đổi tên thành `.stale` hoặc `.corrupt` khi **mọi** `event_id` trong `outbox` của ứng viên đã nằm trong `confirmed_ids` của phiên hiện tại (GS-14.4). Việc tìm thấy một dòng có sẵn trong file kho là **không đủ**.
- **Ý 4.** Áp dụng như GS-13.4 E3.1 ở trên.

### GS-13.12 (bổ sung)

- `archive_failed`: "Không thể mở tiến độ do lỗi bộ nhớ. Hãy thử lại sau."
- `fresh_after_archive`: "Không khôi phục được tiến độ cũ, bắt đầu lại."
- Thông báo khi khôi phục từ `.bak`: theo GS-13.14.

### GS-13.14 Thông báo khi khôi phục từ `.bak` (mới)

- **Văn bản:** "Đã khôi phục bản lưu gần nhất; một số thao tác gần đây có thể chưa được lưu."
- **Kiểu hiển thị:** giống các thông báo ở GS-13.12, không chặn thao tác, hiện một lần khi level mở xong.
- **Quy tắc hiển thị:** hiện **khi và chỉ khi** lần khôi phục này có `source = bak`. Không hiện khi `source` là `main` hoặc `none`.
- **Căn cứ:**
  - Theo GS-12.2, `.bak` chỉ được tạo bằng cách chép `L.json` ngay trước khi commit một bản mới hơn.
  - Vậy nếu `.bak` tồn tại mà `L.json` bị thiếu hoặc bị loại, thì bản chính trước đó đã chứa một commit **bằng hoặc mới hơn** `.bak`.
  - GS-12.3 không có bộ đếm commit, nên khi `L.json` đã mất hoặc không đọc được thì không phân biệt được "bằng" với "mới hơn".
  - Vì vậy quy tắc nghiêng về an toàn: luôn hiện thông báo.
  - Báo thừa xảy ra được, nhưng chỉ khi đã qua WE-3 hoặc WK-4 rồi `L.json` lại mất (TC-13.37). Văn bản dùng chữ "có thể" để phù hợp với trường hợp này.
- **Khi có cả `restored_hex_changed`:** hiện lần lượt, thông báo `.bak` trước.
- **Khi khôi phục bị gián đoạn trước lúc ghi `L.json` mới:** lần sau vẫn có `source = bak` nên thông báo hiện lại.
- **Khi app dừng trước lúc thông báo kịp hiện mà lần sau có `source = main`:** thông báo bị bỏ lỡ. Chấp nhận (R-9).

### GS-13.15 Lưu trữ nhiều ứng viên bị gián đoạn (mới)

1. **Thứ tự cố định:** `L.json` trước, `L.json.bak` sau. Với mỗi ứng viên: chuyển `outbox` (nếu cần) rồi thực hiện **một** lệnh đổi tên. Lệnh đổi tên là thao tác duy nhất làm thay đổi file ứng viên.
2. **Không rollback:** lệnh đổi tên đã thành công thì giữ nguyên. Dòng đã ghi vào kho cũng giữ nguyên. Không có cơ chế hoàn tác.
3. **Các trạng thái có thể gặp:**

| Điểm | Trạng thái | Lần mở level kế tiếp |
|---|---|---|
| AK-1: đang chuyển `outbox` ứng viên 1 | Không file nào bị đổi tên; kho có thể có thêm dòng | Đánh giá lại từ đầu, ra cùng kết quả |
| AK-2 hoặc lỗi đổi tên ứng viên 2 | Ứng viên 1 đã thành `.stale`, `.corrupt` hoặc `.pending-*`; ứng viên 2 còn nguyên | `L.json` là `missing`; `.bak` được đánh giá lại, cho cùng loại (cùng file, cùng catalog) |
| AK-3: đã lưu trữ xong, chưa ghi `L.json` mới | Nguồn (nếu là `.bak`) còn nguyên | Nguồn `.bak` thì khôi phục lại từ nó; nếu không có nguồn thì theo ý 5 |

4. **Khi khởi động lại:** chạy lại GS-13.4 từ bước E0.
   - Các file `.stale`, `.corrupt`, `.pending-*`, `.orphan` **không bao giờ** là ứng viên.
   - File `.pending-*` được xử lý riêng theo GS-14.9.
5. **Khi cả hai ứng viên đều `missing`:**
   - Nếu thư mục có file lưu trữ của L (`.stale`, `.corrupt` hoặc `.pending-*`; không tính `.orphan`): tạo tiến độ mới, `outcome = fresh_after_archive`.
   - Nếu không có: `fresh_first_play`.
6. **Lỗi đổi tên:** chỉ ảnh hưởng tới level L. Lần mở level kế tiếp sẽ thử lại.

---

## 14. Sự kiện

### GS-14.2 (bổ sung)

`restore_result` thêm các trường và giá trị sau:
- `bak_notice: bool`;
- hai giá trị mới cho `outcome`: `fresh_after_archive` và `archive_failed`.

### GS-14.4 Bộ chuyển sự kiện (thay thế)

**Nguồn sự kiện:**
- (a) `outbox` của `L.json`, nhưng **chỉ các mục đã nằm trong một lần ghi đã commit**;
- (b) `outbox` của ứng viên đang được lưu trữ;
- (c) `outbox` của file `.pending-*`.

**Trạng thái của mỗi mục** (chỉ lưu trong bộ nhớ): chưa ghi → đã ghi nhưng chưa xác nhận → đã xác nhận. Tập `confirmed_ids` **trống mỗi khi app khởi động**.

**Xử lý từng nguồn, theo đúng thứ tự:**
1. `event_id` đã có trong `confirmed_ids` → bỏ qua.
2. Ngược lại → thêm một **dòng mới**, kể cả khi file đã có dòng cùng `event_id`.
3. Sync file kho. Có thể gộp nhiều dòng rồi sync một lần.
4. Sync thành công → xác nhận các dòng đã ghi kể từ lần sync thành công trước đó, **với điều kiện không có lần sync thất bại nào xen giữa**.
5. `EA` hoặc `ES` → dừng nguồn này và mọi nguồn khác trong lượt.
   - Các dòng ghi kể từ lần sync thành công gần nhất **không bao giờ được xác nhận trong phiên này**, kể cả khi một lần sync sau đó thành công.
   - Ở lần thử kế tiếp, các mục đó được ghi lại thành dòng mới.

**Chỉ `confirmed_ids` được dùng** để dọn `outbox` của `L.json` (ở lần commit kế tiếp), đổi tên ứng viên và hoàn tất file `.pending-*`.

**Khi nào chạy:**
- khi khởi động;
- sau mỗi lần commit;
- khi lưu trữ ứng viên;
- khi quét file `.pending-*`.

**Giới hạn thử lại:** sau một lần lỗi kho, các lần chạy do commit kích hoạt cách nhau ít nhất `OUTBOX_RETRY_MIN_INTERVAL_S`.

**Sau khi khởi động lại:**
- Mọi mục còn nằm trong nguồn được ghi lại một lần.
- Dòng trùng được tạo ra có chủ đích; GS-14.5 khử trùng chúng.
- Không sự kiện nào bị coi là đã chuyển chỉ vì tìm thấy dòng của nó trong file.

### GS-14.5 Kho sự kiện (thay thế)

- **Định dạng:** như v0.4.
- **Dòng hợp lệ:** kết thúc bằng `\n`, là JSON đúng và có `crc32` đúng. Dòng không hợp lệ ở bất kỳ vị trí nào đều bị bỏ qua và ghi log.
- **Trước khi thêm dòng:** nếu file không kết thúc bằng `\n` thì ghi `\n` trước.
- **Bản ghi logic:**
  - Dòng hợp lệ **đầu tiên** của mỗi `event_id` là bản ghi; các dòng sau cùng `event_id` là bản trùng.
  - Nếu hai dòng cùng `event_id` có payload khác nhau: ghi log `event_payload_conflict` và giữ dòng đầu.
- **Đọc và xuất kho:** mọi thao tác đọc hoặc xuất kho phải khử trùng theo cách trên.
- **Chỉ mục:** chỉ là bộ đệm để đọc, **không** dùng để kết luận một mục đã được xác nhận.
- **Không sửa dòng cũ:** MVP không xoá và không viết lại dòng nào.

### GS-14.6 Bảo đảm (thay thế)

**Sự kiện bền vững:** kho có ít nhất một dòng hợp lệ và **đúng một bản ghi logic** của sự kiện, khi đủ ba điều kiện:
- (i) lần ghi chứa sự kiện đã commit;
- (ii) nguồn chứa nó còn tồn tại cho tới khi mục được xác nhận;
- (iii) kho cuối cùng ghi và sync được.

**Lỗi ghi hoặc sync kho chỉ làm chậm, không làm mất sự kiện**, vì không nguồn nào bị loại bỏ trước khi được xác nhận.

**Không có bảo đảm khi:**
- nguồn là `unreadable` hoặc `wrong_level`;
- kho bị hỏng hoặc bị xoá sau khi nguồn đã được dọn;
- app bị gỡ;
- sự kiện thuộc một lần ghi chưa commit;
- mất nguồn khi primitive sync của nền tảng không thật sự ghi bền (R-8).

**Sự kiện cố gắng hết sức:** có thể mất. Chúng không bao giờ được ghi lại nên không có dòng trùng.

Mức bảo đảm: **ít nhất một dòng; đúng một bản ghi logic.**

### GS-14.9 File chờ lưu trữ (thay thế)

- **Phạm vi:** các file `*.pending-{stale,corrupt}.<UTC>` của **mọi** level, theo ngoại lệ ở GS-13.3.
- **Khi nào quét:**
  - khi app khởi động;
  - sau mỗi lần **sync kho thành công**, tối đa một lần mỗi `OUTBOX_RETRY_MIN_INTERVAL_S`.
- **Điều kiện hoàn tất:**
  - Mọi `event_id` trong file đã nằm trong `confirmed_ids`.
  - Khi đó đổi tên thành `.X.<UTC>`, giữ nguyên dấu thời gian và áp dụng quy tắc tránh trùng tên.
- **Khi chưa hoàn tất:** giữ nguyên file; không giới hạn số lần thử.
- **Khi file `.pending-*` không còn đọc được:** đổi thành `.corrupt.<UTC>`, ghi log `pending_unreadable`. Phần sự kiện bị mất được chấp nhận theo GS-14.6.
- **Không bao giờ dùng làm tiến độ:** file `.pending-*` không bao giờ là nguồn khôi phục.

---

# Test case

## 12. Lưu tiến độ

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-12.12 **[S]** | U | WK-4 | Byte của `L.json` không đổi (N). **`.bak` đã đổi thành bản chép của N.** Khởi động: dọn `.tmp`, khôi phục N với `source = main`, không có thông báo `.bak` | GS-12.2, 12.7, 13.13 |
| TC-12.13 **[S]** | U | `L.json` hỏng, `.tmp` hợp lệ và mới hơn, `.bak` hợp lệ | Dùng `.bak`, không dùng `.tmp`; **có thông báo GS-13.14** | GS-13.13, 13.4, 13.14 |
| TC-12.15 **[S]** | U | WE-1a (đầy bộ nhớ), sau đó lần ghi kế tiếp thành công | Lần đầu: `L.json` và `.bak` không đổi byte nào; `.tmp` đã xoá hoặc được dọn khi khởi động; có cảnh báo. Lần sau: commit đủ, `outbox` đúng thứ tự | GS-12.7 |
| TC-12.16 **[M]** | U | WE-1b | Như TC-12.15; `.tmp` không bị đổi tên | GS-12.2, 12.7 |
| TC-12.17 **[M]** | U | WE-2a | `L.json` và `.bak` không đổi byte; không còn `.tmp` và `.bak.tmp`; bước 3 không chạy | GS-12.7 |
| TC-12.18 **[M]** | U | WE-2b | `.bak` vẫn là N−1 từng byte; còn lại như TC-12.17 | GS-12.7 |
| TC-12.19 **[M]** | U | WE-3, sau đó (a) khởi động lại ngay; hoặc (b) lần ghi kế tiếp thành công | Sau lỗi: `L.json` = N; **`.bak` đã đổi** thành N; có cảnh báo. (a) Khôi phục N từ file chính, không có thông báo `.bak`. (b) `L.json` = bản mới, `.bak` = N | GS-12.2, 12.7 |
| TC-12.20 **[M]** | U | WE-4, chạy cả trường hợp lỗi và trường hợp không hỗ trợ | Tính là đã commit; log một lần mỗi phiên; không cảnh báo; bộ chuyển sự kiện vẫn chạy | GS-12.2, 12.7 |
| TC-12.21 **[M]** | U | WK-3 | `.bak.tmp` được dọn; `L.json` = N và `.bak` = N−1 không đổi; khôi phục N | GS-12.2, 13.13 |
| TC-12.22 **[M]** | U | Khôi phục từ `.bak`; lần ghi đầu gặp WE-3; khởi động lại | `L.json` vẫn thiếu; `.bak` không đổi; lần sau khôi phục lại từ `.bak` và **thông báo hiện lần nữa** | GS-12.7, 13.4, 13.14 |

## 13. Khôi phục

**Test sửa:**
- TC-13.11, 13.13, 13.17, 13.22, 13.23: bổ sung kỳ vọng "có thông báo GS-13.14, `bak_notice = true`".
- TC-13.20: bổ sung `outcome = corrupt_fresh`.
- TC-13.24: bổ sung `outcome = stale_layout_changed`.

**Test mới:**

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-13.28 **[M]** | U | Cả hai ứng viên đều `incompatible`; `L.json` đã thành `.stale`; đổi tên `.bak` thất bại | `archive_failed`; không mở level; **`L.json.stale.*` vẫn còn**; `.bak` không đổi byte. Mở lại khi hết lỗi: `.bak` được lưu trữ, tạo tiến độ mới với `stale_layout_changed`. Trạng thái cuối giống TC-13.24 | GS-13.4, 13.11, 13.15 |
| TC-13.29 **[M]** | U | `L.json` `incompatible`, `.bak` khôi phục được; dừng tại AK-2 | Khởi động: nguồn là `.bak`; ghi `L.json` mới; có thông báo; file `.stale` còn | GS-13.15, 13.4, 13.14 |
| TC-13.30 **[M]** | U | Kho lỗi: `L.json` thành `.pending-stale`; đổi tên `.bak` thất bại | Dừng như TC-13.28; file `.pending` còn đủ `outbox`. Khi đã hồi phục: file `.pending` thành `.stale` (GS-14.9); `.bak` được xử lý lại | GS-13.11, 13.15, 14.9 |
| TC-13.31 **[M]** | U | Đã có `L.json.stale.<T>`; lưu trữ thêm một file với cùng T (đồng hồ giả lập) | File mới nhận hậu tố `-1`; file cũ không đổi byte | GS-13.3 |
| TC-13.32 **[M]** | U | (a) Thư mục chỉ có các file `.stale`, `.corrupt`, `.pending-*`, `.orphan` của L. (b) Chỉ có `.orphan`. (c) Thư mục trống | (a) Không file nào được dùng làm nguồn; `fresh_after_archive` kèm thông báo. (b) và (c): `fresh_first_play`, không có thông báo | GS-13.15, 13.3, 13.12 |
| TC-13.33 **[M]** | U | AK-1: đã ghi 2/3 mục `outbox` của `L.json` | `L.json` không đổi byte; đánh giá lại ra cùng kết quả; mỗi `event_id` đúng 1 bản ghi logic | GS-13.15, 14.4, 14.5 |
| TC-13.34 **[M]** | I | Khôi phục với `source = bak` | Văn bản đúng; đặt hạt được **trong lúc** thông báo đang hiện; hiện đúng 1 lần; `bak_notice = true` | GS-13.14, 13.12, 14.2 |
| TC-13.35 **[M]** | U | `source = main` (cả `restored`, `restored_hex_changed`, có migration) và `source = none` | Không có thông báo `.bak` | GS-13.14 |
| TC-13.36 **[M]** | U | `L.json` thiếu và không có file lưu trữ; `.bak` khôi phục được | Có thông báo | GS-13.14 |
| TC-13.37 **[M]** | U | WE-3, sau đó làm hỏng `L.json` rồi khởi động | Khôi phục N từ `.bak`; **vẫn có thông báo** (báo thừa được chấp nhận) | GS-13.14, 12.7 |
| TC-13.38 **[M]** | I | `source = bak` cùng với `restored_hex_changed`; sau đó khởi động lại | Hai thông báo hiện lần lượt, thông báo `.bak` trước; lần khởi động sau không hiện lại | GS-13.14, 13.12 |

## 14. Sự kiện

**Quy ước đếm:** TC-4.8, 13.25, 14.2, 14.7, 14.9, 14.10 tính theo bản ghi logic. Kỳ vọng của các test này không đổi.

**Test sửa:**

| ID | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|
| TC-14.4 | Cùng một `event_id`: (a) đưa vào hai lần trong một phiên, sau khi đã xác nhận; (b) qua hai phiên | (a) 1 dòng. (b) Có thể 2 dòng. Cả hai trường hợp: 1 bản ghi logic | GS-14.4, 14.5 |
| TC-14.5 | Chạy các nhánh E1–E3 và GS-13.15 | Có đủ các trường, kể cả `bak_notice` và hai `outcome` mới | GS-14.2 |
| TC-14.8 | CP-3, sau đó khởi động | Mục được **ghi lại** rồi xác nhận; 1 bản ghi logic; `outbox` được dọn ở lần commit sau | GS-14.4, 14.5 |
| TC-14.12 | Ứng viên có `outbox` bị lưu trữ dạng stale | Mọi mục được **xác nhận** trước khi đổi tên | GS-13.11, 14.4 |
| TC-14.15 | EA ở mục 2 | Mục 1 đã xác nhận; file thành `.pending-stale` và còn đủ 3 mục | GS-13.11, 14.4 |
| TC-14.16 | ES ở mục 1 | Dòng của mục 1 có trong file nhưng **chưa xác nhận**; file thành `.pending-stale`; lần sync thành công sau đó trong cùng phiên cũng không xác nhận mục 1 | GS-13.11, 14.4 |
| TC-14.17 | Tiếp nối TC-14.15, khởi động khi kho đã hoạt động | Cả 3 mục được ghi lại và xác nhận (mục 1 có 2 dòng); 1 bản ghi logic cho mỗi mục; file thành `.stale.<T>` với cùng T | GS-14.9, 14.4, 14.5 |
| TC-14.18 | Kho lỗi gián đoạn: có những lần sync thành công cho sự kiện khác | Quét `.pending-*` tối đa 1 lần mỗi `OUTBOX_RETRY_MIN_INTERVAL_S` | GS-14.9 |
| TC-14.19 | Đổi tên ứng viên đầu tiên thành `.pending-stale` thất bại | `archive_failed`; không file tiến độ nào bị đổi tên; kho có thể có thêm dòng; mở lại thì chạy đúng quy trình | GS-13.11, 13.4, 13.15 |

**Test mới:**

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-14.22 **[M]** | U | ES với mục e trong `outbox` của `L.json`; sau đó commit tiếp | e không bị xoá khỏi `outbox`; không bước lưu trữ nào coi e là đã chuyển | GS-14.4 |
| TC-14.23 **[M]** | U | **Ghi dòng e thành công, sync thất bại, dừng app, khởi động lại** | e vẫn còn trong nguồn; được ghi thành dòng mới, sync rồi xác nhận; 1 bản ghi logic; sau đó nguồn mới được dọn hoặc đổi tên | GS-14.4, 14.6, 14.9 |
| TC-14.24 **[M]** | U | Như TC-14.23, nhưng cắt file kho ở giữa dòng e | Dòng ghi dở bị bỏ qua và ghi log; chèn `\n` trước dòng mới; e được ghi lại; không mất sự kiện | GS-14.5, 14.6 |
| TC-14.25 **[M]** | U | ES với e, sau đó lần sync kế tiếp trong cùng phiên thành công | e **không** được xác nhận; e được ghi thành dòng mới ở lần thử sau | GS-14.4 |
| TC-14.26 **[M]** | U | Hai dòng cùng `event_id` nhưng payload khác nhau | Dòng đầu là bản ghi; có log `event_payload_conflict`; dựng lại chỉ mục cho cùng kết quả | GS-14.5 |
| TC-14.27 **[M]** | U | Kho lỗi 3 phút trong lúc đặt hạt 5 lần mỗi giây; sau đó kho hồi phục | Số lần thử tối đa 1 lần mỗi `OUTBOX_RETRY_MIN_INTERVAL_S`; gameplay không bị chặn; sau khi hồi phục, mọi mục được xác nhận đúng thứ tự | GS-14.4, 0.2 |
| TC-14.28 **[M]** | U | WE-1a lặp lại trong khi kho vẫn hoạt động | Mục `outbox` chưa commit **không** được ghi vào kho | GS-14.4, 12.7 |
| TC-14.29 **[M]** | U | Có `other_01.json.pending-stale.<T>` lúc khởi động | File được chuyển `outbox` rồi đổi thành `.stale.<T>`; các file khác của `other_01` không đổi byte; không dùng làm tiến độ | GS-14.9, 13.3 |
| TC-14.30 **[M]** | U | File `.pending-*` không đọc được | File thành `.corrupt.<T>`; có log `pending_unreadable`; không crash | GS-14.9 |

---

# Ma trận đối chiếu v0.4.2

Chỉ ghi các dòng bị ảnh hưởng. Các dòng 2–11 và 15–17 giữ nguyên v0.4.1; không test nào trong các dòng đó bị đổi.

| Mục | Quy tắc → test |
|---|---|
| 0.2 | `OUTBOX_RETRY_MIN_INTERVAL_S`: TC-14.18, 14.27 · các tham số khác như v0.4.1 |
| 12 | 12.1: TC-12.1, 12.3–12.6, 12.8, 12.10 · **12.2: TC-12.7, 12.11, 12.12, 12.14, 12.16, 12.19–12.21, 14.6** · 12.3: TC-12.6 · 12.4: TC-12.1, 12.2 · 12.5: TC-16.1 · 12.6: TC-12.9, 13.12 · **12.7: TC-12.12, 12.15–12.20, 12.22, 13.37, 14.28** |
| 13 | 13.1: TC-13.1, 13.3, 13.6b · 13.2: TC-13.1, 13.2 · **13.3: TC-13.15, 13.19, 13.27, 13.31, 13.32, 14.29** · **13.4: TC-13.11–13.13b, 13.17–13.20, 13.22–13.30, 12.13, 12.22, 14.19** · 13.5: TC-13.7–13.10 · 13.6: TC-13.4–13.6c · 13.7: TC-13.14, 13.16, 13.23 · 13.8: TC-13.5e, 13.6c · 13.9: TC-13.5–13.5f · 13.10: TC-13.7 · **13.11: TC-13.8, 13.20, 13.22–13.24, 13.27, 13.28, 13.30, 14.12, 14.15, 14.16, 14.19, 14.20** · **13.12: TC-13.5, 13.5b, 13.12, 13.32, 13.34, 13.38** · **13.13: TC-12.7, 12.11–12.13, 12.21, 14.6** · **13.14: TC-12.13, 12.22, 13.11, 13.13, 13.17, 13.22, 13.23, 13.29, 13.34–13.38** · **13.15: TC-13.28–13.33, 14.19** |
| 14 | 14.1: TC-14.1, 14.13 · **14.2: TC-14.1, 14.5, 6.8, 13.34** · 14.3: TC-4.6, 12.10, 14.1 · **14.4: TC-4.8, 13.25, 13.33, 14.4, 14.7, 14.8, 14.10, 14.12, 14.15, 14.16, 14.22, 14.23, 14.25, 14.27, 14.28** · **14.5: TC-13.25, 13.33, 14.4, 14.8, 14.9, 14.11, 14.17, 14.24, 14.26** · **14.6: TC-14.2, 14.6–14.9, 14.14, 14.23, 14.24** · 14.7: TC-4.7, 14.2 · 14.8: TC-14.3, 10.3 · **14.9: TC-13.30, 14.17, 14.18, 14.21, 14.23, 14.29, 14.30** |

**Kết quả rà soát:**
- **Mọi quy tắc mới hoặc sửa đều có test:** GS-12.2, 12.7, 13.3, 13.4, 13.11, 13.12, 13.14, 13.15, 14.2, 14.4, 14.5, 14.6, 14.9.
- **Mọi test mới hoặc sửa đều trỏ tới quy tắc có thật.** Các mã tham chiếu cũ (TC-4.8, 6.8, 10.3, 12.9, 13.13b, 16.1, 14.7–14.11) đều có trong v0.3 hoặc v0.4.
- **TC-13.21 đã bị bỏ** và không còn xuất hiện ở đâu.
- **Không còn tham chiếu nào tới CP-1a, CP-1b hay `main_status`.** CP-1 và CP-2 chỉ còn là tên gọi cũ của WK-2 và WK-5.
- **Đã sửa ba mâu thuẫn còn sót từ v0.4.1:**
  - GS-12.7 khẳng định "không file nào thay đổi"; thực tế WE-3 đã thay `.bak`.
  - GS-13.11 và GS-14.4 coi "đã có trong kho" là đã chuyển.
  - GS-14.9 quét file của level khác, trái với GS-13.3.

---

# Danh sách thay đổi so với v0.4.1

1. **Ghi tiến độ:**
   - Bảng lỗi theo từng bước (WE-1a đến WE-4) và theo từng điểm dừng (WK-1 đến WK-5), ghi rõ file nào đáng tin sau mỗi điểm.
   - Nêu đúng việc WE-3 và WK-4 làm `.bak` bị thay.
   - Rút lại câu "không file nào thay đổi".
   - Sửa câu bất biến "không thiếu cả `L.json` lẫn `.bak`".
2. **Kho sự kiện:**
   - Phân biệt dòng "có trong file" với dòng "đã xác nhận" (`confirmed_ids`, trống khi khởi động).
   - Dòng ghi trước một lần sync thất bại không bao giờ được xác nhận.
   - Khi khởi động lại, mọi mục còn trong nguồn được ghi lại.
   - Khử trùng ở mức bản ghi logic; chèn `\n` khi file kết thúc bằng dòng ghi dở.
   - Bộ chuyển chỉ chuyển mục đã commit.
   - Giới hạn tần suất thử lại sau lỗi kho.
3. **Lưu trữ nhiều ứng viên:**
   - Thêm GS-13.15: thứ tự cố định, không rollback, bảng trạng thái AK-1 đến AK-3, quy tắc đánh giá lại khi khởi động.
   - Thêm hai `outcome`: `fresh_after_archive`, `archive_failed`.
   - Thêm quy tắc chọn `outcome` khi không có nguồn.
   - Đổi tên lưu trữ không ghi đè file đã có.
   - Bộ chuyển được phép chạm file `.pending-*` của level khác (ngoại lệ có giới hạn).
4. **Thông báo `.bak`:** thêm GS-13.14 (hiện khi và chỉ khi `source = bak`, kèm căn cứ) và trường `bak_notice`.
5. **Test:**
   - **Mới (26 test):** TC-12.16–12.22; TC-13.28–13.38; TC-14.22–14.30.
   - **Sửa (18 test):** TC-12.12, 12.13, 12.15; TC-13.11, 13.13, 13.17, 13.20, 13.22–13.24; TC-14.4, 14.5, 14.8, 14.12, 14.15–14.19.
   - **Đổi cách đếm theo bản ghi logic, kỳ vọng không đổi:** TC-4.8, 13.25, 14.2, 14.7, 14.9, 14.10.
   - **Bỏ:** không có bỏ mới. TC-13.21 vẫn ở trạng thái đã bỏ.

---

# Rủi ro còn lại

- **R-1 (đã chốt hướng):** chưa có công cụ nội dung, nên mọi lần đổi màu đều buộc người chơi bắt đầu lại.
- **R-2:** kho hỏng hoặc bị xoá sau khi nguồn đã được dọn thì mất lịch sử. Sự kiện trong file `unreadable` hoặc `wrong_level` cũng mất.
- **R-3:** chốt chặn ΔE00 không bắt được việc tráo hai màu gần nhau.
- **R-4:** các điểm WK, WE, EA, ES, AK cần hook trong build test.
- **R-5:** file `.stale`, `.corrupt`, `.pending-*` không bao giờ bị xoá.
- **R-6:** khi kho lỗi kéo dài, `outbox` trong `L.json` phình to, có thể vượt giới hạn 2 ms của GS-12.5. Cần đo ở TC-16.1 và TC-14.27.
- **R-7 (từ v0.3/v0.4):**
  - Haptic và Reduce Motion trên Godot iOS chưa xác minh.
  - Cả hai level nội bộ đều bắt buộc zoom ở 24pt.
  - Không có Mac để chạy test trên thiết bị.
  - Bước 2 vẫn chưa commit.
- **R-8 (mở rộng):** chưa xác minh primitive sync mà Godot cung cấp.
  - Nếu nó chỉ flush bộ đệm phía ứng dụng, chưa phải `fsync`, hoặc không có `F_FULLFSYNC` trên iOS, thì cả "điểm commit" (GS-12.2) lẫn "đã xác nhận" (GS-14.4) chỉ mạnh ngang primitive đó.
  - Có thể cần một GDExtension native.
  - Đây là rủi ro lớn nhất còn lại.
- **R-9 (đã quyết bằng GS-13.14):** còn hai phần dư:
  - báo thừa khi `.bak` cùng commit với bản chính đã mất;
  - bỏ lỡ thông báo nếu app dừng trước khi thông báo kịp hiện.
  - Muốn hết báo thừa thì cần thêm bộ đếm commit vào GS-12.3, tức là đổi `save_version`.
- **R-10 (mới):** việc ghi lại mục khi khởi động sinh dòng trùng. Số dòng trùng bị giới hạn bởi số mục còn trong nguồn ở mỗi lần khởi động. Mọi bên đọc hoặc xuất kho **bắt buộc** khử trùng theo GS-14.5.
- **R-11 (mới):**
  - WE-3 làm mất bản dự phòng N−1.
  - Bước 2 chép `L.json` mà không kiểm tra. Nếu `L.json` bị hỏng trên đĩa giữa phiên, chỗ hỏng lan sang `.bak`.
  - Đề xuất cho sau MVP: trước khi chép, so hash của `L.json` với hash commit cuối giữ trong bộ nhớ.
- **R-12 (mới):** `fresh_after_archive` dựa vào việc có file lưu trữ trong thư mục. Nếu người dùng tự xoá `L.json` và `.bak`, app vẫn hiện thông báo này. Hệ quả vô hại.

---

**Trạng thái repo** (kiểm tra thực tế trong lượt này bằng lệnh chỉ đọc):
- HEAD `8feed74` trên `claude/cloud-session-connection-check-hksw4v`; không có stash.
- `git status`, hash của phần thay đổi chưa commit và hash của các file chưa theo dõi đều trùng mốc đã ghi.
- Lượt này chỉ đọc transcript và tạo một script trích xuất tạm trong scratchpad. Không tạo hay sửa file nào trong repo.

Tôi dừng ở đây để bạn duyệt v0.4.2. Hai điểm cần bạn quyết:
- **R-8:** có chấp nhận dùng native plugin cho sync nếu Godot không đủ không.
- **R-9:** có muốn thêm bộ đếm commit để hết báo thừa, chấp nhận đổi `save_version`, không.
