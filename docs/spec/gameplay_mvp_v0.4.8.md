<!-- Lưu trữ nguyên văn bản đặc tả v0.4.8 từ phiên làm việc. Xem docs/spec/README.md để biết cách đọc. -->

# Đặc tả gameplay MVP v0.4.8 (các mục sửa)

**Phạm vi:**
- Bản này xử lý 4 điểm P1 bạn chặn duyệt và 3 điểm P2.
- Rà lại TC-12.38, 12.39, 12.45, 12.48 và ma trận.
- Mọi mục không ghi ở đây giữ nguyên v0.4.7. KT-1 đến KT-6 giữ nguyên.
- Không đụng tới gameplay hay schema level. **Không có quy tắc nào ở đây đã được kiểm chứng trên thiết bị.**

**Một hệ quả ngoài phạm vi 4 điểm:**
- Để thoát được vòng lặp ở P1-2 mà không bỏ qua bước kiểm tra trước, tôi phải định nghĩa thêm cách xử lý **lỗi I/O khi đọc file**.
- Việc này kéo theo thay đổi ở GS-13.4 (thêm loại `io_error`) và GS-14.9.
- Đây là thay đổi bắt buộc để giữ nhất quán. Tôi đánh dấu **[hệ quả]** ở từng chỗ.

---

## P1-1. Primitive báo thành công nhưng file không đổi

### GS-12.8: định nghĩa vi phạm hợp đồng (thay câu cũ về `rename_contract_violation`)

- **Vi phạm hợp đồng** xảy ra khi đủ cả ba điều kiện:
  - `primitive_result = ok`;
  - `postcheck = ok`;
  - `state_after ≠ replaced`.
- Vi phạm gồm hai dạng:

| Dạng | `state_after` | `err` |
|---|---|---|
| V-u | `unchanged` (có bằng chứng: `src` còn nguyên, `dst` khớp `pre_dst`) | `reported_ok_but_unchanged` |
| V-i | `indeterminate` (bước kiểm tra sau đọc được, nhưng trạng thái không khớp hai dạng hợp lệ) | `reported_ok_but_inconsistent` |

- **Không** tính là vi phạm:
  - `postcheck = failed` (không có bằng chứng);
  - primitive báo lỗi nhưng kết quả là `replaced`. Trường hợp này chỉ ghi log `rename_failed_but_replaced`.
- **Khi có vi phạm:**
  - Ghi log `rename_contract_violation{op, dạng, record_id}`.
  - `ok = false`, nên **không commit**.
  - Tạm ngưng (`suspended`) **toàn bộ hồ sơ** có chứa năng lực của thao tác đó (`atomic_replace` hoặc `noreplace`), theo P1-3.
- Áp dụng cho cả `rename_replace` lẫn `rename_noreplace`.

### GS-12.7: hàng mới

| Điểm | Kết quả | Xử lý |
|---|---|---|
| **WE-2b-v** | Bước 2b gặp V-u | Huỷ trước bước 3, cảnh báo. `.bak` = N−1, đã có bằng chứng. **Không** cần bước R |
| **WE-3v** | Bước 3 gặp V-u | **Không** commit, cảnh báo. `L.json` = N, đã có bằng chứng. Không cần bước R. Không chạy bộ chuyển sự kiện |
| WE-2b-i / WE-3i | Gặp V-i | Như các hàng `-i` hiện có, cộng thêm việc ghi log vi phạm và tạm ngưng hồ sơ |

---

## P1-2. Vòng lặp WE-3p → R3 → WE-3p

**Nguyên nhân:**
- Ở v0.4.7, bước kiểm tra trước đòi đọc được **nội dung** của `dst`.
- Nếu `L.json` bị hỏng vĩnh viễn (đọc ra lỗi I/O), mọi lần ghi đều dừng ở WE-3p.
- Bước R lại ra R3 vì không đọc được `L.json`. Vậy là không bao giờ ghi được nữa.

### GS-12.8: phân loại `pre_dst` (sửa)

| Kết quả đọc `dst` ở bước kiểm tra trước | `pre_dst` | Gọi primitive không |
|---|---|---|
| Không tồn tại (kiểm tra tồn tại thành công) | `absent` | Có |
| Tồn tại, đọc và tính được hash | `hash` | Có |
| Tồn tại (kiểm tra tồn tại thành công) nhưng **đọc lỗi** | `unreadable` | **Có** |
| Kiểm tra tồn tại thất bại, **hoặc** không đọc được `src`, **hoặc** hash của `src` khác `expected_src_hash` | — | **Không**: `precheck_failed`, `indeterminate` |

**Vì sao vẫn giữ đúng tinh thần kiểm tra trước, không phải bỏ qua nó:**
- Bước kiểm tra trước vẫn chạy và vẫn bắt buộc phải xác định được hai thứ: nội dung `src` sắp được đặt vào, và việc `dst` có tồn tại hay không.
- Khi `pre_dst = unreadable`, **không bao giờ** được kết luận `unchanged`, vì không có gì để so.
- Kết quả chỉ có thể là `replaced` (bước kiểm tra sau đọc được `dst` mới) hoặc `indeterminate`.
- Thay thế một file không đọc được là an toàn trong hai ngữ cảnh duy nhất mà nó xảy ra:
  - **Bước 3 sau R3:** trạng thái trong bộ nhớ chứa mọi mục `outbox` của mọi bản mà phiên này đã đọc làm mốc hoặc đã ghi (P1-2 của v0.4.7).
  - **Bước 2b:** `.bak` sắp được thay bằng bản sao của `L.json` hiện tại.

### GS-12.2: cờ đối soát và trạng thái tạm khoá ghi (mới)

**Cờ `needs_reconcile`** (trong bộ nhớ, theo phiên):
- **Được bật khi** một lần ghi kết thúc không có `replaced` vì một trong các lý do: WE-2b-i, WE-2b-p, WE-3i, WE-3p; hoặc WE-2a do **đọc `L.json` lỗi** ở bước 2a; hoặc mốc ban đầu có `L.json` ở loại `io_error` (GS-13.4).
- **Khi cờ đang bật**, lần ghi kế tiếp chạy bước R trước.
- **Cờ được tắt** khi có một lần ghi đạt `replaced`.

**Đếm lỗi và tạm khoá:**
- `k` là số lần ghi **liên tiếp** không đạt `replaced`, bất kể lý do. `k` trở về 0 khi có một lần `replaced`.
- **Khi k ≥ `SAVE_BLOCK_AFTER_FAILURES`** (mặc định 3), chuyển sang trạng thái **`save_blocked`**:
  - Hiện một banner cố định, không chặn thao tác: "Không lưu được tiến độ. Tiến độ hiện chỉ còn trong phiên này."
  - Ngừng ghi theo từng thao tác.
  - Chỉ thử lại **một lần ghi đầy đủ** theo giao thức, mỗi `SAVE_BLOCKED_RETRY_INTERVAL_S` (mặc định 30 giây), cùng với khi app xuống nền hoặc quay lại.
- **Mỗi lần thử lại:**
  - chạy bước R (nếu `needs_reconcile`), rồi bước 1–4;
  - **không bỏ qua** kiểm tra trước hay kiểm tra sau;
  - **không** coi là commit nếu không có `replaced`.
- **Thoát `save_blocked`** khi có một lần `replaced`: gỡ banner, chạy bộ chuyển sự kiện cho `B_new`.

**Trong lúc `save_blocked`:**
- Không file nào bị đổi ngoài những gì một lần thử đầy đủ có thể làm, theo đúng bảng WE.
- `outbox` trong bộ nhớ tiếp tục lớn lên.
- Bộ chuyển sự kiện **không** nhận mục nào chỉ có trong bộ nhớ (GS-14.4).
- `.bak` không bị chạm ở các lần thử đi theo R3 hoặc R0.

### GS-13.4 E1: loại `io_error` [hệ quả]

**Loại mới `io_error`:** E1 không đọc được byte của ứng viên vì lỗi I/O. Loại này khác `unreadable`, là trường hợp đọc được byte nhưng không phải JSON.

**Ứng viên `io_error`:**
- không được dùng làm nguồn;
- **không được lưu trữ**, vì không có `H_read` để làm `expected_src_hash`, nên được để nguyên tại chỗ;
- `outbox` của nó không chuyển được (GS-14.6 (b): không có bảo đảm).

**Khi `L.json` là `io_error`:**
- Mốc ban đầu có `H_commit = none` và bật `needs_reconcile`.
- Lần ghi đầu đi qua R3, và bước 3 thay `L.json` với `pre_dst = unreadable`.

**Khi `.bak` là `io_error`:**
- Để nguyên. Lần xoay `.bak` kế tiếp (bước 2b) thay nó với `pre_dst = unreadable`.

### GS-14.9: file `.pending-*` không đọc được (sửa) [hệ quả]

- **Đọc được byte nhưng nội dung hỏng:** `rename_noreplace` thành `.corrupt.<T>`, với `expected_src_hash` = hash của byte đã đọc.
- **Lỗi I/O khi đọc:** giữ nguyên file, ghi log `pending_io_error`, thử lại ở lần quét sau. Không đổi tên vì không có hash.

### 0.2 Tham số (thêm)

| Tham số | Mặc định |
|---|---|
| `SAVE_BLOCK_AFTER_FAILURES` | 3 |
| `SAVE_BLOCKED_RETRY_INTERVAL_S` | 30 giây |

---

## P1-3. Đọc danh sách `suspended` theo hướng fail-closed

### GS-12.8: tạm ngưng cục bộ (thay mục 3 của v0.4.7)

**Định dạng trường trong file cài đặt:**

```
storage_evidence_suspended: {state: "known", ids: [record_id…]}
                          | {state: "unknown", since: <UTC>}
```

**Khi khởi động**, đọc trường này **trước khi** bất kỳ hồ sơ nào được dùng:

| Tình huống | Kết quả trong phiên | Ghi lại vào file cài đặt |
|---|---|---|
| Trường hợp lệ, `state = known` (kể cả `ids` rỗng) | Áp dụng danh sách | — |
| Trường hợp lệ, `state = unknown` | **Mọi hồ sơ lưu trữ bị bỏ**, mức bằng chứng là `assumed` | Giữ nguyên `unknown` |
| **Cài mới:** không có file cài đặt, **và** không có `progress/`, **và** không có kho sự kiện | Coi danh sách là rỗng | Ghi `{state: "known", ids: []}` |
| Không có file cài đặt nhưng có `progress/` hoặc kho sự kiện; file cài đặt bị lỗi I/O; JSON hỏng; thiếu trường; trường sai kiểu | **Mọi hồ sơ lưu trữ bị bỏ**, `assumed`; ghi log `evidence_suspension_list_unavailable` | Ghi `{state: "unknown", since: now}`. Nếu ghi thất bại thì vẫn bỏ hồ sơ trong phiên; lần khởi động sau sẽ gặp lại đúng tình huống này |

**Thoát trạng thái `unknown`:**
- **Chỉ** khi cài một build mới có `build_id` khác **và** thời điểm chụp sổ bằng chứng của build đó muộn hơn `since`. Khi đó trường được đặt lại thành `{state: "known", ids: []}`.
- Lý do: danh sách thu hồi chính thức của build mới đã có cơ hội ghi nhận các vi phạm xảy ra sau `since`. Đổi lại, một nghi ngờ cục bộ chưa từng được báo lên sổ bằng chứng có thể bị mất (R-23).

**Khi có vi phạm trong phiên** (P1-1):
- Thêm `record_id` vào `ids` cả trong bộ nhớ lẫn trong file, bằng `write_file` + `rename_replace`.
- Nếu ghi thất bại, trong phiên vẫn coi hồ sơ là `suspended`.
- `state` không bao giờ chuyển từ `unknown` về `known` vì một lần ghi như vậy.

**Phân biệt với `revocation_list`:**
- `revocation_list` nằm trong build và là nguồn thu hồi chính thức. Nếu nó lỗi, bỏ **toàn bộ** hồ sơ.
- Danh sách `suspended` là cục bộ. Nếu nó lỗi, bỏ **toàn bộ hồ sơ lưu trữ** và giữ trạng thái `unknown` cho tới build mới.
- Cả hai đều mặc định coi như không có bằng chứng khi gặp lỗi.

---

## P1-4. Phân biệt `B_read` và `H_read`

### GS-13.4 E1 (sửa câu của v0.4.6)

| Ký hiệu | Định nghĩa | Thời gian giữ trong bộ nhớ |
|---|---|---|
| `B_read(c)` | Chính các byte đã đọc từ ứng viên c, tức các byte đã được đánh giá ở A–D | Tới khi E3 xong. Sau đó **bỏ** |
| `H_read(c)` | SHA-256 của `B_read(c)` | Suốt phiên. Dùng cho mốc `H_commit` và làm `expected_src_hash` khi lưu trữ c |
| `E_read(c)` | Danh sách `outbox` **được phân tích một lần từ `B_read(c)`** ở E1 | Tới khi bộ chuyển sự kiện xử lý xong nguồn đó |

- Mỗi ứng viên được đọc **đúng một lần**.
- Bộ chuyển và bước lưu trữ (GS-13.11) dùng `E_read(c)` và `H_read(c)`. **Không đọc lại file.**

### GS-14.4, nguồn (a) (sửa)

Danh sách mục được phân tích từ byte của một bản đã biết là commit, và chỉ gồm:
- `outbox` của `B_new` khi lần ghi có `replaced`;
- `outbox` của `B_disk` ở R12;
- **`E_read(nguồn đã chọn)`** ở E3.4, với nguồn là `L.json` hoặc `.bak`.

Hash (`H_*`) **không bao giờ** là đầu vào của bộ chuyển.

---

## P2

- **TC-12.39, 12.27, 12.28, 12.30: số lần tối thiểu.**
  - Phân loại ba kết quả (đạt / vi phạm / không xác định) áp dụng cho **cả bốn** test.
  - Một đợt chạy chỉ đạt khi: **mỗi trường hợp** có số lần "đạt" ≥ ngưỡng của test gốc; 0 vi phạm; 0 "không xác định".
  - Ngưỡng:
    - TC-12.27: 50 lần cho mỗi điểm WK;
    - TC-12.28: 100 lần;
    - TC-12.30: 100 lần;
    - TC-12.39: (a)–(d) mỗi trường hợp 100 lần; (e) 50 lần khởi động lại.
  - Không đủ ngưỡng thì đợt chạy **không đạt**.
- **TC-12.48 bước 5: chốt một hành vi duy nhất.** Bộ nạp bằng chứng là **một thủ tục duy nhất**:
  1. đọc `revocation_list`;
  2. đọc danh sách `suspended`;
  3. đọc các hồ sơ, rồi lọc.
  - Trước khi thủ tục này **hoàn tất**, mọi truy vấn năng lực đều trả về bằng chứng `assumed`. Không có API nào đọc được hồ sơ chưa qua lọc.
  - Nếu hồ sơ đến trước danh sách (giả lập thứ tự sai), hồ sơ chỉ được giữ ở trạng thái chờ và không dùng được, cho tới khi lọc xong.
- **Độ bền:** giữ nguyên. Không có `durable (verified)` khi chưa có D3, và việc này không phụ thuộc vào cổng Q1.

---

# Test case

## Test sửa

| ID | Thay đổi |
|---|---|
| **TC-12.38** | Thêm (l): primitive báo thành công nhưng mô hình không thực hiện gì → `unchanged`, `err = reported_ok_but_unchanged`, có log vi phạm, không commit. Thêm (m): `dst` tồn tại nhưng đọc lỗi → primitive vẫn được gọi; kết quả `replaced` hoặc `indeterminate`, **không bao giờ** `unchanged` |
| **TC-12.39** | Áp dụng ngưỡng tối thiểu ở P2. Nếu thấy dạng V-u trên thiết bị (báo thành công nhưng không đổi) thì tính là **vi phạm** |
| **TC-12.27, 12.28, 12.30** | Áp dụng phân loại ba kết quả và ngưỡng tối thiểu |
| **TC-12.40** | Phân biệt rõ: `dst` không đọc được nhưng kiểm tra tồn tại thành công → primitive **được** gọi (`pre_dst = unreadable`). Kiểm tra tồn tại thất bại, hoặc không đọc được `src` → `precheck_failed`, `indeterminate` |
| **TC-12.45** | Bổ sung kỳ vọng: đầu vào của bộ chuyển là danh sách phân tích từ byte (`B_disk`, `B_new`), không phải hash. Nhật ký truy cập có đúng một lần đọc `L.json` ở bước R |
| **TC-12.48** | Bước 5 thay bằng: (i) thứ tự bình thường; (ii) hồ sơ đến trước danh sách. Cả hai: không truy vấn nào trả về `verified` trước khi việc lọc hoàn tất; R1 không bao giờ được dùng. (iii)/(iv): danh sách thiếu hoặc hỏng → bỏ toàn bộ hồ sơ. Thêm bước 1b: vi phạm dạng V-u (P1-1) cũng dẫn tới `suspended`. Liên kết với TC-12.52 cho chiều **đọc** danh sách `suspended` |
| **TC-14.30** | Tách hai trường hợp: (a) nội dung hỏng → `.corrupt.<T>` với hash của byte đã đọc; (b) lỗi I/O → giữ nguyên file, ghi log `pending_io_error`, thử lại ở lần quét sau |

## Test mới

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-12.52 **[M]** | U | Đọc danh sách `suspended` ở các trường hợp: (a) `known` với `ids` rỗng; (b) `known` có R1; (c) `unknown`; (d) cài mới (không có file nào); (e) không có file cài đặt nhưng có `progress/`; (f) lỗi I/O; (g) JSON hỏng; (h) thiếu trường; (i) trường sai kiểu; (j) khởi động lại sau (e)–(i); (k) cài build mới có `build_id` khác, thời điểm chụp sổ muộn hơn `since`; (l) build mới nhưng thời điểm chụp sổ sớm hơn `since` | (a): hồ sơ dùng được. (b): R1 bị bỏ. (c), (e)–(i): **mọi** hồ sơ lưu trữ bị bỏ, `assumed`, có log; ghi `unknown` (trừ khi đã là `unknown`). (d): ghi `known` rỗng. (j): vẫn `unknown`. (k): đặt lại thành `known` rỗng. (l): vẫn `unknown`. Mọi trường hợp: `state_after` và quyết định commit giống hệt nhau | GS-12.8, 12.9 |
| TC-12.53 **[M]** | U | Khôi phục với nguồn `main`, và với nguồn `bak`; `outbox` có e1, e2 | Bộ chuyển nhận đúng {e1, e2} = `E_read` phân tích từ `B_read`. Nhật ký truy cập: mỗi ứng viên đọc **một lần**. Giả lập truyền nhầm `H_read` cho bộ chuyển → bị từ chối, vì kiểu dữ liệu sai hoặc có assert. `B_read` được giải phóng sau E3 | GS-13.4, 14.4 |
| TC-12.54 **[M]** | U | V-u ở bước 3, ở bước 2b, và ở `rename_noreplace` (lưu trữ) | Bước 3: WE-3v, không commit, không chạy bộ chuyển, `L.json` = N, cảnh báo. Bước 2b: WE-2b-v, không chạy bước 3. Lưu trữ: `archive_failed`. Cả ba: có log `rename_contract_violation`; hồ sơ liên quan thành `suspended` trong bộ nhớ và trong file cài đặt; nhãn `assumed` | GS-12.8, 12.7, 13.15 |
| TC-12.55 **[M]** | U | **Chuỗi lỗi kéo dài:** (a) đọc `.tmp` lỗi ở mỗi lần kiểm tra trước, gây WE-3p; bước R ra R3 vì `L.json` cũng đọc lỗi; lặp lại 5 lần, rồi bộ nhớ đọc được trở lại. (b) `L.json` bị lỗi I/O **vĩnh viễn** trong khi `.tmp` vẫn đọc được | (a): không lần nào commit trong lúc lỗi; tới k = 3 thì vào `save_blocked` (có banner, thử lại tối đa 1 lần mỗi 30 giây); bộ chuyển **không** nhận mục nào chỉ có trong bộ nhớ; `L.json` không bị chạm (`operation_effect = none`); `.bak` không đổi byte nào; sau khi đọc được trở lại: một lần `replaced`, gỡ banner, chuyển `outbox` của `B_new`. (b): bước 3 chạy với `pre_dst = unreadable` → `replaced` → thoát vòng lặp mà không bỏ qua kiểm tra trước | GS-12.2, 12.7, 12.8, 14.4 |
| TC-12.56 **[M]** | U | E1 gặp `io_error`: (a) ở `L.json`, với `.bak` hợp lệ; (b) ở `.bak`, với `L.json` hợp lệ; (c) ở cả hai | (a): nguồn `bak`, có thông báo; `L.json` **không** được lưu trữ; bật `needs_reconcile`; lần ghi đầu đi R3 rồi thay `L.json` với `pre_dst = unreadable`. (b): nguồn `main`; `.bak` để nguyên; lần xoay kế tiếp thay nó. (c): tạo tiến độ mới, `outcome = corrupt_fresh`, không file nào bị lưu trữ | GS-13.4, 12.2, 12.8 |

---

# Ma trận đối chiếu v0.4.8

Chỉ ghi các dòng thay đổi so với v0.4.7.

| Mục | Quy tắc → test |
|---|---|
| 0.2 | `SAVE_BLOCK_AFTER_FAILURES`, `SAVE_BLOCKED_RETRY_INTERVAL_S`: **TC-12.55** |
| 12 | 12.2: thêm **TC-12.55, 12.56** · 12.7: thêm **TC-12.54, 12.55** · 12.8: thêm **TC-12.38 (l, m), 12.40, 12.48, 12.52–12.56** · 12.9: thêm **TC-12.52** · 12.10: TC-12.27, 12.28, 12.30, 12.39 (ba kết quả cùng ngưỡng), 12.48 |
| 13 | 13.4: thêm **TC-12.53, 12.56** · 13.11: thêm **TC-12.53** (lưu trữ dùng `H_read`) · 13.15: thêm **TC-12.54** |
| 14 | 14.4: thêm **TC-12.45, 12.53, 12.55** · 14.6: thêm **TC-12.56** (`io_error` không có bảo đảm) · 14.9: thêm **TC-14.30 (a, b)** |
| Cổng | Q1: TC-12.27, 12.28, 12.30, 12.39. Đạt khi đủ ngưỡng, 0 vi phạm, 0 "không xác định". Hồ sơ `revoked`/`suspended`/`unknown` thì Q1 không đạt (TC-12.48, 12.52) |

---

# Rà soát tham chiếu chéo

| Chỗ đối chiếu | Kết quả |
|---|---|
| GS-12.8 (vi phạm V-u, V-i) ↔ GS-12.7 (WE-2b-v, WE-3v) ↔ GS-12.8 (tạm ngưng) | Vi phạm luôn dẫn tới: không commit, ghi log, tạm ngưng hồ sơ. `unchanged` vẫn đòi bằng chứng. Nhánh `-v` không cần bước R vì trạng thái đã có bằng chứng |
| GS-12.8 (`pre_dst = unreadable`) ↔ R3 ↔ GS-13.4 (`io_error`) ↔ GS-14.9 | File không đọc được nhưng biết là tồn tại thì được thay khi ghi tiến độ. Nó **không** được lưu trữ (không có hash) và **không** được dùng làm nguồn. Ba nơi đều thống nhất |
| `needs_reconcile` / `save_blocked` ↔ GS-14.4 | Không đường nào đưa mục chỉ có trong bộ nhớ vào bộ chuyển, kể cả lúc đang `save_blocked` |
| `B_read` / `H_read` / `E_read` ↔ GS-13.4, 13.11, 14.4 | Hash chỉ làm mốc và làm `expected_src_hash`. Danh sách sự kiện chỉ lấy từ byte. Không đọc lại file |
| Bộ nạp bằng chứng ↔ TC-12.48 ↔ TC-12.52 | Một thủ tục duy nhất; mọi truy vấn trước khi nạp xong đều trả về `assumed`; cả hai danh sách đều mặc định bỏ bằng chứng khi có lỗi |
| Ba kết quả và ngưỡng ↔ hồ sơ ↔ Q1 | Thống nhất trên cả bốn test cấp D của Q1 |

**Trạng thái file mới được liệt kê trong bản này:**
- ứng viên `io_error`;
- `dst` tồn tại nhưng không đọc được;
- file `.pending-*` bị lỗi I/O;
- danh sách `suspended` ở trạng thái `unknown`.

---

# Mức chắc chắn

- **Đã rà trên tài liệu, trong phiên này:** các bảng ở trên; lập luận vì sao thay một `dst` không đọc được là an toàn ở hai ngữ cảnh đã nêu.
- **Đã thử trên Linux ở các lượt trước:** không có gì mới. **Lượt này không chạy thử nghiệm nào.**
- **Giả định:**
  - phân biệt được "kiểm tra tồn tại thành công" với "đọc lỗi", tức là `FileAccess.file_exists` hoạt động độc lập với việc đọc (chưa xác minh trên iOS);
  - pipeline build có `build_id` và thời điểm chụp sổ bằng chứng;
  - chỉ có một tiến trình ghi;
  - SHA-256 không đụng độ;
  - các giả định về iOS như ở v0.4.7.
- **Chưa kiểm chứng:** toàn bộ test cấp D. **Chưa có test nào được chạy.** Repo chưa có code Godot.

---

# Danh sách thay đổi so với v0.4.7

1. **GS-12.8:**
   - Định nghĩa vi phạm hợp đồng với hai dạng V-u (báo thành công nhưng không đổi) và V-i; thêm hai giá trị `err`.
   - Thêm `pre_dst = unreadable`: primitive vẫn được gọi, nhưng không bao giờ cho ra `unchanged`.
   - Danh sách `suspended` có hai trạng thái `known`/`unknown`, bảng đọc mặc định bỏ bằng chứng khi lỗi, và điều kiện thoát `unknown`.
   - Bộ nạp bằng chứng là một thủ tục duy nhất.
2. **GS-12.7:** thêm WE-2b-v và WE-3v; nhánh V-i đi theo các hàng `-i`.
3. **GS-12.2:**
   - Thêm cờ `needs_reconcile`, bộ đếm `k` và trạng thái `save_blocked`, cùng hai tham số mới.
   - Lần thử lại luôn chạy đủ giao thức.
4. **GS-13.4:**
   - Định nghĩa `B_read`, `H_read`, `E_read`.
   - **[hệ quả]** Thêm loại `io_error`.
5. **GS-14.4:** nguồn (a) dùng `E_read`; hash không bao giờ là đầu vào của bộ chuyển.
6. **GS-14.9 [hệ quả]:** tách nội dung hỏng khỏi lỗi I/O.
7. **Test:**
   - **Sửa:** TC-12.27, 12.28, 12.30, 12.38, 12.39, 12.40, 12.45, 12.48, 14.30.
   - **Mới:** TC-12.52–12.56.
   - Không bỏ test nào.

---

# Rủi ro còn lại

- **R-23 (sửa):** nghi ngờ cục bộ có thể mất khi thoát trạng thái `unknown` bằng một build mới, nếu nó chưa từng được báo lên sổ bằng chứng. Ngoài ra, một lần ghi `suspended` thất bại chỉ có hiệu lực trong phiên đó.
- **R-25 (mới):** ở `save_blocked`, người chơi có thể chơi tiếp trong khi tiến độ chỉ còn trong bộ nhớ. Banner là cách duy nhất để báo cho họ. Có nên chặn thao tác hay không là **quyết định sản phẩm**, cần bạn chốt.
- **R-26 (mới):** thay một `L.json` không đọc được thì mất luôn nội dung của nó cho việc điều tra sau này. File `io_error` cũng không được lưu trữ.
- **R-27 (mới):** việc phân biệt "tồn tại nhưng đọc lỗi" với "không kiểm tra được sự tồn tại" phụ thuộc vào API Godot trên iOS. Đây là điểm chưa xác minh, cần thêm vào bảng API của GS-12.10.
- **Giữ nguyên:** R-1 đến R-21 và R-24, trừ R-9 (đã chốt) và R-22 (đã rút). Đặc biệt R-8: thực tế chỉ đạt mức `written`, chưa có D3.

---

**Trạng thái repo**, đã kiểm tra thực tế trong lượt này bằng lệnh chỉ đọc:
- HEAD `8feed74` trên nhánh `claude/cloud-session-connection-check-hksw4v`; không có stash.
- `git status`, hash của phần thay đổi chưa commit và hash của các file chưa theo dõi đều trùng mốc đã ghi.
- Không có file nào trong repo bị tạo hay sửa.

Tôi dừng ở đây để bạn duyệt v0.4.8. Điểm cần bạn quyết là R-25: khi `save_blocked`, có chặn thao tác hay chỉ hiện banner.
