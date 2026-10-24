<!-- Lưu trữ nguyên văn bản đặc tả v0.4.4 từ phiên làm việc. Xem docs/spec/README.md để biết cách đọc. -->

# Đặc tả gameplay MVP v0.4.4 (các mục sửa)

**Phạm vi:**
- Chỉ những mục ghi dưới đây thay đổi. Mọi mục khác giữ nguyên v0.4.3.
- Các quyết định KT-1 đến KT-6 giữ nguyên. Trong v0.4.3, KT-1 đến KT-6 là: catalog, schema v1, không khôi phục khi thiếu metadata màu, thông báo khi `source = bak` mà không thêm bộ đếm commit, giao diện `StorageBackend`, và chỉ tuyên bố độ bền đúng với mức của backend.

---

## 0.1 Thuật ngữ (sửa)

| Thuật ngữ | Nghĩa |
|---|---|
| `written` | Mọi lời gọi của thao tác (ghi, flush, close, rename) đều báo thành công. Dữ liệu đã được giao cho hệ điều hành; **không** có bằng chứng là dữ liệu đã nằm trên thiết bị lưu trữ |
| `durable` | Một primitive có **bằng chứng** (GS-12.8, cột "bằng chứng") đã báo thành công cho dữ liệu, và cho cả mục thư mục nếu là thao tác tạo/đổi tên |
| `committed` | Bước 3 của GS-12.2 có `state_after = replaced` (GS-12.8). Luôn ghi kèm mức: `committed@written` hoặc `committed@durable` |
| `confirmed@L` | Trạng thái logic của bộ chuyển sự kiện. Dòng đã đạt mức L do `sync_file` báo về, với L ∈ {`written`, `durable`}, và không có lỗi xen giữa. **Không có `confirmed` nếu không kèm mức** |

**Quy tắc diễn đạt:**
- Không được dùng `confirmed@written` hay `committed@written` để suy ra rằng dữ liệu chịu được mất nguồn.
- Các chữ "synced", "durable", "đã đồng bộ" chỉ được dùng khi kết quả thực sự là `durable`.

---

## 12. Lưu tiến độ

### GS-12.8 Hợp đồng `StorageBackend` (thay phần năng lực và hai thao tác đổi tên)

#### Năng lực `capabilities()`

Mỗi năng lực có hai phần: **giá trị** và **bằng chứng** (`verified` hoặc `assumed`).

| Năng lực | Giá trị có thể có |
|---|---|
| `file_sync` | `written` \| `durable` |
| `dir_sync` | `durable` \| `unsupported` |
| `atomic_replace` | `available` \| `unavailable` |
| `noreplace` | `native` \| `check_then_rename` |

**Cách hiểu cột bằng chứng:**
- **`assumed`:**
  - Hiện thực gọi một primitive mà tài liệu hoặc mã nguồn nói là có tính chất đó, ví dụ `rename(2)` trên POSIX. Nhưng tổ hợp backend + bản Godot + phiên bản iOS lớn **chưa** qua test cấp D tương ứng.
  - Mọi bảo đảm dựa trên năng lực này là **giả định thiết kế**.
- **`verified`:**
  - Build mang theo một **hồ sơ bằng chứng**. Hồ sơ ghi bản Godot, phiên bản iOS lớn, phiên bản backend, các test đã đạt (TC-12.27 và 12.28 cho `atomic_replace`), ngày chạy và thiết bị.
  - `verified` chỉ có nghĩa là **"không thấy vi phạm trong các điều kiện đã thử"**. Nó **không** phải bảo đảm tuyệt đối, và **không** mở rộng sang trường hợp mất nguồn nếu `file_sync`/`dir_sync` không phải `durable`.
- **Thiếu hồ sơ hoặc hồ sơ không khớp tổ hợp đang chạy** → bằng chứng tự động là `assumed`.

#### `rename_replace(src, dst, expected_src_hash)`

- **Mục tiêu.** Khi thành công: `dst` mang nội dung của `src`, và `src` không còn tồn tại.
  - Khi `atomic_replace = available`, hiện thực **nhắm tới** tính chất sau: ở mọi thời điểm, kể cả khi app bị dừng giữa chừng, `dst` hoặc là bản cũ còn nguyên hoặc là bản mới đầy đủ, không bao giờ vắng mặt hay ghi dở.
  - Tính chất này **chỉ đúng tới mức bằng chứng của năng lực**.
- **Khi `atomic_replace = unavailable`:**
  - Ví dụ: hiện thực chỉ làm được bằng cách "xoá đích rồi đổi tên".
  - Thao tác **từ chối**, trả về `err = replace_not_atomic` mà không chạm vào file nào. Không được giả lập âm thầm bằng hai bước.
- **Kết quả trả về:** `{ok, err, state_after}`.
  - `err` ∈ {`src_missing`, `dst_is_dir`, `replace_not_atomic`, `io_failed`, `unknown`}.
  - `state_after` ∈ {`replaced`, `unchanged`, `indeterminate`}.
- **Kiểm tra lại sau lỗi:**
  - Lý do: `DirAccess.rename_absolute` chỉ trả về một mã `Error` chung. Trên Linux, thiếu file nguồn cho ra `1` (ERR_FAILED), không có errno.
  - Vì vậy khi lời gọi báo lỗi, backend kiểm tra lại:
    - `src` còn và `dst` khác `expected_src_hash` → `unchanged`;
    - `src` mất và `dst` có hash = `expected_src_hash` → `replaced`, ghi log `rename_failed_but_replaced`;
    - mọi trường hợp khác → `indeterminate`.
- **Lời gọi báo thành công:** `state_after = replaced`.

#### `rename_noreplace`

- Trả về `err = dst_exists` nếu đích đã tồn tại.
- Với `noreplace = check_then_rename`, tính chất "không ghi đè" dựa vào giả định chỉ có một tiến trình ghi (hàng đợi duy nhất ở GS-12.8).

#### Các thao tác khác

- **`sync_file`:** trả về `written`, `durable` hoặc `failed`.
  - `GodotFileBackend` chỉ trả về `written` (flush + `get_error()` = OK) hoặc `failed`.
- **`sync_dir`:** xem GS-12.11.
- **`verify` (đọc lại):**
  - Chỉ kiểm tra được **lớp `written`**: đọc lại có thể lấy từ bộ đệm của hệ điều hành.
  - Nó phát hiện lỗi ghi ở mức hệ điều hành, **không** chứng minh dữ liệu đã nằm trên thiết bị.

### GS-12.2 và GS-12.7 (sửa theo hợp đồng mới)

**GS-12.2:**
- Bước 2b và bước 3 truyền `expected_src_hash`, là SHA-256 của nội dung vừa ghi.
- **Điểm commit:** bước 3 có `state_after = replaced`, dù lời gọi báo thành công hay báo lỗi.

**GS-12.7, thay các hàng WE-2b và WE-3, thêm ba hàng:**

| Điểm | Kết quả của backend | Xử lý |
|---|---|---|
| WE-2b | `state_after = unchanged` | Như v0.4.2: `.bak` vẫn là N−1 |
| WE-3 | `state_after = unchanged` | Như v0.4.2: `L.json` = N, `.bak` đã bị thay bằng N |
| WE-3r | Báo lỗi nhưng `state_after = replaced` | Coi là đã commit; ghi log; tiếp tục bước 4 |
| WE-3i | `state_after = indeterminate` | **Không** coi là đã commit; hiện cảnh báo "Chưa lưu được tiến độ"; giữ trạng thái trong bộ nhớ; lần ghi sau chạy lại toàn bộ giao thức. Lần khởi động sau, GS-13.4 đánh giá các file đang thực sự có |
| WE-R | `replace_not_atomic` | Không file nào bị chạm. Hiện cảnh báo một lần mỗi phiên. Gameplay tiếp tục với tiến độ chỉ trong bộ nhớ. Ghi log `storage_capability_unavailable`. Đây là tín hiệu không đạt Q1 (GS-12.10) |

### GS-12.9 Tuyên bố độ bền (sửa)

**Mỗi bảo đảm được ghi theo hai trục:**

| | `file_sync`/`dir_sync` = `written` hoặc `unsupported` | = `durable` |
|---|---|---|
| **App bị dừng** | Bất biến GS-12.7, nếu `atomic_replace = available`. Là giả định khi bằng chứng là `assumed`; là "đã thử, không thấy vi phạm" khi là `verified` | Như cột bên trái |
| **Mất nguồn / khởi động lại cưỡng bức** | **Không có bảo đảm.** Chỉ yêu cầu: không crash, `outcome` hợp lệ, có thông báo đúng | Bảo đảm trong giới hạn phần cứng, **chỉ khi** bằng chứng là `verified` |

- Trước khi có hồ sơ bằng chứng, `GodotFileBackend` trên iOS có:
  - `file_sync = written (assumed)`;
  - `dir_sync = unsupported (assumed)`;
  - `atomic_replace = available (assumed)`;
  - `noreplace = check_then_rename (assumed)`.

### GS-12.10 Cổng chọn backend (sửa)

**Q1 và Q2:**

| Mã | Yêu cầu | Test |
|---|---|---|
| Q1 | Chịu được app bị dừng | TC-12.27, 12.28, 12.30 |
| Q2 | Phát hiện được lỗi ghi | TC-12.36 trên thiết bị. TC-12.37 (macOS) là bằng chứng bổ trợ. **Điều kiện tiên quyết:** TC-12.29 (mô phỏng) phải đạt trước |

**Q3:** chỉ để ghi nhận thông tin.

**Khi Q1 hoặc Q2 không đạt, bắt buộc phân loại nguyên nhân trước khi quyết định:**

| Loại | Ví dụ | Hướng xử lý | Có dẫn tới native không |
|---|---|---|---|
| **N1. Lỗi giao thức/logic** | Sai thứ tự bước, dọn nhầm file, lỗi trong GS-13.4, xử lý sai `state_after` | Sửa logic, chạy lại cổng | Không |
| **N2. Dùng sai API** | Không kiểm tra giá trị `bool` của `store_*`, không gọi `get_error()` sau flush/close, sai chế độ mở file | Sửa `GodotFileBackend`, chạy lại | Không |
| **N3. Lỗi khung test** | Hook đặt sai thời điểm, thiết bị bị khoá màn hình hoặc hết pin, dọn dẹp chưa xong từ lần trước | Sửa khung test, chạy lại | Không |
| **N4. Giới hạn của primitive Godot** | API báo thành công trong khi thao tác thực tế thất bại; `rename_absolute` không thay thế atomic; dữ liệu `written` mất sau khi app bị dừng | Thử `verify` trước (với Q2); nếu vẫn không đạt thì xét native | **Có thể**, khi đủ bằng chứng (bên dưới) |
| **N5. Giới hạn của nền tảng** | Hệ điều hành hoặc phần cứng không cung cấp tính chất đó cho bất kỳ API nào | Ghi nhận rủi ro; điều chỉnh tuyên bố ở GS-12.9 | Không, vì native cũng không giải quyết được |

**Chỉ chọn `NativeDurableBackend` khi đủ cả ba điều sau:**
1. Lỗi đã được xếp vào N4, và có **bản tái hiện tối giản** chỉ gọi thẳng API Godot, không có logic game.
2. Có trích dẫn mã nguồn Godot 4.4.1, hoặc có vết system call, chỉ ra lời gọi nào thiếu tính chất cần có.
3. Có **nguyên mẫu native** chạy **cùng bản tái hiện đó trên cùng thiết bị** và đạt.

**Hồ sơ quyết định:** mỗi lần không đạt phải có một hồ sơ gồm `{mã test, lần chạy, loại N1–N5, bằng chứng, cách sửa, kết quả chạy lại}`. Không có hồ sơ thì không được đổi backend.

**Câu chặn:** đặc tả này không tuyên bố bất kỳ API iOS nào đã được kiểm chứng. Mọi năng lực hiện đều ở mức `assumed`.

### GS-12.11 `sync_dir` (mới)

**Kết quả có thể có:**

| Kết quả | Nghĩa | Không được hiểu là |
|---|---|---|
| `durable` | Có primitive kèm bằng chứng, và lời gọi thành công. Các thay đổi mục thư mục trước đó đã được ghi bền | — |
| `unsupported` | Backend không có primitive. **Không có lời gọi nào được thực hiện.** Không nói gì về trạng thái của thư mục | "đã đồng bộ", hay "không cần đồng bộ" |
| `failed` | Có primitive nhưng lời gọi báo lỗi. Các lần đổi tên đã làm vẫn thấy được ở mức `written`; mức bền của chúng không xác định | "đã đồng bộ một phần" |

**Ảnh hưởng tới trạng thái commit:**
- `unsupported` và `failed` **không** huỷ commit, nhưng commit chỉ là `committed@written`.
- Chỉ `durable` (kèm `file_sync = durable`) mới cho ra `committed@durable`.

**Log bắt buộc cho mỗi lần commit:**

```
{op: "commit", level: "written"|"durable", dir_sync: "durable"|"unsupported"|"failed"}
```

**Giới hạn ghi log:**
- `unsupported`: một lần mỗi lần chạy app.
- `failed`: mỗi lần xảy ra, tối đa một lần mỗi phút.
- Không log nào được chứa chữ "synced" hay "durable" khi `dir_sync` khác `durable`.

**Người dùng:** không hiện cảnh báo nào cho `unsupported` hay `failed`, vì commit vẫn thành công.

---

## 13–14. Sự kiện và dọn nguồn

### GS-13.11, GS-13.15, GS-14.4, GS-14.9: điều kiện dọn nguồn (sửa diễn đạt)

**Mọi chỗ trước đây viết "đã xác nhận" hoặc "∈ `confirmed_ids`" nay đọc là `confirmed@L_backend`**, với L_backend là mức `file_sync` của backend đang chạy. Cụ thể:
- GS-13.11 ý 2: đổi ứng viên thành `.stale` hoặc `.corrupt`.
- GS-14.4: dọn `outbox` của `L.json`.
- GS-14.9: đổi tên file `.pending-*`.
- GS-13.15: lưu trữ ứng viên.

**Cách đọc đúng:**
- Việc dọn nguồn **chỉ** dựa trên `confirmed@L_backend`. Nó không bao giờ đòi hỏi `durable`, và cũng không được mô tả như thể dữ liệu đã `durable`.
- Bản thân thao tác dọn nguồn (commit, đổi tên) cũng chỉ đạt cùng mức L_backend.

**Không đổi:** dòng mới khi thử lại, `confirmed_ids` trống khi khởi động, quy tắc "dòng ghi trước một lần sync thất bại không bao giờ được xác nhận", khử trùng bản ghi logic (GS-14.5), và giới hạn tần suất thử lại.

### GS-14.6 Bảo đảm (thay thế bảng)

| Tình huống | `confirmed@written` | `confirmed@durable` (chỉ khi có bằng chứng) |
|---|---|---|
| Lỗi ghi hoặc sync kho | Không mất; thử lại; đúng 1 bản ghi logic | Như cột bên trái |
| App bị dừng | Không mất (giả định, kiểm ở TC-12.27 và 12.30) | Như cột bên trái |
| Mất nguồn / khởi động lại cưỡng bức | **Có thể mất.** Dòng kho và thao tác dọn nguồn đều chỉ ở mức `written`; sau khi mất nguồn, có thể còn thao tác dọn mà mất dòng. **Không có bảo đảm** | Không mất, trong giới hạn phần cứng |
| Nguồn `unreadable`/`wrong_level`, kho bị xoá, gỡ app | Không có bảo đảm | Không có bảo đảm |

- Khử trùng vẫn bảo đảm **không bao giờ có hơn một bản ghi logic**, ở mọi mức.

---

# Test case

## Test sửa

| ID | Thay đổi |
|---|---|
| TC-12.18 | Kết quả mong đợi thêm: `rename_replace` trả về `state_after = unchanged` |
| TC-12.19 | Như TC-12.18 cho WE-3 |
| TC-12.20 | (a) `sync_dir` trả về `failed`; (b) trả về `unsupported`. Cả hai: commit vẫn giữ; log commit có `level=written` và `dir_sync` đúng giá trị; **không** dòng log nào chứa "synced" hay "durable"; không hiện cảnh báo |
| **TC-12.24** | Viết lại, xem bên dưới |
| TC-12.25 | `capabilities()` có đủ bốn năng lực, mỗi năng lực kèm bằng chứng. Thiếu hồ sơ, hoặc hồ sơ không khớp bản Godot hay phiên bản iOS → mọi bằng chứng là `assumed`. Không bao giờ ra `durable (verified)` nếu không có hồ sơ |
| **TC-12.29** | Viết lại thành test mô phỏng (U), xem bên dưới |

## TC-12.24 **[M]** (U): mô phỏng logic bằng mô hình hai lớp

> **Đây là test mô phỏng logic.** Nó kiểm tra đặc tả và mã của ta có xử lý đúng các trạng thái mà mô hình sinh ra hay không. Nó **không** phải bằng chứng về độ bền thực tế. Độ bền thực tế được kiểm riêng ở TC-12.27, 12.28, 12.30, 12.31, 12.36.

**Mô hình** (thuộc `FaultInjectingBackend`) theo dõi riêng hai loại trạng thái:
- **Dữ liệu từng file:** lớp `written` và lớp `durable`.
- **Mục thư mục** (tạo, đổi tên, xoá): lớp `written` và lớp `durable`.

**Các trạng thái trung gian mà mô hình phải sinh ra:**

| Nhóm | Trạng thái |
|---|---|
| Ghi dữ liệu | Sau k byte, với k ∈ {0, 1, giữa, n−1, n}, trong `write_file`, `copy_file`, `append_line` |
| Giữa các lời gọi | Mọi điểm giữa hai lời gọi backend liên tiếp trong GS-12.2, GS-13.15 và GS-14.4 (bao gồm WK-1 đến WK-5 và AK-1 đến AK-3) |
| Rename | Chế độ atomic: một bước duy nhất. Chế độ `non_atomic` (chỉ dùng để thử khả năng chống chịu): tách thành "xoá đích" rồi "liên kết nguồn"; có trạng thái trung gian `dst` vắng mặt |
| Cập nhật thư mục khi mất nguồn | Các thao tác thư mục từ sau lần `sync_dir = durable` gần nhất có thể **đã áp dụng hoặc chưa**. Mô hình liệt kê mọi **tiền tố** của chuỗi thao tác, cộng thêm các hoán vị của hai thao tác cuối |
| Dữ liệu chưa `durable` khi mất nguồn | Bản cũ, rỗng, một tiền tố, hoặc đầy đủ |

**Các trường hợp:**

| Trường hợp | Kết quả mong đợi |
|---|---|
| (a) `crash()` tại mọi điểm ở trên | Giữ đúng các bất biến GS-12.7; kết quả khôi phục đúng bảng WK |
| (b) `power_loss()` với `file_sync = written`, liệt kê đủ các trạng thái ở trên | Không crash; `outcome` thuộc tập đã định nghĩa; thông báo đúng; file tạm không bao giờ được dùng. **Không** kiểm "không mất dữ liệu" |
| (c) Chế độ rename `non_atomic` cùng `crash()` giữa hai bước con | Khôi phục được (từ `.bak` hoặc tạo mới) với thông báo đúng, nghĩa là quy trình khôi phục chịu được cả khi giả định atomic bị sai |
| (d) `power_loss()` với một backend giả lập `durable` | Dữ liệu và mục thư mục đã `durable` thì còn nguyên |

**Ngoài phạm vi mô hình (ghi rõ):** hành vi bộ đệm thật của kernel, phần cứng báo sai về flush, và các trường hợp fsync thất bại rồi mất trang ngoài những gì EA/ES đã mô phỏng.

## TC-12.29 **[S]** (U): tiêm lỗi hết dung lượng qua `FaultInjectingBackend`

| Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|
| Tiêm lỗi `ENOSPC` lần lượt vào: `store_*` trả về `false`; `get_error()` sau flush; close; `copy_file`; `rename_replace`; `append_line`; `sync_file` | Mỗi lỗi được phát hiện **trước** bước 3; trạng thái file đúng hàng WE tương ứng; với kho sự kiện là đúng EA/ES. Khi bật `verify`: lỗi kiểu "báo thành công nhưng nội dung sai" được phát hiện | GS-12.7, 12.8 |

## Test mới

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-12.33 **[M]** | U | `rename_replace` báo lỗi nhưng `dst` đã mang hash mới và `src` đã mất (WE-3r) | `state_after = replaced`; coi là đã commit; có log `rename_failed_but_replaced`; bước 4 vẫn chạy | GS-12.8, 12.7 |
| TC-12.34 **[M]** | U | WE-3i: `state_after = indeterminate`; sau đó khởi động lại | Không coi là đã commit; có cảnh báo; lần ghi sau chạy lại toàn bộ giao thức. Khởi động lại: GS-13.4 cho ra một `outcome` hợp lệ dựa trên các file thật | GS-12.8, 12.7 |
| TC-12.35 **[M]** | U | `atomic_replace = unavailable` (WE-R) | `rename_replace` trả về `replace_not_atomic`; không file nào bị chạm (nhật ký truy cập không có thao tác ghi hay xoá); có cảnh báo; gameplay vẫn chạy; có log `storage_capability_unavailable` | GS-12.8, 12.7 |
| TC-12.36 **[D]** | D | **Hết dung lượng có kiểm soát trên thiết bị** (quy trình ở bảng dưới) | Ghi rõ số lần thử N và số lần bỏ sót. **Tiêu chí:** 0 lần bỏ sót trong N lần thử; `L.json` không bao giờ bị cắt cụt. **Không** kết luận rằng mọi lỗi ghi đều sẽ bị phát hiện. Chỉ cần một lần bỏ sót là phải phân loại theo GS-12.10 | GS-12.10, 12.7 |
| TC-12.37 **[M]** | I (macOS) | Chạy bản export Godot 4.4.1 cho macOS trên một **ảnh đĩa APFS nhỏ** (ví dụ 64 MB, gắn tạm thời), ghi tới khi đầy | Ghi nhận API báo lỗi bằng cách nào. Đây là bằng chứng **macOS/APFS**, không phải iOS. Gỡ ảnh đĩa thì dọn sạch hoàn toàn | GS-12.10 |
| TC-14.31 **[M]** | U | Mô hình: thao tác dọn nguồn dựa trên `confirmed@written`, sau đó `power_loss()`; chạy lại với backend giả lập `durable` | Ở mức `written`: có trạng thái mà sự kiện bị mất, và kết quả này **khớp** với bảng GS-14.6, không bị coi là lỗi. Ở mức `durable`: không mất. Cả hai mức: không bao giờ có hơn một bản ghi logic; quy tắc thử lại không đổi | GS-14.4, 14.6, 13.11, 12.9 |

**Quy trình TC-12.36 (an toàn, kiểm soát được, dọn được):**

| Mục | Quy định |
|---|---|
| Thiết bị | **Chỉ dùng thiết bị dành riêng cho test**, không dùng máy cá nhân. Build test từ chối chạy nếu không có cờ `storage_fill_test` **và** người chạy chưa xác nhận trên màn hình |
| Chỗ chứa dữ liệu đệm | File đệm chỉ được đặt trong `user://ballast/`, tức thư mục sandbox của app |
| Cách làm đầy | Đọc dung lượng trống (qua `DirAccess.get_space_left()`; hành vi trên iOS cần xác minh). Ghi file đệm theo từng khối, cho tới khi lần ghi khối thất bại. Sau đó **ngay lập tức** chạy chuỗi ghi tiến độ và ghi kho đang được kiểm tra |
| Giới hạn thời gian | Thời gian ở trạng thái gần đầy tối đa 60 giây cho mỗi lần thử |
| Dọn dẹp | Xoá `user://ballast/` khi kết thúc mỗi lần thử. Xoá `user://ballast/` **trước mọi việc khác** mỗi khi build test khởi động (phòng trường hợp app bị dừng giữa chừng). Cách cuối cùng: gỡ app sẽ xoá toàn bộ sandbox |
| Ghi nhận | Dung lượng trống trước và sau; lời gọi nào báo lỗi và bằng cách nào; trạng thái file sau lỗi |

---

# Ma trận đối chiếu v0.4.4

Chỉ ghi các dòng thay đổi so với v0.4.3. Các dòng còn lại giữ nguyên.

| Mục | Quy tắc → test |
|---|---|
| 12 | 12.2: TC-12.7, 12.11, 12.12, 12.14, 12.16, 12.19–12.21, 12.27, **12.33, 12.34**, 14.6 · 12.7: TC-12.12, 12.15–12.20, 12.22, 12.24, **12.29, 12.33–12.35**, 13.37, 14.28 · **12.8: TC-12.23, 12.25, 12.29, 12.33–12.37** · **12.9: TC-12.20, 12.24, 12.25, 12.31, 14.31** · **12.10: TC-12.26–12.28, 12.30–12.32, 12.36, 12.37** · **12.11 (mới): TC-12.20, 12.24(d)** |
| 13 | 13.11: TC-13.8, 13.20, 13.22–13.24, 13.27, 13.28, 13.30, 14.12, 14.15, 14.16, 14.19, 14.20, **14.31** |
| 14 | 14.4: thêm **TC-14.31** vào danh sách của v0.4.2 · 14.6: TC-14.2, 14.6–14.9, 14.14, 14.23, 14.24, 12.24, **14.31** |

**Kết quả rà soát ma trận:**
- **Quy tắc mới có test:** GS-12.11 có TC-12.20 và TC-12.24(d).
- **Mọi quy tắc sửa đều có test:** GS-12.2, 12.7, 12.8, 12.9, 12.10, 13.11, 13.15, 14.4, 14.6, 14.9.
- **Mọi test mới hoặc sửa đều trỏ tới quy tắc có thật:** TC-12.18–12.20, 12.24, 12.25, 12.29, 12.33–12.37, 14.31.
- **TC-12.29 giờ là cấp U.** Chỗ của nó trong cổng Q2 được thay bằng TC-12.36; TC-12.29 chỉ còn là điều kiện tiên quyết.
- **Thuật ngữ:** không còn chỗ nào dùng `confirmed` hay `committed` mà không kèm mức.
- **Năng lực:** `dir_sync` không còn giá trị `written`. Chỗ không nhất quán này có trong v0.4.3 và đã được sửa.

---

# Rà soát cuối: phân loại theo mức chắc chắn

**A. Đã rà trên tài liệu đặc tả (phiên này):**
- Đối chiếu chéo GS↔TC theo ma trận ở trên.
- Thuật ngữ `written`, `durable`, `committed@L`, `confirmed@L` được dùng nhất quán trong GS-12.2, 12.7–12.11, 13.11, 13.15, 14.4, 14.6, 14.9.
- KT-1 đến KT-6 không bị thay đổi.

**B. Đã thử trên Linux** (Godot 4.4.1-stable, x86_64 headless, trong container, chỉ chạy trong scratchpad). Đây **không** phải bằng chứng về iOS.
- Lượt trước:
  - `open(WRITE)` dùng `O_TRUNC`;
  - `flush()` chỉ gọi `write()`, không gọi `fsync` hay `fdatasync`;
  - `flush()` trả về `void`; `store_*` trả về `bool`;
  - không có API nào để sync thư mục.
- **Lượt này:**
  - `rename_absolute` lên một file đích đã tồn tại chỉ gọi một lần `rename(2)`, không có `unlink` trước, và nội dung đích được thay đúng;
  - đổi tên khi thiếu file nguồn trả về `1` (ERR_FAILED), tức không có errno. Đây là căn cứ cho bước kiểm tra lại `state_after`.

**C. Giả định thiết kế, chưa được xác minh:**
- Bản iOS của Godot 4.4.1 dùng cùng driver Unix như bản Linux.
- `rename(2)` trên APFS thay thế file đích một cách atomic.
- Dữ liệu ở mức `written` còn nguyên sau khi app bị dừng.
- `get_error()` hoặc giá trị trả về phản ánh lỗi đầy bộ nhớ.
- `DirAccess.get_space_left()` hoạt động trên iOS.
- `OS.crash()` dùng được để giả lập WK.
- Chỉ có một tiến trình ghi.
- Mô hình hai lớp sinh ra đủ các trạng thái cần thiết, trong phạm vi đã ghi rõ.

**D. Phải kiểm chứng trên iOS:** TC-12.1–12.3, 12.26–12.28, 12.30–12.32, 12.36. TC-12.37 kiểm chứng trên macOS.

**Chưa có test nào chạy.** Repo hiện chưa có code Godot, nên mọi TC từ cấp U đến D đều chưa được thực thi. Tôi chỉ chạy hai đoạn probe nói ở mục B.

---

# Danh sách thay đổi so với v0.4.3

1. **GS-12.8:**
   - Năng lực có hai phần, giá trị và bằng chứng (`verified`/`assumed`), kèm hồ sơ bằng chứng.
   - Hợp đồng `rename_replace` có `expected_src_hash`, danh sách `err`, `state_after` và bước kiểm tra lại sau lỗi.
   - Thêm `replace_not_atomic`; không được giả lập âm thầm.
   - Thêm năng lực `noreplace`.
   - Nêu rõ `verify` chỉ kiểm tra được lớp `written`.
   - Bỏ giá trị `written` khỏi `dir_sync`.
2. **GS-12.2 và GS-12.7:** điểm commit dựa vào `state_after`; thêm các hàng WE-3r, WE-3i, WE-R.
3. **GS-12.9:** bảng bảo đảm theo hai trục (loại lỗi × mức), có xét bằng chứng.
4. **GS-12.10:**
   - Phân loại nguyên nhân N1–N5.
   - Ba điều kiện bắt buộc để chọn native: bản tái hiện, trích dẫn hoặc vết system call, nguyên mẫu native đạt.
   - Hồ sơ quyết định.
   - Q2 chuyển sang TC-12.36; câu chặn "không tuyên bố đã kiểm chứng".
5. **GS-12.11 (mới):** các kết quả `durable`, `unsupported`, `failed` của `sync_dir`; ảnh hưởng tới commit; mẫu log; giới hạn tần suất log; các từ bị cấm.
6. **Dọn nguồn sự kiện (GS-13.11, 13.15, 14.4, 14.9):** điều kiện dọn là `confirmed@L_backend`. **GS-14.6:** bảng bảo đảm mới, nêu rõ có thể mất sự kiện khi mất nguồn ở mức `written`. Cơ chế khử trùng và thử lại không đổi.
7. **Test:**
   - **Viết lại:** TC-12.24 (mô phỏng logic, các trạng thái trung gian, a–d, phạm vi ngoài mô hình), TC-12.29 (thành U, tiêm lỗi).
   - **Sửa:** TC-12.18, 12.19, 12.20, 12.25.
   - **Mới:** TC-12.33–12.35 (U), TC-12.36 (D), TC-12.37 (I, macOS), TC-14.31 (U).
   - Không bỏ test nào.

---

# Rủi ro còn lại

- **R-8:** bằng chứng trên Linux cho thấy API Godot không gọi `fsync` và không sync được thư mục. Nếu iOS cũng vậy, MVP chỉ đạt mức `written`, và có thể mất commit hoặc sự kiện khi mất nguồn. Việc này được chấp nhận theo KT-6. Native chỉ được xét khi có nguyên nhân N4 kèm đủ bằng chứng.
- **R-15 (mới):** bước kiểm tra lại sau khi `rename_replace` báo lỗi dựa vào việc đọc lại file, nên có thể kết luận sai nếu chính lệnh đọc cũng lỗi. Trường hợp `indeterminate` được xử lý theo hướng an toàn: không coi là đã commit.
- **R-16 (mới):** TC-12.36 chỉ cho số lần bỏ sót trên N lần thử, không chứng minh được rằng mọi lỗi đều được phát hiện. Ngoài ra cần có thiết bị riêng để test.
- **R-17 (mới):** mô hình hai lớp không bao quát được hành vi bộ đệm thật hay phần cứng báo sai về flush.
- **R-13, R-14:** mô hình chưa chắc khớp hành vi thật; chưa có hiện thực nào, chưa có test nào chạy.
- **R-9:** đã chốt theo KT-4.
- **Giữ nguyên:** R-1 đến R-7, R-10 đến R-12.

---

**Trạng thái repo**, đã kiểm tra thực tế trong lượt này bằng lệnh chỉ đọc:
- HEAD `8feed74` trên nhánh `claude/cloud-session-connection-check-hksw4v`; không có stash.
- `git status`, hash của phần thay đổi chưa commit và hash của các file chưa theo dõi đều trùng mốc đã ghi.
- Probe đổi tên chỉ chạy trong `/tmp/claude-0/-home-user-Qgame/0fb10fa7-097d-5509-a238-153a396e5da7/scratchpad/fsprobe`. Không có file nào trong repo bị tạo hay sửa.

Tôi dừng ở đây để bạn duyệt v0.4.4.
