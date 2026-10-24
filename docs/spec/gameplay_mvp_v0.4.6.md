<!-- Lưu trữ nguyên văn bản đặc tả v0.4.6 từ phiên làm việc. Xem docs/spec/README.md để biết cách đọc. -->

# Đặc tả gameplay MVP v0.4.6 (các mục sửa)

**Phạm vi:**
- Chỉ các mục ghi dưới đây thay đổi so với v0.4.5; phần còn lại giữ nguyên.
- KT-1 đến KT-6 giữ nguyên.
- Không đụng tới gameplay hay schema level.
- **Không thêm file metadata mới** (lý do ở GS-12.2, mục "Không thêm file nhật ký commit").

---

## 12. Lưu tiến độ

### GS-12.2 Phạm vi của các hash và bước đối soát (thay phần "Hash mong đợi" và "Bước R" của v0.4.5)

#### Phạm vi tồn tại

| Ký hiệu | Phạm vi | Thời điểm đặt | Khi app bị dừng |
|---|---|---|---|
| `H_pending` (tên mới của `H_new`) | **Một lần ghi**, chỉ trong bộ nhớ | Trước bước 1, bằng SHA-256 của `B_new` | **Mất** |
| `H_bak` | **Một lần ghi**, chỉ trong bộ nhớ | Ở bước 2a, bằng SHA-256 của byte đọc được từ `L.json` | **Mất** |
| `H_commit` | **Một phiên**, tức một lần chạy tiến trình; chỉ trong bộ nhớ | Ban đầu theo GS-13.4 E3 (bên dưới); sau đó bằng `H_pending` của mỗi lần ghi có `state_after = replaced` | **Mất** |
| `H_commit = none` | Một phiên | Khi `L.json` không tồn tại ở mốc ban đầu (nguồn là `bak` hoặc `none`) | — |

- **Không quy tắc nào được giả định rằng các giá trị này còn sau khi app khởi động lại.**
- **Bất biến I-H:** mọi quyết định của giao thức chỉ dựa vào **nội dung byte** hiện có (qua hash) và vào việc file có tồn tại hay không. Không quy tắc nào dùng hash để suy ra **thứ tự** hay **số lượng** commit.

#### Mốc ban đầu của phiên (bổ sung cho GS-13.4)

- **Ở bước E1:** mỗi ứng viên được đọc **đúng một lần**. Ghi lại `H_read(ứng viên)` = SHA-256 của chính các byte đã đọc và đã đánh giá.
- **Ở bước E3:**

| Nguồn | `H_commit` ban đầu |
|---|---|
| `main`, và E3.2 không bắt buộc ghi | `H_read(L.json)` |
| `main`, và E3.2 có ghi (migration, `restored_hex_changed`) | Đặt theo kết quả của lần ghi đó. Nếu lần ghi không có `replaced` thì giữ `H_read(L.json)` |
| `bak` (lúc này `L.json` đã được lưu trữ, không còn) hoặc `none` | `none` cho tới commit đầu tiên |

#### Bước R: đối soát trong phiên (thay thế)

- **Khi nào chạy:** trước lần ghi kế tiếp, nếu lần ghi trước kết thúc bằng WE-2b-i hoặc WE-3i, **trong cùng phiên**.
- **Cách làm:** đọc `L.json`, tính `H_disk`. Gọi `H_prev_pending` là `H_pending` của lần ghi bị `indeterminate`.

| Trường hợp | Điều kiện | Kết luận | Xoay `.bak` ở bước 2 |
|---|---|---|---|
| **R12** | `H_disk = H_prev_pending` **hoặc** `H_disk = H_commit` | `L.json` chứa một bản đã commit, có nội dung `H_disk`. Đặt `H_commit = H_disk`. Nếu `H_disk = H_prev_pending` thì ghi log `commit_reconciled` | Có |
| **R0** | `L.json` vắng mặt **và** `H_commit = none` | Lần ghi trước chưa commit | Không có gì để xoay; chạy bước 1 rồi bước 3 |
| **R3** | Mọi trường hợp khác: `L.json` không đọc được; vắng mặt dù `H_commit ≠ none`; hoặc hash khác cả hai | Không biết `L.json` đang chứa gì | **Không**. Chạy bước 1 rồi bước 3; ghi log `reconcile_unknown_main` |

#### R1 và R2 gộp thành R12. Lập luận

Khi `H_prev_pending = H_commit`, hai byte chuỗi giống hệt nhau, nên "đã commit lần ghi mới" và "vẫn là commit cũ" cho ra **cùng một nội dung file**. Lần lượt xét mọi thứ có thể phụ thuộc vào việc phân biệt hai trường hợp:

- **Tiến độ:** `placed`, `selected`, `completed` nằm trong byte → giống nhau.
- **`outbox`:** cũng nằm trong byte → cùng một tập mục, cùng thứ tự.
  - Một lần ghi có xoá các mục đã `confirmed` thì byte của nó phải khác → không thể rơi vào trường hợp bằng nhau.
- **Bộ chuyển sự kiện:** ở R12, bộ chuyển chạy cho `outbox` của `H_disk`.
  - Các mục của nó trùng với mục của commit trước, vốn đã hoặc sẽ được chuyển.
  - Theo GS-14.4, mục đã `confirmed` thì bị bỏ qua, mục chưa `confirmed` thì được ghi lại, và GS-14.5 khử trùng theo bản ghi logic.
  - Vì vậy việc chạy thêm một lần **không đổi tập bản ghi logic**.
- **Xoay `.bak`:** cả hai cách hiểu đều xoay từ chính byte của `L.json` → kết quả giống nhau.
- **`H_commit`:** cả hai cách hiểu đều cho ra cùng giá trị `H_disk`.
- **Khác biệt duy nhất** là số lần commit mà log ghi nhận. Không quy tắc nào dùng con số đó (bất biến I-H).

**Kết luận:** không cần phân biệt, và cũng không cần thêm bằng chứng nào.

#### Đường xử lý sau khi app khởi động lại, sau WE-2b-i hoặc WE-3i

1. **Bước R không chạy.** Không còn `H_prev_pending` hay `H_commit` để so.
2. Chạy GS-13.13 để dọn file tạm, rồi GS-13.4 trên **các file thật**:
   - `L.json` và `.bak` được đánh giá độc lập. Mỗi file có thể là: hợp lệ, không đọc được, không hợp lệ, hoặc vắng mặt.
   - Nguồn được chọn theo E2; ứng viên không được chọn được lưu trữ theo E3.1.
3. **Mốc mới** được đặt theo bảng "Mốc ban đầu của phiên".
4. **Ghi tiếp** theo giao thức bình thường:
   - Bước 2 xoay `.bak` từ byte đọc được của `L.json` ngay lúc đó (`H_bak`).
   - Bước 3 dùng `H_pending` của lần ghi mới.
   - Không cần bất kỳ hash nào từ phiên trước.
5. **Hệ quả:**
   - Trạng thái N+1 chỉ còn trong bộ nhớ của phiên trước thì mất. Lần ghi của nó hoặc đã thực sự thay `L.json` (lúc đó nó được khôi phục), hoặc chưa (lúc đó nó mất). Cả hai đều nằm trong mục tiêu GS-12.4.
   - Sự kiện của N+1 có cùng số phận với N+1.

#### Không thêm file nhật ký commit

Một file nhật ký (ví dụ ghi `H_pending` trước khi commit) sẽ cần:
- cơ chế ghi atomic của riêng nó;
- các trạng thái lỗi riêng (ghi dở, lệch so với `L.json`, mất);
- và một quy tắc ưu tiên khi nó mâu thuẫn với `L.json`.

Trong khi đó, đánh giá dựa trên nội dung (GS-13.4) đã cho ra kết quả hợp lệ ở mọi trạng thái được liệt kê, nên nhật ký không thêm được khả năng khôi phục nào. **Quyết định: không thêm.**

### GS-12.7 WE-2b-i (thay hàng)

| Điểm | Trạng thái file | Xử lý |
|---|---|---|
| WE-2b-i | `L.json` = N (bước 3 chưa chạy). **`.bak` không xác định:** có thể là N−1, N, vắng mặt, **không đọc được, không hợp lệ, hoặc có nội dung bất kỳ**. `.bak.tmp` có thể còn hoặc không | Huỷ trước bước 3; cảnh báo. **Trong cùng phiên:** chạy bước R. Bước R **không đọc `.bak`**; trường hợp R12 sẽ ghi đè `.bak` bằng byte của `L.json`, còn R3 giữ nguyên `.bak`. **Sau khi khởi động lại:** GS-13.4 tự đánh giá `.bak`; nếu `.bak` hỏng thì nó là `broken` và được lưu trữ dạng `.corrupt` |

- Hàng WE-3i bổ sung: **`L.json` cũng có thể không đọc được hoặc không hợp lệ.** Bước R (R3) và GS-13.4 đều xử lý được trường hợp này.
- Nếu ở R3 cả `L.json` lẫn `.bak` đều hỏng, lần ghi tiếp tạo `L.json` mới từ trạng thái trong bộ nhớ.
  - **Không mất sự kiện**, vì `outbox` trong bộ nhớ chứa mọi mục của mọi bản mà phiên này đã ghi.
  - Mục duy nhất có thể đã bị xoá khỏi `outbox` trong bộ nhớ là mục đã `confirmed@L_backend` (GS-14.4).

### GS-12.8 Hợp đồng `rename_replace` (sửa)

#### Kết quả có cấu trúc

`{ok, err, primitive_result, postcheck, state_after}`, trong đó `ok` ⇔ `state_after = replaced`.

| Tình huống | `primitive_result` | `postcheck` | `state_after` | `err` |
|---|---|---|---|---|
| **Kiểm tra trước thất bại** (không đọc được `dst` hiện tại, không kiểm tra được `src`) | `not_called` | `not_run` | `unchanged`. Lý do: **không có lời gọi nào làm thay đổi file**; nhật ký truy cập chứng minh điều này, dưới giả định chỉ có một tiến trình ghi | `precheck_failed` |
| Kiểm tra trước phát hiện `src_missing`, `dst_is_dir`, hoặc năng lực `unavailable` | `not_called` | `not_run` | `unchanged` | `src_missing` / `dst_is_dir` / `replace_not_atomic` |
| **Primitive báo thành công**, kiểm tra sau đạt | `ok` | `ok` | Theo bảng điều kiện bên dưới | — |
| **Primitive báo lỗi**, kiểm tra sau đạt | `error` | `ok` | Theo bảng điều kiện | `io_failed` (hoặc `unknown`) |
| **Kiểm tra sau thất bại** (lỗi khi kiểm tra tồn tại, đọc hay tính hash), dù primitive báo gì | `ok` hoặc `error` | `failed` | **`indeterminate`** | `postcheck_failed` |

#### Điều kiện đủ khi kiểm tra sau đạt

| `state_after` | Điều kiện đủ |
|---|---|
| `replaced` | `src` vắng mặt **và** `hash(dst) = expected_src_hash` |
| `unchanged` | `src` còn, với `hash(src) = expected_src_hash`, **và** `dst` khớp `pre_dst` |
| `indeterminate` | Mọi trường hợp khác. **Gồm cả** các trạng thái vi phạm tính nhất quán hai chiều: `dst` mới mà `src` còn; `dst` cũ mà `src` mất; `dst` vắng mặt dù trước đó có; hash lạ |

- Nếu kiểm tra sau đạt mà **primitive báo thành công** nhưng kết quả là `indeterminate`, ghi thêm log `rename_contract_violation`. Đây là **tín hiệu vi phạm** cho mục "Hạ cấp hồ sơ" bên dưới.

#### Hạ cấp hồ sơ `verified` (mới)

1. **Thế nào là vi phạm:**
   - Bất kỳ lần chạy test nào (U trên mô hình thật, I, hoặc D) cho ra kết quả trái tiêu chí;
   - hoặc một log `rename_contract_violation` thu được từ thiết bị đã được xác nhận là không do khung test gây ra.
2. **Khi có vi phạm:**
   - Hồ sơ của tổ hợp đó được đánh dấu `revoked`, kèm mã vi phạm và ngày.
   - Hồ sơ `revoked` **được xử lý như không có hồ sơ**: năng lực trở về `assumed`.
   - Build kế tiếp mang hồ sơ đã `revoked`.
   - Mọi tuyên bố bảo đảm dựa trên hồ sơ cũ (tài liệu nội bộ, ghi chú phát hành) phải được **rút lại ngay**. Kể cả với các build đã phát hành, hồ sơ cũ không còn được dùng làm căn cứ.
3. **Chỉ được cấp lại** khi đã phân loại nguyên nhân (N1–N5, GS-12.10), đã sửa, và chạy lại **toàn bộ** tiêu chí với N lần thử mới. Không khôi phục hồ sơ cũ.
4. **Không ảnh hưởng tới logic chạy:**
   - Mức bằng chứng (`verified`, `assumed`, `revoked`) **chỉ** ảnh hưởng tới nhãn trong log và trong tuyên bố bảo đảm.
   - Nó **không** thay đổi các điều kiện về `state_after`, điều kiện commit, bước R hay GS-13.4. `indeterminate` không bao giờ là commit, dù ở mức bằng chứng nào.
   - Chỉ riêng **giá trị** `atomic_replace = unavailable` mới đổi hành vi (WE-R). Giá trị này chỉ được đổi bằng một build mới kèm hồ sơ quyết định.

### GS-12.9 (giữ nguyên, nhấn mạnh hai câu)

- Không nâng lên `durable (verified)` khi chưa có D3. Hiện **chưa có** phương pháp nào thoả D3.
- Hồ sơ `durable` bị `revoked` thì cũng được xử lý như không có hồ sơ, giống quy tắc ở GS-12.8.

### GS-12.10 (bổ sung một câu)

- Hồ sơ của Q1 hay Q2 bị `revoked` thì cổng tương ứng được coi là **không đạt** cho tới khi được cấp lại theo GS-12.8 mục 3.

---

## 13–14. Khôi phục và sự kiện

- **GS-13.4:** bổ sung `H_read` và "mốc ban đầu của phiên" như ở GS-12.2. Không thay đổi gì khác.
- **GS-14.4:** bổ sung một câu. Ở trường hợp R12, bộ chuyển sự kiện chạy cho `outbox` của `H_disk`; việc này luôn không gây hại, theo lập luận ở GS-12.2.
- **GS-14.6, hàng "lần ghi `indeterminate`":**
  - Trong cùng phiên: bước R quyết định.
  - Sau khi khởi động lại: GS-13.4 quyết định dựa trên các file thật.
  - Sự kiện của một trạng thái chưa từng được commit vào file thì mất, cùng với trạng thái đó (GS-12.4).
- Không đổi: khử trùng bản ghi logic, cơ chế thử lại, điều kiện dọn nguồn.

---

# Test case

## Test sửa

| ID | Thay đổi |
|---|---|
| **TC-12.38** (U, mô phỏng) | **Tiêu chí hai chiều** áp dụng cho mọi trường hợp: (1) kết quả trả về `replaced` ⇒ `dst` = mới **và** `src` vắng mặt; `unchanged` ⇒ `dst` = cũ (hoặc vẫn vắng mặt nếu trước đó vắng mặt) **và** `src` còn với hash đúng. (2) Trường hợp (i), `crash()` rồi khởi động lại: trạng thái **chỉ được** thuộc {`dst` cũ (hoặc vắng mặt nếu trước đó vắng mặt) **và** `src` còn} hoặc {`dst` mới **và** `src` vắng mặt}. **Không chấp nhận:** `dst` cũ và `src` mất (mất cả bản mới lẫn nguồn); `dst` mới và `src` còn; `dst` vắng mặt dù trước đó có; hash lạ. Ghi chú: đây là **test mô phỏng**, nó kiểm hiện thực của backend và mô hình, **không** kiểm iOS |
| **TC-12.39** (D, iOS thật) | Trường hợp (e) dùng đúng tiêu chí hai chiều ở trên, kiểm tra sau **mỗi** lần khởi động lại; mỗi trạng thái không được chấp nhận được tính là **một vi phạm**. Trường hợp (a)–(d) kiểm thêm chiều (1). Tiêu chí: 0 vi phạm trong N lần, có ghi N. Chỉ kết quả của test này (cùng TC-12.27, 12.28) mới được dùng làm bằng chứng cho `atomic_replace` trên iOS |
| **TC-12.40** | Kiểm tra trước thất bại → `primitive_result = not_called`, `postcheck = not_run`, `state_after = unchanged`, `err = precheck_failed`. Nhật ký truy cập **không có lời gọi nào làm thay đổi file** |
| **TC-12.34** | Thêm hai biến thể: (f) primitive báo lỗi và kiểm tra sau thất bại; (g) primitive báo thành công và kiểm tra sau thất bại. Cả hai: `postcheck = failed`, `err = postcheck_failed`, `state_after = indeterminate`, **không** commit. Biến thể (c) và (d) dẫn tới thêm log `rename_contract_violation` khi primitive báo thành công. Thay "R1/R2" bằng **R12**; thêm trường hợp R0 |
| **TC-12.29** | **Nhóm P** (tách riêng): kiểm tra trước thất bại → `not_called`; lỗi được phát hiện trước khi gọi primitive của bước 3. **Nhóm B và C**, ba trường hợp tách bạch: (1) kiểm tra trước thất bại (`not_called`, `unchanged`); (2) primitive báo lỗi, kiểm tra sau đạt (`unchanged` hoặc `replaced`); (3) kiểm tra sau thất bại (`indeterminate`, không commit). Nhóm E giữ nguyên |
| **TC-12.25** | Thêm kỳ vọng: hồ sơ `revoked` được xử lý như không có hồ sơ; không nạp lại được hồ sơ cũ đã `revoked` |
| **TC-12.42** | Thay "R2" bằng "R12" |

## Test mới

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-12.44 **[M]** | U | **Khởi động lại sau WE-3i**, ba biến thể: `L.json` thực tế là (a) `B_new`, (b) N, (c) không đọc được (khi đó `.bak` = N) | Bước R **không** chạy. GS-13.4: (a) `source = main`, tiến độ là N+1, mốc = `H_read`. (b) `source = main`, tiến độ là N. (c) `source = bak` kèm thông báo; `L.json` được lưu trữ dạng `.corrupt`. Lần ghi kế tiếp xoay `.bak` từ byte đọc được (với a và b) hoặc bỏ qua bước 2 vì `L.json` vắng mặt (với c). Không quy tắc nào cần hash của phiên trước | GS-12.2, 12.7, 13.4 |
| TC-12.45 **[M]** | U | `B_new` giống hệt `L.json` hiện tại, rồi WE-3i, rồi bước R. Chạy song song hai cách hiểu (đã commit / chưa commit) trên mô hình | Cả hai cho ra cùng: byte của `L.json` và `.bak` sau lần ghi kế tiếp, `H_commit`, `outbox`, và **tập bản ghi logic** trong kho. Khác biệt duy nhất là log `commit_reconciled` | GS-12.2, 14.4, 14.5 |
| TC-12.46 **[M]** | U | **Cùng nội dung, khác lịch sử:** commit X, Y, rồi X lần nữa (giả lập); ở mỗi bước có tiêm WE-3i, WE-2b-i và `crash()` | Mọi quyết định (`state_after`, bước R, chọn nguồn ở GS-13.4, xoay `.bak`, chuyển sự kiện) chỉ phụ thuộc vào byte và việc file có tồn tại hay không; không bước nào cho kết quả dựa trên thứ tự commit (bất biến I-H) | GS-12.2, 12.8, 13.4 |
| TC-12.47 **[M]** | U | WE-2b-i với `.bak` ở từng trạng thái {N−1, N, vắng mặt, không đọc được, JSON hỏng, hợp lệ nhưng là level khác, nội dung bất kỳ}. Trong cùng phiên chạy R12 và R3; ngoài ra có trường hợp khởi động lại | Bước R không đọc `.bak`. R12: `.bak` bị ghi đè bằng byte của `L.json`. R3: `.bak` giữ nguyên. Khởi động lại: E1 phân loại đúng (`broken` hoặc `incompatible`), lưu trữ đúng; không crash | GS-12.7, 12.2, 13.4 |
| TC-12.48 **[M]** | U | Hồ sơ `verified`, sau đó tiêm một vi phạm, sau đó chạy lại cùng bộ kịch bản WE và WK | Hồ sơ thành `revoked`; log và tuyên bố hiện `assumed`. Mọi `state_after`, mọi quyết định commit và kết quả khôi phục **giống hệt** lúc còn hồ sơ `verified` | GS-12.8, 12.9, 12.10 |

---

# Ma trận đối chiếu v0.4.6

Chỉ ghi các dòng thay đổi so với v0.4.5.

| Mục | Quy tắc → test |
|---|---|
| 12 | 12.2: TC-12.7, 12.11, 12.12, 12.14, 12.16, 12.19–12.21, 12.27, 12.33, 12.34, 12.42, 12.43, **12.44–12.47**, 14.6 · 12.7: TC-12.12, 12.15–12.20, 12.22, 12.24, 12.29, 12.33–12.35, 12.40, 12.42, **12.44, 12.47**, 13.37, 14.28 · 12.8: TC-12.23, 12.25, 12.29, 12.33–12.43, **12.46, 12.48** · 12.9: TC-12.20, 12.24, 12.25, 12.31, 14.31, **12.48** · 12.10: TC-12.25–12.28, 12.30–12.32, 12.36, 12.37, 12.39, **12.48** |
| 13 | 13.4: thêm **TC-12.44, 12.46, 12.47** |
| 14 | 14.4: thêm **TC-12.45** · 14.5: thêm **TC-12.45** · 14.6: thêm **TC-12.44, 12.45** |
| Cổng | Q1: TC-12.27, 12.28, 12.30, 12.39; hồ sơ bị `revoked` thì Q1 không đạt (TC-12.48) · Q2: TC-12.36, điều kiện tiên quyết TC-12.29 · `durable (verified)`: chưa có test nào thoả D3 |

---

# Rà soát cuối

## 1. Các trường hợp hash giống nhau nhưng lịch sử commit khác

| Trường hợp | Ở đâu | Xử lý |
|---|---|---|
| `H_pending = H_commit` | Bước R | Gộp thành R12; đã chứng minh vô hại; có TC-12.45 |
| Nội dung `src` trùng `dst` cũ | Kiểm tra sau rename | Dựa vào việc `src` còn hay mất; có TC-12.41 |
| Lặp lại nội dung X → Y → X | Mọi quy tắc | Bất biến I-H; có TC-12.46 |
| `.bak` = `L.json` (sau WE-3 hoặc WK-4) | GS-13.14 | Báo thừa được chấp nhận (KT-4); có TC-13.37 |
| `outbox` trùng `event_id` giữa `L.json` và `.bak` | GS-14.4 | Khử trùng logic; có TC-13.25 |
| Đụng độ SHA-256 | Mọi quy tắc | **Giả định** không xảy ra; không xử lý |

## 2. Các trạng thái file trước đây chưa được liệt kê và nay đã bổ sung

- `.bak` không xác định, không đọc được hoặc không hợp lệ sau WE-2b-i.
- `L.json` không đọc được sau WE-3i.
- `L.json` vắng mặt trong khi `H_commit ≠ none` (R3).
- `L.json` vắng mặt với `H_commit = none` (R0).

**Những trạng thái chỉ xuất hiện khi giả định atomic bị sai:**
- `dst` vắng mặt trong khi `src` còn: GS-13.4 khôi phục từ `.bak`. File tạm `N+1` bị dọn, có thể mất tới 2 commit.
- `dst` mới trong khi `src` vẫn còn: dùng `L.json`, file tạm bị dọn.

Cả hai trạng thái này được TC-12.38 và 12.39 tính là vi phạm, và được ghi vào R-20.

## 3. Đối chiếu chéo giữa các quy tắc

**GS-12.2 ↔ 12.7 ↔ 12.8:**
- Commit chỉ khi `replaced`.
- Kiểm tra trước thất bại → `unchanged` vì không gọi primitive, không phải do suy đoán. Chỗ mâu thuẫn trong v0.4.5 (điều kiện `unchanged` đòi `pre_dst` trong khi chính bước đọc `pre_dst` lại thất bại) đã được sửa.

**GS-12.9 ↔ 12.10 ↔ hạ cấp hồ sơ:**
- Mức bằng chứng không đổi logic chạy.
- Hồ sơ bị `revoked` thì cổng tương ứng không đạt.

**GS-13.4:**
- Không phụ thuộc hash của phiên trước.
- Có thêm `H_read` để đặt mốc.

**GS-14.4–14.6:**
- Trường hợp R12 không đổi tập bản ghi logic.
- Điều kiện dọn nguồn không đổi.

## 4. Mức chắc chắn

- **Đã rà trên tài liệu, trong phiên này:** các bảng ở mục 1–3; ma trận và cổng; lập luận cho R12.
- **Đã thử trên Linux ở các lượt trước:** hành vi `O_TRUNC`, `flush` không gọi `fsync`, `rename(2)`, và mã lỗi chung `ERR_FAILED`. **Lượt này không chạy thử nghiệm nào.**
- **Giả định:**
  - chỉ có một tiến trình ghi; đây cũng là căn cứ để `precheck_failed` cho ra `unchanged`;
  - SHA-256 không đụng độ;
  - bản iOS dùng cùng driver Unix; rename trên APFS là atomic;
  - dữ liệu `written` còn nguyên sau khi app bị dừng;
  - chi phí đọc thêm `L.json` và `.bak` nằm trong ngân sách 2 ms.
- **Chưa kiểm chứng:**
  - toàn bộ test cấp D trên iOS: TC-12.1–12.3, 12.26–12.28, 12.30–12.32, 12.36, 12.39;
  - TC-12.37 trên macOS.
  - **Chưa có test nào được chạy.** Repo chưa có code Godot.

---

# Danh sách thay đổi so với v0.4.5

1. **GS-12.2:**
   - Bảng phạm vi tồn tại của từng hash; đổi `H_new` thành `H_pending`; thêm `H_commit = none`; thêm bất biến I-H.
   - Mốc ban đầu của phiên (`H_read`), bổ sung vào GS-13.4.
   - Bước R chỉ chạy trong cùng phiên; gộp R1 và R2 thành R12, kèm lập luận; thêm R0.
   - Đường xử lý sau khi khởi động lại.
   - Quyết định không thêm file nhật ký commit, kèm lý do.
2. **GS-12.7:** WE-2b-i có `.bak` không xác định; WE-3i có thêm trường hợp `L.json` không đọc được; lập luận vì sao R3 không làm mất sự kiện.
3. **GS-12.8:**
   - Kết quả có cấu trúc `primitive_result`/`postcheck`, tách bạch kiểm tra trước thất bại, primitive báo lỗi và kiểm tra sau thất bại.
   - Các trạng thái vi phạm hai chiều được xếp vào `indeterminate`; thêm log `rename_contract_violation`.
   - Thêm quy trình hạ cấp hồ sơ (`revoked`).
4. **GS-12.9 và 12.10:** giữ chính sách D3; hồ sơ `revoked` khiến cổng không đạt.
5. **GS-14.4 và 14.6:** một câu về R12; hàng `indeterminate` tách xử lý trong phiên và sau khi khởi động lại.
6. **Test:**
   - **Sửa:** TC-12.25, 12.29, 12.34, 12.38, 12.39, 12.40, 12.42.
   - **Mới:** TC-12.44–12.48, đều cấp U.
   - Không bỏ test nào.

---

# Rủi ro còn lại

- **R-8:** MVP thực tế chỉ đạt mức `written`; chưa có phương pháp nào thoả D3.
- **R-16:** kết quả 0 vi phạm trên N lần thử không phải bảo đảm.
- **R-18:** sau R3, `.bak` có thể cũ hơn nhiều commit.
- **R-20 (mới):** nếu giả định atomic sai trên thiết bị, có thể mất tới 2 commit, vì file tạm không bao giờ được dùng. TC-12.39 sẽ phát hiện trường hợp này như một vi phạm.
- **R-21 (mới):** việc rút lại tuyên bố bảo đảm cho các build đã phát hành là quy trình bên ngoài app. Build đã phát hành không tự biết hồ sơ của nó đã bị `revoked`.
- **R-22 (mới):** việc `precheck_failed` cho ra `unchanged` dựa vào giả định chỉ có một tiến trình ghi.
- **Giữ nguyên:** R-1 đến R-7, R-9 (đã chốt), R-10 đến R-17, R-19.

---

**Trạng thái repo**, đã kiểm tra thực tế trong lượt này bằng lệnh chỉ đọc:
- HEAD `8feed74` trên nhánh `claude/cloud-session-connection-check-hksw4v`; không có stash.
- `git status`, hash của phần thay đổi chưa commit và hash của các file chưa theo dõi đều trùng mốc đã ghi.
- Lượt này không chạy thử nghiệm nào và không tạo hay sửa file nào trong repo.

Tôi dừng ở đây để bạn duyệt v0.4.6.
