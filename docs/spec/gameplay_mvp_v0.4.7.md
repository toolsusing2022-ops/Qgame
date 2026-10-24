<!-- Lưu trữ nguyên văn bản đặc tả v0.4.7 từ phiên làm việc. Xem docs/spec/README.md để biết cách đọc. -->

# Đặc tả gameplay MVP v0.4.7 (các mục sửa)

**Phạm vi:**
- Bản này xử lý ba vấn đề P1 mà bạn chặn duyệt:
  - `precheck_failed` không đủ căn cứ để trả về `unchanged`;
  - câu "Không mất sự kiện" ở GS-12.7;
  - điều kiện chuyển `outbox` ở R12.
- Sau đó là P1 về tiêu chí kiểm sau crash và hai mục P2, rồi đến các test và phần rà tham chiếu chéo.
- Mọi mục không ghi ở đây giữ nguyên v0.4.6. KT-1 đến KT-6 giữ nguyên.
- Không đụng tới gameplay hay schema level.
- **Không có quy tắc nào ở đây đã được kiểm chứng trên thiết bị.**

---

## P1-1. GS-12.8: tách `operation_effect` khỏi `state_after`

### Kết quả trả về (thay bảng của v0.4.6)

`{ok, err, operation_effect, primitive_result, postcheck, state_after}`

| Trường | Ý nghĩa |
|---|---|
| `operation_effect` | Lời gọi này **có thực hiện** thao tác làm thay đổi file hay không. `none`: primitive không được gọi. `attempted`: primitive đã được gọi. Trường này chỉ nói về **lời gọi hiện tại** |
| `state_after` | Backend **có bằng chứng tích cực** về trạng thái file sau lời gọi hay không. `replaced` / `unchanged` khi có bằng chứng; `indeterminate` khi không có |
| `ok` | Đúng khi và chỉ khi `state_after = replaced` |

### Điều kiện đủ (thay thế; áp dụng cho mọi đường đi, kể cả khi không gọi primitive)

| `state_after` | Điều kiện đủ |
|---|---|
| `replaced` | Đọc được và cho thấy `src` vắng mặt, **và** `hash(dst) = expected_src_hash` |
| `unchanged` | Đã đọc được cả hai phía và có bằng chứng tích cực: `src` tồn tại với `hash(src) = expected_src_hash`, **và** `dst` khớp `pre_dst` (vắng mặt, hoặc có hash = `pre_dst`). Ở đường đi không gọi primitive, phải **đọc được `pre_dst` ở bước kiểm tra trước**; chỉ dựa vào `operation_effect = none` là **không đủ** |
| `indeterminate` | Mọi trường hợp còn lại |

### Các đường đi

| Tình huống | `operation_effect` | `state_after` | `err` |
|---|---|---|---|
| Kiểm tra trước **không đọc được** `src` hoặc `dst` | `none` | **`indeterminate`** | `precheck_failed` |
| Kiểm tra trước đọc đủ hai phía, rồi từ chối vì `dst_is_dir` hoặc `replace_not_atomic` | `none` | `unchanged` (có bằng chứng tích cực) | `dst_is_dir` / `replace_not_atomic` |
| Kiểm tra trước thấy `src` vắng mặt | `none` | `indeterminate`, vì điều kiện `unchanged` đòi `src` tồn tại | `src_missing` |
| Primitive đã chạy và bước kiểm tra sau đạt | `attempted` | Theo bảng điều kiện | Có hoặc không có `io_failed` |
| Primitive đã chạy và bước kiểm tra sau thất bại | `attempted` | `indeterminate` | `postcheck_failed` |

**Thứ tự thực hiện:** kiểm tra trước (đọc `src`, đọc `pre_dst`) → kiểm tra năng lực → gọi primitive → kiểm tra sau. Năng lực `unavailable` nay được xét **sau** khi đã đọc, để kết quả `unchanged` có bằng chứng.

**`rename_noreplace`** áp dụng cùng các điều kiện và cùng tiêu chí bằng chứng như trên. Ở GS-13.4 E3.1 và GS-14.9, `indeterminate` được xử lý như lỗi đổi tên:
- E3.1 dừng với `archive_failed`;
- GS-14.9 giữ nguyên file `.pending-*` để thử lại sau.

### GS-12.7: hàng mới cho kiểm tra trước thất bại; sửa WE-2b và WE-3

| Điểm | Kết quả | Xử lý |
|---|---|---|
| **WE-2b-p** | `operation_effect = none`, `state_after = indeterminate` | Như WE-2b-i: huỷ trước bước 3, hiện cảnh báo, lần ghi sau chạy bước R. Ghi chú: lời gọi này không đổi tên gì, nhưng `.bak` vẫn có thể ở trạng thái bất thường từ trước |
| **WE-3p** | `operation_effect = none`, `state_after = indeterminate` | Như WE-3i: **không** commit, cảnh báo, chạy bước R. Vì primitive không được gọi nên lần ghi này **chắc chắn không** đổi `L.json`, nhưng nội dung hiện tại của `L.json` thì chưa biết |
| WE-2b / WE-3 | `unchanged` **có bằng chứng** | Bỏ cụm "(gồm cả `precheck_failed`)" của v0.4.5/0.4.6. Phần còn lại giữ nguyên |

---

## P1-2. GS-12.7: thay câu "Không mất sự kiện" sau R3

**Câu của v0.4.6 bị rút lại.** Câu thay thế:

> Ở R3, lần ghi tiếp theo tạo `L.json` mới từ trạng thái trong bộ nhớ. **Bản thân thao tác ghi đè này không làm mất thêm mục `outbox` nào**, vì `outbox` trong bộ nhớ chứa mọi mục của mọi bản `L.json` mà phiên này đã đọc làm mốc hoặc đã ghi. Ngoại lệ là các mục đã bị xoá khỏi bộ nhớ theo GS-14.4, tức là các mục đã `confirmed@L_backend`.
>
> Tuy vậy, sự kiện **vẫn có thể mất** trong các trường hợp sau:
> - (i) Mục đã bị xoá khỏi `outbox` vì đã `confirmed@written`, rồi sau đó **mất nguồn** hoặc **file kho bị hỏng hay bị xoá**. Lúc đó dòng của nó trong kho có thể không còn, mà nguồn cũng không còn.
> - (ii) App bị dừng **trước khi** lần ghi R3 commit được. Các mục chỉ có trong bộ nhớ mất cùng trạng thái của chúng (GS-12.4).
> - (iii) Các trường hợp đã có trong GS-14.6 khi không đủ điều kiện (a)–(e).
>
> Chỉ được nói "không mất" khi **hoặc** nguồn của mục vẫn còn nguyên (chưa bị dọn), **hoặc** dòng của mục đã `confirmed` ở mức đáp ứng được loại lỗi đang xét, theo bảng GS-14.6. Với mất nguồn, mức đó là `durable (verified)`, và hiện chưa có mức này.

GS-14.6 không đổi. Câu thay thế ở trên được viết để khớp với GS-14.6.

---

## P1-3. GS-12.2 và GS-14.4: R12 chỉ chuyển các mục có trong `L.json` đọc từ đĩa

### Sửa R12

| Trường hợp | Điều kiện | Kết luận | Chuyển sự kiện |
|---|---|---|---|
| **R12** | `H_disk = H_prev_pending` hoặc `H_disk = H_commit` | `L.json` chứa một bản đã commit, với byte là `B_disk` (chính các byte vừa đọc ở bước R). Đặt `H_commit = H_disk` | Bộ chuyển **chỉ** nhận danh sách `E_disk`, tức `outbox` **được phân tích từ `B_disk`**. **Không** nhận mục nào từ `outbox` trong bộ nhớ |

**Hai tình huống của R12:**

- **(R12-a) `H_disk = H_prev_pending`:** lần ghi trước thực ra đã commit.
  - `E_disk` là `outbox` của lần ghi đó.
  - Mục nào được thêm vào bộ nhớ **sau** lần ghi đó thì không nằm trong `E_disk`.
- **(R12-b) `H_disk = H_commit` và `H_disk ≠ H_prev_pending`:** lần ghi trước chưa commit.
  - `E_disk` là `outbox` của commit cũ. Các mục này phần lớn đã được xử lý sau commit cũ; mục nào đã có trong `confirmed_ids` thì bị bỏ qua.
  - **Các mục mới chỉ có trong bộ nhớ** (gọi là `E_mem \ E_disk`) **không** được chuyển, **không** được thêm vào `confirmed_ids`, và vẫn nằm trong `outbox` của bộ nhớ.
  - Chúng chỉ được chuyển sau một lần ghi kế tiếp có `state_after = replaced`.

### Sửa GS-14.4, nguồn (a)

Nguồn (a) là danh sách mục **được phân tích từ byte của một bản `L.json` đã biết là đã commit**, và chỉ có ba trường hợp:
- `B_new` của lần ghi có `replaced`;
- `B_disk` ở R12;
- byte `H_read` của mốc ban đầu (GS-13.4 E3).

**Bộ chuyển không bao giờ đọc `outbox` từ trạng thái trong bộ nhớ.**

### Lập luận vì sao R12 không làm sai `confirmed_ids`

- Một mục chỉ vào `confirmed_ids` sau khi bộ chuyển đã ghi dòng của nó và `sync_file` thành công (GS-14.4).
- Bộ chuyển chỉ nhận mục từ `E_disk`.
- Vì vậy một mục thuộc `E_mem \ E_disk` không thể vào `confirmed_ids` trước khi nó nằm trong một bản đã commit.

---

## P1-4. TC-12.38 và TC-12.39: phân loại sau crash

**Mỗi lần thử có đúng một trong ba kết quả:**

| Kết quả | Điều kiện |
|---|---|
| **Đạt** | Sau khi khởi động lại, **đọc được cả `src` lẫn `dst`**: kiểm tra được sự tồn tại của cả hai, và tính được hash của mọi file đang tồn tại. Trạng thái thoả **đúng một** trong hai dạng hợp lệ: {`dst` cũ (hoặc vắng mặt nếu trước đó vắng mặt) và `src` còn, với hash đúng} hoặc {`dst` mới và `src` vắng mặt} |
| **Vi phạm** | Đọc được đủ, nhưng trạng thái không thuộc hai dạng hợp lệ |
| **Không xác định** | Bất kỳ phép đọc hay kiểm tra tồn tại nào cần cho việc xác minh bị lỗi; **hoặc** lần thử thiếu bước kiểm tra sau khởi động lại |

**Cách tính:**
- "Không xác định" **không** được tính là đạt, và không được tính vào N.
- Mọi lần "không xác định" phải được ghi lại, kèm phân loại nguyên nhân (thường là N3 theo GS-12.10).
- **Một đợt chạy chỉ đạt khi** có 0 vi phạm, 0 "không xác định", và mọi lần thử đều có bước kiểm tra sau khởi động lại.
- **Hồ sơ `verified`** (GS-12.8) chỉ được cấp từ một đợt chạy đạt.
- Đạt chỉ là bằng chứng hữu hạn, **không** chứng minh tính atomic tuyệt đối.

**Phân biệt hai loại test:**
- TC-12.38 là **mô phỏng**. Trong mô hình, lỗi đọc được tiêm vào để kiểm chính quy tắc phân loại ba kết quả.
- TC-12.39 chạy trên **iOS thật**, và chỉ TC-12.39 được dùng làm bằng chứng iOS.

---

## P2-1. GS-12.2: R0

| Trường hợp | Điều kiện | Xử lý |
|---|---|---|
| **R0** | `L.json` vắng mặt **và** `H_commit = none` | Bỏ qua bước 2. **Bỏ qua bước 2 không có nghĩa là xoá hay ghi đè `.bak`**: `.bak` giữ nguyên từng byte. Chạy bước 1 rồi bước 3 |

**Nguồn của `B_new` ở R0:**
- `B_new` được tạo từ **trạng thái đang tiếp tục trong bộ nhớ**: trạng thái đã khôi phục ở GS-13.4 (từ `.bak`, hoặc trạng thái mới tạo khi nguồn là `none`) cộng với mọi thao tác sau đó.
- **Không bao giờ** dùng trạng thái rỗng hay mặc định, trừ khi đó đúng là trạng thái hiện tại (nguồn là `none` và chưa có thao tác nào).

**`.bak` sau R0:** `.bak` giữ nguyên **cả sau khi** `L.json` mới đã commit. Lần commit đầu tiên khi `L.json` vắng mặt không có gì để xoay (GS-13.4 E3.2). `.bak` chỉ thay đổi ở lần ghi kế tiếp, khi bước 2 chép `L.json` vào.

---

## P2-2. GS-12.8: vòng đời hồ sơ bị thu hồi

**1. Sổ bằng chứng (nằm ngoài app):**
- Là nơi duy nhất cấp hoặc thu hồi hồ sơ.
- Pipeline build nhúng vào build **cả** hồ sơ lẫn **danh sách thu hồi** (`revocation_list`, mỗi mục là một `record_id`).
- **Build thất bại** nếu nó định nhúng một hồ sơ có `record_id` nằm trong danh sách thu hồi.

**2. Khi app khởi động, nạp theo thứ tự cố định:**
1. `revocation_list`.
2. Các hồ sơ.
3. Bỏ mọi hồ sơ có `record_id` nằm trong danh sách.
4. Nếu `revocation_list` **thiếu, hỏng hoặc không đọc được**: bỏ **toàn bộ** hồ sơ. Khi có lỗi thì mặc định coi như không có bằng chứng.

**3. Tạm ngưng ngay trong app (cục bộ):**
- Khi thấy log `rename_contract_violation`, app lập tức coi hồ sơ liên quan là `suspended` **trong bộ nhớ** cho đến hết phiên.
- App ghi thêm `record_id` đó vào trường `storage_evidence_suspended` của **file cài đặt sẵn có** (GS-12.6). Đây không phải file mới. Việc ghi này dùng `write_file` + `rename_replace`, và chỉ là cố gắng: nếu ghi thất bại, lần khởi động sau sẽ tạm ngưng lại khi gặp vi phạm kế tiếp.
- Hồ sơ `suspended` được xử lý như không có hồ sơ.
- Chỉ sổ bằng chứng mới thu hồi chính thức. Trạng thái tạm ngưng cục bộ không bao giờ được tự gỡ trong app.

**4. Không đổi logic chạy:** giữ nguyên như v0.4.6.

---

# Test case

## Test sửa

| ID | Thay đổi |
|---|---|
| **TC-12.40** | Kiểm tra trước không đọc được `src` hoặc `dst`, ở cả bước 2b và bước 3 → `operation_effect = none`, `state_after = indeterminate`, `err = precheck_failed`; nhật ký truy cập không có lời gọi nào làm thay đổi file. Bước 2b đi theo WE-2b-p (không chạy bước 3, lần ghi sau chạy bước R). Bước 3 đi theo WE-3p (không commit, không chạy bộ chuyển sự kiện, lần ghi sau chạy bước R) |
| **TC-12.29** | Chuyển kiểm tra trước thất bại **ở bước 3** từ nhóm P sang nhóm C, với kỳ vọng `indeterminate`. Nhóm P chỉ còn các lỗi trước khi gọi `rename_replace` của bước 3: bước 1, bước 2a, kiểm tra trước của bước 2b, và tính hash. Nhóm B và C tách ba trường hợp: kiểm tra trước thất bại (`none`, `indeterminate`); primitive báo lỗi nhưng kiểm tra sau đạt; kiểm tra sau thất bại |
| **TC-12.35** | `replace_not_atomic`: kiểm tra trước đọc được đủ → `unchanged`. Thêm biến thể: không đọc được → `indeterminate` |
| **TC-12.38** | Thêm (j): tiêm lỗi đọc vào bước kiểm tra sau khởi động lại → lần thử bị xếp "không xác định", và đợt chạy **không đạt**. Thêm (k): bỏ bước kiểm tra sau khởi động lại → "không xác định". Áp dụng phân loại ba kết quả ở P1-4 |
| **TC-12.39** | Áp dụng phân loại ba kết quả. Báo cáo phải có số lần đạt, vi phạm và "không xác định". Đợt chạy đạt khi có 0 vi phạm và 0 "không xác định" |
| **TC-12.45** | Viết lại, xem bên dưới |
| **TC-12.48** | Viết lại thành luồng vòng đời, xem bên dưới |
| **TC-12.25** | Giữ phần đọc năng lực. Phần liên quan tới hồ sơ `revoked` chuyển sang TC-12.48 |

## TC-12.45 **[M]** (U): R12 và việc chuyển sự kiện (viết lại)

| Trường hợp | Bước | Kết quả mong đợi |
|---|---|---|
| (a) | `B_new` giống hệt commit cũ, rồi WE-3i, rồi bước R | Như v0.4.6: hai cách hiểu cho ra cùng byte, cùng `H_commit` và cùng tập bản ghi logic |
| (b) **R12-b** | Commit N có `outbox` {e1}. Thêm thao tác sinh ra e2, vào bộ nhớ. Lần ghi gặp WE-3i và trên đĩa vẫn là N. Bước R | Bộ chuyển chỉ nhận {e1}. **e2 không** có dòng nào trong kho, **không** nằm trong `confirmed_ids`, vẫn có trong `outbox` bộ nhớ. Lần ghi kế tiếp có `replaced`: e2 được chuyển và xác nhận; đúng 1 bản ghi logic |
| (c) **R12-a** | Lần ghi chứa {e1, e2} gặp WE-3i nhưng trên đĩa thực ra là bản mới. Sau đó thêm e3 vào bộ nhớ trước bước R | Bộ chuyển nhận {e1, e2} từ `B_disk`. **e3** không được chuyển cho tới commit kế tiếp |
| (d) | Như (b), nhưng app bị dừng trước lần ghi kế tiếp | e2 mất cùng trạng thái của nó (GS-12.4). Kho không có dòng nào của e2 |

Quy tắc: GS-12.2 (R12), GS-14.4, 14.5, 14.6.

## TC-12.48 **[M]** (U, có dùng mô phỏng pipeline): vòng đời hồ sơ thu hồi (viết lại)

| Bước | Kết quả mong đợi |
|---|---|
| 1. Hồ sơ R1 ở trạng thái `verified`. Tiêm một vi phạm, tạo log `rename_contract_violation` | R1 thành `suspended` trong bộ nhớ ngay lập tức; `storage_evidence_suspended` được ghi vào file cài đặt; log và tuyên bố hiện `assumed` |
| 2. Khởi động lại | R1 vẫn bị tạm ngưng, vì được đọc lại từ file cài đặt |
| 3. Như bước 2, nhưng việc ghi file cài đặt ở bước 1 đã thất bại | R1 dùng lại được cho tới vi phạm kế tiếp. Ghi nhận đây là giới hạn đã biết (R-23) |
| 4. Sổ bằng chứng thu hồi R1; chạy pipeline build kế tiếp | `revocation_list` có R1; nếu R1 vẫn được nhúng thì **build thất bại** |
| 5. Khởi động build mới với từng thứ tự tải hoặc lỗi: (i) bình thường; (ii) hồ sơ được nạp trước danh sách (giả lập lỗi thứ tự); (iii) danh sách thiếu; (iv) danh sách hỏng | (i) và (ii): R1 không được dùng (hiện thực bắt buộc theo thứ tự cố định, và (ii) phải bị từ chối hoặc vẫn ra cùng kết quả). (iii) và (iv): **toàn bộ** hồ sơ bị bỏ |
| 6. Chạy lại bộ kịch bản WE và WK ở mỗi bước trên | `state_after`, quyết định commit và kết quả khôi phục **giống hệt** nhau ở mọi bước |

Quy tắc: GS-12.8, 12.9, 12.10.

## Test mới

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-12.49 **[M]** | U | Khôi phục từ một `.bak` hợp lệ (`L.json` đã được lưu trữ); thêm vài thao tác; lần ghi đầu gặp WE-3i; bước R ra R0; lần ghi kế tiếp có `replaced`; rồi thêm một lần ghi nữa | Sau WE-3i và sau R0: `.bak` **không đổi byte nào**. `B_new` chứa trạng thái đã khôi phục **cộng** các thao tác, không phải trạng thái rỗng. Sau commit đầu: `.bak` **vẫn** không đổi. Sau lần ghi thứ hai: `.bak` mới là byte của `L.json` | GS-12.2 (R0), 13.4 |
| TC-12.50 **[M]** | U | R3 rồi ghi đè `L.json` từ bộ nhớ; trước đó đã có mục e được xoá khỏi `outbox` vì đã `confirmed@written`. Ba biến thể: (a) kho còn nguyên; (b) `power_loss()` trên mô hình làm mất dòng của e; (c) xoá file kho | (a): e có 1 bản ghi logic. (b) và (c): e **mất**, đúng như câu thay thế ở P1-2 và bảng GS-14.6; test **không** coi đây là lỗi hiện thực. Mọi mục còn trong `outbox` bộ nhớ có mặt trong `L.json` mới | GS-12.7, 14.6 |
| TC-12.51 **[M]** | U | `rename_noreplace` có kiểm tra trước thất bại, ở bước lưu trữ E3.1 và ở GS-14.9 | E3.1: `archive_failed`, dừng. GS-14.9: file `.pending-*` giữ nguyên, thử lại sau. Không có bước nào coi `indeterminate` là đổi tên thành công | GS-12.8, 13.4, 13.15, 14.9 |

---

# Ma trận đối chiếu v0.4.7

Chỉ ghi các dòng thay đổi so với v0.4.6.

| Mục | Quy tắc → test |
|---|---|
| 12 | 12.2: thêm **TC-12.45 (b–d), 12.49** · 12.7: thêm **TC-12.40 (WE-2b-p, WE-3p), 12.50** · 12.8: thêm **TC-12.35, 12.38 (j, k), 12.40, 12.48, 12.51** · 12.9: TC-12.20, 12.24, 12.25, 12.31, 14.31, 12.48 · 12.10: thêm **TC-12.39 (phân loại ba kết quả), 12.48** |
| 13 | 13.4: thêm **TC-12.49, 12.51** · 13.15: thêm **TC-12.51** |
| 14 | 14.4: thêm **TC-12.45 (b, c)** · 14.5: thêm **TC-12.45** · 14.6: thêm **TC-12.45 (d), 12.50** · 14.9: thêm **TC-12.51** |
| Cổng | Q1: TC-12.27, 12.28, 12.30, 12.39 (đạt khi 0 vi phạm và 0 "không xác định"); hồ sơ `revoked` hoặc `suspended` thì Q1 không đạt (TC-12.48) |

---

# Rà soát tham chiếu chéo sau khi sửa

| Chỗ đối chiếu | Kết quả |
|---|---|
| GS-12.8 ↔ GS-12.7 | `precheck_failed` nay cho ra `indeterminate` ở cả hai nơi (WE-2b-p, WE-3p). Không còn chỗ nào nói "`unchanged` vì không gọi primitive". `unchanged` luôn đòi bằng chứng tích cực |
| GS-12.8 ↔ GS-12.2 (bước R) | Bước R xử lý chung cho `indeterminate`, bất kể đến từ kiểm tra trước, primitive hay kiểm tra sau. `operation_effect` chỉ được ghi vào log, không thay đổi nhánh của bước R |
| GS-12.8 ↔ GS-13.4 E3.1, 13.15, 14.9 | `rename_noreplace` cho ra `indeterminate` thì được coi là đổi tên thất bại (TC-12.51) |
| GS-12.7 (P1-2) ↔ GS-14.6 | Cùng điều kiện và cùng các trường hợp mất. Không còn câu khẳng định tuyệt đối nào |
| GS-12.2 R12 ↔ GS-14.4 nguồn (a) | Bộ chuyển chỉ nhận `outbox` phân tích từ byte đã commit (`B_new` có `replaced`, `B_disk`, `H_read`). Không có đường nào đưa mục chỉ có trong bộ nhớ vào `confirmed_ids` |
| GS-12.2 R0 ↔ GS-13.4 E3.2 | `.bak` không bị chạm cho tới lần ghi thứ hai sau khi khôi phục; khớp với quy tắc "lần ghi đầu chỉ tạo `L.json`" |
| TC-12.38/39 ↔ hồ sơ GS-12.8 ↔ cổng Q1 | Cùng tiêu chí ba kết quả; hồ sơ chỉ được cấp khi 0 "không xác định" |
| R-22 (v0.4.6) | **Rút lại.** `precheck_failed` không còn dựa vào giả định chỉ có một tiến trình ghi để trả về `unchanged` |

**Lỗi tham chiếu đã sửa:** câu "(gồm cả `precheck_failed`)" ở hàng WE-2b và WE-3, cùng tiêu chí của TC-12.40 trong v0.4.6, mâu thuẫn với điều kiện đủ của `unchanged`. Cả hai đã được thay.

---

# Mức chắc chắn

- **Đã rà trên tài liệu, trong phiên này:** các bảng đối chiếu ở trên; lập luận về `confirmed_ids` ở R12; sự khớp nhau giữa P1-2 và GS-14.6.
- **Đã thử trên Linux ở các lượt trước:** không có gì mới. Lượt này không chạy thử nghiệm nào.
- **Giả định:**
  - chỉ có một tiến trình ghi (nay chỉ còn dùng cho `noreplace = check_then_rename` và cho việc dọn file tạm);
  - SHA-256 không đụng độ;
  - các giả định về iOS như ở v0.4.6;
  - pipeline build có thể nhúng và kiểm tra `revocation_list`.
- **Chưa kiểm chứng:** toàn bộ test cấp D. **Chưa có test nào được chạy.** Repo chưa có code Godot.

---

# Danh sách thay đổi so với v0.4.6

1. **GS-12.8:**
   - Thêm `operation_effect`; điều kiện của `unchanged` đòi bằng chứng tích cực.
   - Kiểm tra trước thất bại, hoặc thấy `src_missing`, nay cho ra `indeterminate`.
   - Đổi thứ tự: đọc trước, rồi mới xét năng lực.
   - `rename_noreplace` dùng cùng điều kiện.
   - Thêm vòng đời hồ sơ: sổ bằng chứng, `revocation_list`, thứ tự nạp, mặc định bỏ hồ sơ khi có lỗi, tạm ngưng cục bộ.
2. **GS-12.7:** thêm WE-2b-p và WE-3p; bỏ "(gồm cả `precheck_failed`)"; thay câu "Không mất sự kiện" bằng một câu có điều kiện.
3. **GS-12.2:**
   - R12 chỉ chuyển `E_disk`; tách hai tình huống R12-a và R12-b.
   - R0 ghi rõ `.bak` giữ nguyên và `B_new` lấy từ trạng thái đang tiếp tục.
4. **GS-14.4:** định nghĩa chặt nguồn (a); bộ chuyển không đọc `outbox` từ bộ nhớ.
5. **Tiêu chí của TC-12.38 và 12.39:** ba kết quả (đạt / vi phạm / không xác định); đợt chạy đạt khi 0 vi phạm và 0 "không xác định".
6. **Test:**
   - **Viết lại:** TC-12.45, 12.48.
   - **Sửa:** TC-12.25, 12.29, 12.35, 12.38, 12.39, 12.40.
   - **Mới:** TC-12.49, 12.50, 12.51.
   - Không bỏ test nào.

---

# Rủi ro còn lại

- **R-22:** rút lại (xem bảng tham chiếu chéo).
- **R-23 (mới):** việc tạm ngưng hồ sơ cục bộ chỉ là cố gắng. Nếu ghi file cài đặt thất bại, hồ sơ có thể được dùng lại cho tới vi phạm kế tiếp. Sổ bằng chứng mới là nơi thu hồi chính thức.
- **R-24 (mới):** WE-2b-p và WE-3p làm tăng số lần rơi vào bước R, và do đó tăng khả năng gặp R3 khi bộ nhớ đọc lỗi kéo dài. Hệ quả là `.bak` có thể cũ hơn (R-18).
- **Giữ nguyên:** R-1 đến R-21, trừ R-9 (đã chốt) và R-22 (đã rút). Đặc biệt R-8: thực tế chỉ đạt mức `written`, chưa có D3.

---

**Trạng thái repo**, đã kiểm tra thực tế trong lượt này bằng lệnh chỉ đọc:
- HEAD `8feed74` trên nhánh `claude/cloud-session-connection-check-hksw4v`; không có stash.
- `git status`, hash của phần thay đổi chưa commit và hash của các file chưa theo dõi đều trùng mốc đã ghi.
- Không có file nào trong repo bị tạo hay sửa.

Tôi dừng ở đây để bạn duyệt v0.4.7.
