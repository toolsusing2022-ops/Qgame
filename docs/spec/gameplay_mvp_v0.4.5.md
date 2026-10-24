<!-- Lưu trữ nguyên văn bản đặc tả v0.4.5 từ phiên làm việc. Xem docs/spec/README.md để biết cách đọc. -->

# Đặc tả gameplay MVP v0.4.5 (các mục sửa)

**Phạm vi:**
- Chỉ những mục ghi dưới đây thay đổi; mọi mục khác giữ nguyên v0.4.4.
- KT-1 đến KT-6 giữ nguyên.
- Không đụng tới gameplay hay schema level.

---

## 12. Lưu tiến độ

### GS-12.2 Hash mong đợi của từng bước (bổ sung)

| Ký hiệu | Định nghĩa | Tính từ byte nào |
|---|---|---|
| `B_new`, `H_new` | Nội dung mới sẽ được commit | Đúng dãy byte truyền cho `write_file(L.json.tmp)` ở bước 1, tức chuỗi JSON đã mã hoá UTF-8. `H_new` = SHA-256 của dãy byte đó, tính **trong bộ nhớ, trước khi ghi** |
| `B_old`, `H_bak` | Nội dung được sao lưu | Đúng dãy byte **đọc được từ `L.json`** ở bước 2a; chính dãy byte này được ghi vào `.bak.tmp`. `H_bak` = SHA-256 của dãy byte đó. **Không** dùng hash của commit trước mà app giữ trong bộ nhớ |
| `H_commit` | Hash của commit gần nhất mà app biết | Bằng `H_new` của lần commit gần nhất có `state_after = replaced`. Chỉ dùng cho việc đối soát (bước R bên dưới) |

**Truyền hash mong đợi:**
- Bước 2b: `rename_replace(.bak.tmp, .bak, expected_src_hash = H_bak)`.
- Bước 3: `rename_replace(.tmp, L.json, expected_src_hash = H_new)`.

**Lỗi khi đọc file hoặc tính hash:**
- **Tính `H_new` thất bại** (ví dụ hết bộ nhớ trong): huỷ lần ghi **trước bước 1**. Không file nào bị chạm. Xử lý như WE-1a.
- **Đọc `L.json` thất bại ở bước 2a, hoặc tính `H_bak` thất bại:** huỷ lần ghi trước khi ghi `.bak.tmp`. Xử lý như WE-2a: `L.json` và `.bak` không đổi.
- Nếu `verify` đang bật và việc đọc lại hoặc so hash thất bại, thì đó là lỗi của bước đó (WE-1b hoặc WE-2a).

**Bước R: đối soát trước lần ghi kế tiếp** (bắt buộc sau WE-2b-i và WE-3i). Đọc `L.json` và tính hash `H_disk`:

| Kết quả | Kết luận | Bước 2 có xoay `.bak` không |
|---|---|---|
| R1: `H_disk = H_new` của lần ghi trước | Lần ghi trước **thực ra đã commit**. Ghi log `commit_reconciled`. Đặt `H_commit = H_new` cũ | Có, theo giao thức |
| R2: `H_disk = H_commit` | Lần ghi trước chưa commit | Có, theo giao thức |
| R3: hash khác cả hai, hoặc `L.json` không đọc được hay vắng mặt | Không biết `L.json` đang chứa gì | **Không.** Bỏ qua bước 2 để không ghi đè `.bak` bằng dữ liệu không rõ nguồn gốc; chỉ chạy bước 1 rồi bước 3. Ghi log `reconcile_unknown_main` |

**Ngoại lệ của bất biến** "`.bak` là commit liền trước hoặc cùng commit": sau R3, `.bak` có thể cũ hơn 2 commit trở lên. Trường hợp này được chấp nhận và ghi log.

### GS-12.8 Hợp đồng `rename_replace` (thay thế)

**Gọi hàm:** `rename_replace(src, dst, expected_src_hash) → {ok, err, state_after}`.

**1. Kiểm tra trước (backend tự làm).** Ghi lại `pre_dst`:
- `absent` nếu `dst` chưa tồn tại;
- `hash(dst)` nếu đã tồn tại.

Nếu việc kiểm tra này thất bại thì **không gọi rename**: `err = precheck_failed`, `state_after = unchanged`.

**2. Gọi primitive.** Với `GodotFileBackend`, primitive là `DirAccess.rename_absolute`.

**3. Kiểm tra sau.** Luôn chạy, **kể cả khi lời gọi báo thành công**. Các điều kiện đủ:

| `state_after` | Điều kiện đủ (phải thoả **tất cả**) |
|---|---|
| `replaced` | (i) Một lời gọi kiểm tra tồn tại **thành công** và cho thấy `src` vắng mặt; (ii) đọc được `dst`; (iii) `hash(dst) = expected_src_hash` |
| `unchanged` | (i) `src` tồn tại và `hash(src) = expected_src_hash`; (ii) trạng thái của `dst` khớp `pre_dst`: vắng mặt nếu trước đó vắng mặt, hoặc có hash bằng `pre_dst` |
| `indeterminate` | Mọi trường hợp còn lại, **bao gồm** mọi lỗi khi kiểm tra tồn tại, đọc file hay tính hash trong bước 3. Backend **không suy đoán** |

**Giải thích:**
- Việc `src` còn hay mất được đặt lên trước nội dung `dst`. Nhờ vậy, khi `src` và `dst` cũ có cùng nội dung, kết quả vẫn được phân loại đúng.
- Lời gọi báo thành công nhưng không thoả điều kiện `replaced` → `indeterminate`, kèm log `rename_success_unverified`.
- Lời gọi báo lỗi nhưng thoả điều kiện `replaced` → `replaced`, kèm log `rename_failed_but_replaced`.
- Kiểm tra sau chỉ đọc ở lớp `written` (bộ đệm của hệ điều hành). Nó **không** chứng minh dữ liệu đã `durable`.

**Danh sách `err`:** `src_missing`, `dst_is_dir`, `replace_not_atomic`, `precheck_failed`, `io_failed`, `postcheck_failed`, `unknown`.

**Không thoả được yêu cầu thay thế:**
- Năng lực `atomic_replace = unavailable` → `err = replace_not_atomic`, không gọi primitive, `state_after = unchanged`.
- `src_missing` hoặc `dst_is_dir` được phát hiện ở bước 1 → không gọi primitive, `state_after = unchanged`.

**Tiêu chí bằng chứng cho từng năng lực.** Chỉ chấp nhận bằng chứng chạy trên **chính tổ hợp mục tiêu**: thiết bị iOS thật + bản Godot + phiên bản iOS lớn + phiên bản backend.

| Năng lực | Điều kiện để chuyển từ `assumed` sang `verified` |
|---|---|
| `atomic_replace = available` | Đủ cả bốn: TC-12.26 xác định được primitive mà backend thực sự gọi; **TC-12.39** (hợp đồng rename trên thiết bị), **TC-12.27** và **TC-12.28** cho 0 vi phạm, có ghi số lần thử N; TC-12.38 (U) đạt |
| `file_sync = written` | TC-12.27 và TC-12.30 cho 0 vi phạm trên thiết bị |
| `noreplace = check_then_rename` | Trường hợp (c) của TC-12.39 cho 0 vi phạm. Tính chất này vẫn dựa trên giả định chỉ có một tiến trình ghi, và hồ sơ phải ghi rõ giả định đó |
| `dir_sync = unsupported` | TC-12.26 xác nhận không có primitive nào |
| `file_sync = durable` / `dir_sync = durable` | Xem GS-12.9 |

**Quy tắc chung cho hồ sơ bằng chứng:**
- **Không bao giờ được tính là bằng chứng cho iOS:** kết quả mô phỏng (TC-12.24, 12.29, 12.38, 12.40–12.43), kết quả trên macOS (TC-12.37), kết quả trên Linux.
- **`verified` chỉ có nghĩa là** "không phát hiện vi phạm trong N lần thử, trong các điều kiện đã ghi". Đó không phải bảo đảm tuyệt đối.
- **Hồ sơ bị hạ về `assumed`** khi đổi tổ hợp, hoặc khi phát hiện **bất kỳ** vi phạm nào sau đó. Khi đó phải phân loại theo N1–N5 (GS-12.10).

### GS-12.7 Bảng WE (thay các hàng ở bước 2b và bước 3)

| Điểm | `state_after` | Trạng thái file | Xử lý |
|---|---|---|---|
| WE-2b | `unchanged` (gồm cả `precheck_failed`) | `.bak` = N−1 | Huỷ trước bước 3; dọn file tạm; cảnh báo; thử lại |
| WE-2b-r | `replaced` dù lời gọi báo lỗi | `.bak` = bản sao của N, đúng `H_bak` | Coi bước 2b thành công; tiếp tục bước 3 |
| WE-2b-i | `indeterminate` | `.bak` là N−1, là N, hoặc vắng mặt; chưa rõ | Huỷ trước bước 3; cảnh báo; lần ghi sau chạy bước R |
| WE-3 | `unchanged` (gồm cả `precheck_failed`) | `L.json` = N; `.bak` = N | Như v0.4.2 |
| WE-3r | `replaced` dù lời gọi báo lỗi | `L.json` = `B_new` | **Đã commit**; ghi log; chạy bước 4 |
| WE-3i | `indeterminate`, **kể cả khi lời gọi báo thành công** | `L.json` là N, là `B_new`, hoặc chưa rõ | **Không** coi là đã commit; không chạy bộ chuyển sự kiện cho lần ghi này; cảnh báo; lần ghi sau chạy bước R. Nếu khởi động lại, GS-13.4 đánh giá các file thật |
| WE-R | `replace_not_atomic` | Không file nào bị chạm | Như v0.4.4 |

**Log commit** (GS-12.11): chỉ ghi `{op:"commit", …}` khi `state_after = replaced`. Trường hợp `indeterminate` ghi `{op:"commit_attempt", state_after:"indeterminate"}`.

### GS-12.9 Tuyên bố độ bền và tiêu chí `durable (verified)` (thay thế)

**Hai bộ tiêu chí riêng biệt:**

| Tiêu chí | Năng lực cần có | Bằng chứng tối thiểu |
|---|---|---|
| **Chịu được app bị dừng** | `atomic_replace = available (verified)` và `file_sync = written (verified)` | Như bảng ở GS-12.8 |
| **Chịu được mất nguồn** | `file_sync = durable (verified)`, cộng thêm `dir_sync = durable (verified)` cho các thao tác tạo hay đổi tên | Đủ cả ba điều kiện D1–D3 dưới đây |

**Điều kiện để đặt `durable (verified)` trên iOS:**
- **D1. Tài liệu nhà cung cấp.** Tài liệu chính thức của Apple mô tả primitive đó đưa dữ liệu (hoặc mục thư mục) tới bộ nhớ lâu dài. Ví dụ, sẽ cần đọc mô tả của `F_FULLFSYNC`; **chưa đọc trong phiên này**.
- **D2. Bằng chứng backend thực sự gọi primitive đó trên thiết bị.** Có nhật ký lời gọi do backend ghi, kèm mã trả về; mã nguồn đã được rà.
- **D3. Một phương pháp thử mất nguồn hoặc tắt máy không sạch trên thiết bị iOS thật.** Phương pháp phải tái tạo được việc mất dữ liệu chưa ghi bền. Ở mức đối chứng, nó **phải cho thấy mất dữ liệu** khi chỉ dùng mức `written`. Sau đó phải cho 0 vi phạm trong N lần thử với primitive đang được kiểm tra.

**Hiện trạng:**
- Chưa có phương pháp nào thoả D3. TC-12.31 (khởi động lại cưỡng bức) **chưa được chứng minh** là tương đương mất nguồn. Nếu thử đối chứng mà không gây mất dữ liệu nào, thì TC-12.31 **không** đủ cho D3.
- Vì vậy, khi chưa có D3:
  - `file_sync` và `dir_sync` **không được** đặt `durable (verified)`;
  - một backend native có gọi `F_FULLFSYNC` thì tối đa là `durable (assumed)`;
  - `durable (assumed)` được **coi như `written`** khi tuyên bố bảo đảm.
- `GodotFileBackend` giữ nguyên: `file_sync = written (assumed)`, `dir_sync = unsupported (assumed)`.

**Bảng bảo đảm (thay bảng v0.4.4):**

| | Không có `durable (verified)` | Có `durable (verified)` |
|---|---|---|
| **App bị dừng** | Bất biến GS-12.7. Là "đã thử, không thấy vi phạm" nếu tiêu chí chịu dừng đã `verified`; ngược lại là giả định | Như cột bên trái |
| **Mất nguồn** | Không có bảo đảm; chỉ yêu cầu không crash và `outcome` hợp lệ | Không phát hiện vi phạm trong các điều kiện đã thử ở D3 |

### GS-12.10 Cổng chọn backend (sửa)

**Q1 (chịu được app bị dừng):** TC-12.27, 12.28, 12.30 và **12.39**.

**Q2 (phát hiện lỗi ghi):** TC-12.36. **Điều kiện tiên quyết:** TC-12.29 phải đạt **từng nhóm** của nó.

**Q3:** chỉ để ghi nhận thông tin. Việc nâng lên mức `durable` theo GS-12.9 **không** phải một cổng của MVP.

Phân loại N1–N5, ba điều kiện để chọn native và hồ sơ quyết định giữ nguyên v0.4.4.

**Bổ sung:**
- Khi xét theo điều kiện số 3 (có nguyên mẫu native đạt), nguyên mẫu đó cũng chỉ được ghi nhận ở mức bằng chứng mà nó thực sự đạt. Không được tự gán `durable (verified)` cho nó.

---

## 14. Sự kiện

### GS-14.6 Phạm vi bảo đảm (thay câu "không mất")

**Câu "sự kiện bền vững không bị mất" chỉ áp dụng khi thoả cả năm điều kiện:**
- (a) Lần ghi chứa sự kiện đã **commit** (`state_after = replaced`).
- (b) Nguồn chứa sự kiện vẫn **tồn tại và đọc được**: `outbox` của `L.json`, ứng viên đang được lưu trữ, hoặc file `.pending-*`.
- (c) Nguồn **chưa bị dọn**. Theo GS-14.4, nguồn chỉ được dọn sau khi có `confirmed@L_backend`.
- (d) App **có thể tiếp tục chạy**, hoặc được mở lại, cho tới khi kho ghi và sync được.
- (e) File kho không bị xoá hay hỏng sau khi nguồn đã được dọn.

**Khi thiếu một trong các điều kiện trên: không có bảo đảm.**

**Bảng theo mức của backend:**

| Tình huống | `confirmed@written` | `confirmed@durable (verified)` |
|---|---|---|
| Lỗi ghi hoặc sync kho | Không mất nếu đủ (a)–(d); thử lại; đúng 1 bản ghi logic | Như cột bên trái |
| App bị dừng | Không mất nếu đủ (a)–(e) **và** tiêu chí chịu dừng (GS-12.9). Là giả định cho tới khi tiêu chí đó `verified` | Như cột bên trái |
| Mất nguồn / tắt máy không sạch | **Không có bảo đảm**, kể cả khi đủ (a)–(e). `confirmed@written` **không** bao giờ được hiểu là chịu được mất nguồn | Không phát hiện vi phạm trong các điều kiện đã thử ở D3 |
| Sự kiện của lần ghi `indeterminate` (WE-3i) | Chưa được chuyển. Lần ghi sau (sau bước R) hoặc lần khôi phục sau sẽ quyết định nó có thuộc một commit hay không | Như cột bên trái |

**Không đổi:** khử trùng theo bản ghi logic (không bao giờ có hơn 1 bản ghi logic), cơ chế thử lại và điều kiện dọn nguồn.

---

# Test case

## TC-12.29 **[S]** (U): tiêm lỗi hết dung lượng, chia theo thao tác (viết lại)

| Nhóm | Điểm tiêm lỗi | Tiêu chí | Quy tắc |
|---|---|---|---|
| **P: trước commit** | `store_*` trả về `false`; `get_error()` sau flush; close; đọc `L.json` ở bước 2a; ghi `.bak.tmp`; tính hash; `precheck_failed` ở bước 2b hoặc 3 | Lỗi được phát hiện **trước khi gọi** primitive rename của bước 3: nhật ký truy cập **không có** lời gọi rename lên `L.json`. Trạng thái file đúng hàng WE-1a, 1b, 2a, 2b tương ứng; có cảnh báo | GS-12.2, 12.7, 12.8 |
| **B: tại bước 2b** | Lỗi trước khi rename có hiệu lực; lỗi sau khi có hiệu lực; lỗi kèm lỗi ở bước kiểm tra sau | Ra lần lượt WE-2b, WE-2b-r, WE-2b-i. Riêng WE-2b-i: không gọi bước 3; lần ghi sau chạy bước R | GS-12.7, 12.8 |
| **C: tại bước 3** | Lỗi trước khi có hiệu lực; lỗi sau khi có hiệu lực; lỗi kèm lỗi ở bước kiểm tra sau; báo thành công nhưng bước kiểm tra sau thất bại | `state_after` đúng là `unchanged`, `replaced`, `indeterminate`, `indeterminate`. Trạng thái file đúng bảng WE. Cảnh báo chỉ có khi **không** phải `replaced`. **Log commit chỉ có khi `replaced`.** Bộ chuyển sự kiện không chạy cho lần ghi `indeterminate` | GS-12.7, 12.8, 12.11 |
| **E: kho sự kiện** | `append_line` hết dung lượng (cả trường hợp ghi được một phần dòng); `sync_file` thất bại | Theo GS-14.4 và 14.5: không dọn nguồn; dừng lượt chuyển; các dòng ghi trước lần sync thất bại không bao giờ được xác nhận trong phiên; lần ghi sau chèn `\n` trước dòng mới; thử lại theo `OUTBOX_RETRY_MIN_INTERVAL_S`. **Không** áp dụng tiêu chí "trước bước 3" | GS-14.4, 14.5 |

## Test sửa

| ID | Thay đổi |
|---|---|
| TC-12.18 | Thêm trường hợp `precheck_failed` ở bước 2b: không gọi rename; kết quả `unchanged` |
| TC-12.19 | Thêm trường hợp `precheck_failed` ở bước 3 |
| TC-12.25 | Thêm các kỳ vọng: hồ sơ có kết quả mô phỏng, kết quả macOS hoặc Linux bị **từ chối** làm bằng chứng iOS; nếu thiếu D3 thì không bao giờ ra `durable (verified)`; `durable (assumed)` được coi như `written` trong mọi tuyên bố và log |
| TC-12.33 | Bổ sung: điều kiện `replaced` đúng như bảng GS-12.8, tức `src` vắng mặt (nhờ một lời gọi kiểm tra thành công) và `hash(dst) = expected` |
| TC-12.34 | Viết lại, xem bảng dưới |
| TC-12.35 | Giữ nguyên |

## Test mới

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-12.34 **[M]** (viết lại) | U | WE-3i ở năm biến thể: (a) kiểm tra tồn tại `src` thất bại; (b) đọc `dst` thất bại; (c) `hash(dst)` khác cả `pre_dst` lẫn `expected`; (d) cả `src` và `dst` đều vắng mặt; (e) lời gọi báo thành công nhưng bước kiểm tra sau thất bại. Sau đó lần ghi kế tiếp gặp lần lượt R1, R2, R3; ngoài ra có trường hợp khởi động lại ngay | Cả năm biến thể: `indeterminate`; không có log commit; có cảnh báo; bộ chuyển sự kiện không chạy. R1: có log `commit_reconciled`, chạy giao thức bình thường. R2: chạy bình thường. R3: không xoay `.bak`; có log `reconcile_unknown_main`. Khởi động lại: GS-13.4 cho ra `outcome` hợp lệ dựa trên file thật | GS-12.2, 12.7, 12.8, 13.4 |
| TC-12.38 **[M]** | U | **Hợp đồng `rename_replace`** chạy qua `FaultInjectingBackend` bọc bộ nhớ: (a) `dst` đã tồn tại, nội dung khác `src`; (b) `dst` vắng mặt; (c) thiếu `src`; (d) `dst` là thư mục; (e) `src` và `dst` cũ **có cùng nội dung**, lời gọi báo lỗi và `src` vẫn còn; (f) lỗi được tiêm trước khi có hiệu lực; (g) lỗi được tiêm sau khi có hiệu lực; (h) lỗi được tiêm kèm lỗi ở bước kiểm tra sau; (i) `crash()` ngay sau rename rồi khởi động lại | (a) và (b): `replaced`, `src` vắng mặt, `hash(dst) = expected`. (c): `src_missing`, `unchanged`. (d): `dst_is_dir`, `unchanged`. (e): `unchanged` (không bị nhận nhầm là `replaced`). (f): `unchanged`. (g): `replaced`. (h): `indeterminate`. (i): sau khi khởi động, `dst` ∈ {cũ, mới} và nhất quán với việc `src` còn hay mất | GS-12.8 |
| TC-12.39 **[M]** | D | **Hợp đồng rename trên thiết bị iOS thật**, trong `user://rename_test/`. Thư mục này bị xoá lúc bắt đầu và lúc kết thúc. Các trường hợp (a)–(d) của TC-12.38, mỗi trường hợp ≥ 100 lần. Thêm: (e) vòng lặp 1000 lần rename đè lên một đích có sẵn, `OS.crash()` ở thời điểm ngẫu nhiên, lặp ≥ 50 lần, kiểm tra sau mỗi lần khởi động lại | (a)–(d): đúng kết quả như TC-12.38. (e): sau mỗi lần khởi động lại, `dst` luôn tồn tại, đọc được, có hash ∈ {cũ, mới}; nếu hash là bản mới thì `src` vắng mặt. **Tiêu chí:** 0 vi phạm trong N lần, có ghi N và điều kiện thử. Đạt **không** có nghĩa là bảo đảm tuyệt đối. Lỗi "sau khi có hiệu lực" không tạo được trên thiết bị nên chỉ kiểm ở TC-12.38 | GS-12.8, 12.10 |
| TC-12.40 **[M]** | U | Bước 1 của `rename_replace` (kiểm tra trước) thất bại, ở bước 2b và ở bước 3 | Không có lời gọi rename trong nhật ký; `precheck_failed`; `unchanged`; huỷ lần ghi; cảnh báo | GS-12.8, 12.7 |
| TC-12.41 **[M]** | U | Bước 3 khi `B_new` giống hệt `L.json` cũ, cả khi lời gọi báo thành công lẫn báo lỗi | Báo thành công và `src` vắng mặt → `replaced`. Báo lỗi và `src` vẫn còn → `unchanged`. Không bao giờ bị phân loại sai chỉ vì hai bên trùng nội dung | GS-12.8 |
| TC-12.42 **[M]** | U | WE-2b-i, sau đó lần ghi kế tiếp | Không gọi bước 3; lần ghi sau chạy bước R; nếu `L.json` khớp `H_commit` (R2) thì `.bak` được ghi lại từ đúng byte của `L.json` | GS-12.2, 12.7 |
| TC-12.43 **[M]** | U | `L.json` trên đĩa khác `H_commit` mà app giữ trong bộ nhớ (giả lập file bị sửa từ bên ngoài); chạy bước 2 | `expected_src_hash` của bước 2b bằng hash của **byte đọc được** (`H_bak`), không phải `H_commit`; kết quả `replaced` đúng. Đối chứng: nếu (sai) truyền `H_commit` thì kết quả là `indeterminate`, và test phải chứng minh hiện thực **không** làm như vậy | GS-12.2, 12.8 |

---

# Ma trận đối chiếu v0.4.5

Chỉ ghi các dòng thay đổi so với v0.4.4.

| Mục | Quy tắc → test |
|---|---|
| 12 | 12.2: TC-12.7, 12.11, 12.12, 12.14, 12.16, 12.19–12.21, 12.27, 12.33, 12.34, **12.42, 12.43**, 14.6 · 12.7: TC-12.12, 12.15–12.20, 12.22, 12.24, 12.29 (P, B, C), 12.33–12.35, **12.40, 12.42**, 13.37, 14.28 · **12.8: TC-12.23, 12.25, 12.29, 12.33–12.43** · 12.9: TC-12.20, 12.24, 12.25, 12.31, 14.31 · **12.10: TC-12.25–12.28, 12.30–12.32, 12.36, 12.37, 12.39** · 12.11: TC-12.20, 12.24(d), **12.29 (C)** |
| 13 | 13.4: thêm **TC-12.34** (khởi động lại sau `indeterminate`) |
| 14 | 14.4: thêm **TC-12.29 (E)** · 14.5: thêm **TC-12.29 (E)** · 14.6: TC-14.2, 14.6–14.9, 14.14, 14.23, 14.24, 12.24, 14.31, **12.34** |
| Cổng | **Q1:** TC-12.27, 12.28, 12.30, 12.39 · **Q2:** TC-12.36; điều kiện tiên quyết TC-12.29 (P, B, C, E) · **Q3 (thông tin):** TC-12.31 · **`durable (verified)`:** D1–D3 ở GS-12.9; hiện **chưa có test nào thoả D3** |

---

# Kiểm tra tính nhất quán

| Cặp đối chiếu | Kết quả |
|---|---|
| Bảng năng lực (GS-12.8) ↔ bảng bảo đảm (GS-12.9) | Nhất quán. `durable (assumed)` được coi như `written`; chỉ `durable (verified)` mới mở cột "mất nguồn". Mô phỏng, macOS và Linux đều bị loại khỏi bằng chứng iOS ở cả hai nơi |
| Giao thức commit (GS-12.2) ↔ `state_after` (GS-12.8) ↔ bảng WE (GS-12.7) | Nhất quán. Commit **chỉ** khi `replaced`, ở cả ba nơi. `indeterminate` không bao giờ là commit, và luôn dẫn tới bước R ở lần ghi sau |
| Bảng WE ↔ bảng khôi phục (GS-13.4) | Nhất quán. Mọi trạng thái file có thể có sau WE-2b-i hoặc WE-3i (`.bak` vắng mặt, `L.json` là N hoặc `B_new`) đều thuộc các loại mà E1 đánh giá được. Không bao giờ dùng file tạm |
| Log commit (GS-12.11) ↔ bảng WE | Nhất quán. Không ghi log commit khi `indeterminate` |
| Điều kiện dọn nguồn (GS-13.11, 13.15, 14.4, 14.9) ↔ bảo đảm (GS-14.6) | Nhất quán. Dọn nguồn dựa trên `confirmed@L_backend`; GS-14.6 nêu rõ bảo đảm mất hiệu lực khi nguồn đã bị dọn mà dòng kho bị mất. Bộ chuyển sự kiện không chạy cho lần ghi `indeterminate` |
| Bất biến "`.bak` cách tối đa 1 commit" ↔ R3 | Đã thêm một ngoại lệ có ghi log. Đây là chỗ duy nhất nới bất biến |

---

# Phân loại mức chắc chắn

**A. Đã rà trên tài liệu đặc tả, trong phiên này:**
- Các cặp đối chiếu trong bảng ở trên.
- Ma trận GS↔TC và cổng Q.
- Không còn chỗ nào dùng `confirmed`, `committed` hay `durable` mà không kèm mức hoặc bằng chứng.

**B. Đã thử trên Linux ở các lượt trước, không phải iOS:**
- `open(WRITE)` dùng `O_TRUNC`.
- `flush()` không gọi `fsync`.
- `rename_absolute` gọi đúng một `rename(2)`, không `unlink` trước.
- Thiếu `src` thì trả về `1` (ERR_FAILED) mà không có errno.
- Lượt này không chạy thử nghiệm mới nào.

**C. Giả định thiết kế:**
- Bản iOS dùng cùng driver Unix.
- Rename trên APFS là atomic.
- Dữ liệu `written` còn nguyên khi app bị dừng.
- Việc đọc lại ở bước kiểm tra sau phản ánh đúng trạng thái `written`.
- Đọc `L.json` và `.bak` mỗi lần commit vẫn nằm trong ngân sách 2 ms (GS-12.5).
- Chỉ có một tiến trình ghi.
- `OS.crash()` và `DirAccess.get_space_left()` dùng được trên iOS.
- Tồn tại một phương pháp đạt D3 (chưa biết có hay không).

**D. Phải kiểm chứng trên iOS:** TC-12.1–12.3, 12.26–12.28, 12.30–12.32, 12.36, **12.39**. TC-12.37 kiểm trên macOS và chỉ là bằng chứng bổ trợ.

**Chưa có test nào được chạy.** Repo chưa có code Godot.

---

# Danh sách thay đổi so với v0.4.4

1. **GS-12.2:**
   - Định nghĩa `B_new`/`H_new` (bước 3), `B_old`/`H_bak` (bước 2b, tính từ byte đọc được) và `H_commit`.
   - Quy định cách xử lý khi đọc file hoặc tính hash thất bại.
   - Thêm bước R (R1–R3) và ngoại lệ có ghi log cho bất biến `.bak`.
2. **GS-12.8:**
   - `rename_replace` có bước kiểm tra trước (`pre_dst`), kiểm tra sau chạy luôn, và điều kiện đủ cho `replaced`, `unchanged`, `indeterminate`.
   - Lỗi trong bước kiểm tra cho ra `indeterminate`.
   - Thêm `precheck_failed`, `postcheck_failed`.
   - Bảng tiêu chí chuyển `assumed` → `verified` cho từng năng lực, cùng quy tắc loại bằng chứng không phải iOS.
3. **GS-12.7:** thay các hàng WE ở bước 2b và bước 3; thêm WE-2b-r, WE-2b-i; WE-3i áp dụng cả khi lời gọi báo thành công.
4. **GS-12.9:** tách hai bộ tiêu chí; thêm D1–D3 cho `durable (verified)`; nêu rõ hiện chưa có phương pháp thoả D3.
5. **GS-12.10:** Q1 thêm TC-12.39; Q2 dựa trên TC-12.29 đạt từng nhóm; nguyên mẫu native chỉ được ghi nhận đúng mức bằng chứng của nó.
6. **GS-14.6:** năm điều kiện (a)–(e) cho câu "không mất"; bảng mới có thêm hàng cho lần ghi `indeterminate`.
7. **Test:**
   - **Viết lại:** TC-12.29 (bốn nhóm P, B, C, E), TC-12.34 (năm biến thể cùng R1–R3).
   - **Sửa:** TC-12.18, 12.19, 12.25, 12.33.
   - **Mới:** TC-12.38 (U), TC-12.39 (D), TC-12.40–12.43 (U).
   - Không bỏ test nào.

---

# Rủi ro còn lại

- **R-8:** MVP thực tế chỉ đạt mức `written`. Chưa có phương pháp nào thoả D3, nên có thể **không bao giờ** đạt `durable (verified)` trên iOS trong MVP.
- **R-15 (sửa):** bước kiểm tra sau rename đọc từ lớp `written`. Trường hợp `indeterminate` được xử lý theo hướng an toàn. Việc đọc thêm `L.json` và `.bak` ở mỗi lần commit làm tăng chi phí; cần đo ở TC-16.1.
- **R-16:** TC-12.36 và 12.39 chỉ cho kết quả 0 vi phạm trên N lần thử, không chứng minh được rằng không bao giờ có vi phạm.
- **R-17:** mô hình hai lớp không bao quát hết hành vi thật của hệ thống.
- **R-18 (mới):** sau R3, `.bak` có thể cũ hơn nhiều commit, khiến lần khôi phục từ `.bak` sau đó lùi xa hơn 1 commit. Thông báo GS-13.14 vẫn hiện.
- **R-19 (mới):** D3 có thể đòi hỏi thiết bị hoặc dụng cụ đặc biệt; chưa xác định được.
- **Giữ nguyên:** R-1 đến R-7, R-9 (đã chốt), R-10 đến R-14.

---

**Trạng thái repo**, đã kiểm tra thực tế trong lượt này bằng lệnh chỉ đọc:
- HEAD `8feed74` trên nhánh `claude/cloud-session-connection-check-hksw4v`; không có stash.
- `git status`, hash của phần thay đổi chưa commit và hash của các file chưa theo dõi đều trùng mốc đã ghi.
- Lượt này không chạy thử nghiệm nào và không tạo hay sửa file nào trong repo.

Tôi dừng ở đây để bạn duyệt v0.4.5.
