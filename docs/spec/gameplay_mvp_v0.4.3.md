<!-- Lưu trữ nguyên văn bản đặc tả v0.4.3 từ phiên làm việc. Xem docs/spec/README.md để biết cách đọc. -->

# Đặc tả gameplay MVP v0.4.3 (bản chốt để duyệt)

**Phạm vi:**
- Chỉ các mục dưới đây thay đổi; mọi mục khác giữ nguyên như v0.4.2.
- Bản này **không** tuyên bố đã xác minh bất kỳ API iOS hay độ bền lưu trữ nào trên thiết bị.

---

## 0. Quyết định kiến trúc (cập nhật)

| Mã | Quyết định |
|---|---|
| KT-1 | Giữ `content/catalog.json` cho metadata nội dung |
| KT-2 | Giữ schema level v1 |
| KT-3 | Thiếu metadata chứng minh tương thích màu thì **không** khôi phục tiến độ cũ (`stale_palette_unverified`) |
| KT-4 **(mới)** | Hiện thông báo không chặn **mỗi khi `source = bak`** (GS-13.14). **Không** thêm bộ đếm commit vào GS-12.3 và **không** đổi `save_version` chỉ để tránh báo thừa. Chấp nhận báo thừa |
| KT-5 **(mới)** | Mọi thao tác file đi qua giao diện `StorageBackend` (GS-12.8). Backend mặc định dùng API có sẵn của Godot. **Chỉ** chọn native plugin khi cổng kiểm chứng GS-12.10 không đạt |
| KT-6 **(mới)** | Tuyên bố độ bền chỉ ở mức mà backend thực sự đạt được và đã được kiểm chứng (GS-12.9). GS-12.4 giữ nguyên: mục tiêu không áp dụng cho trường hợp mất nguồn |

## 0.1 Thuật ngữ (mới; dùng thống nhất trong toàn bộ đặc tả)

| Thuật ngữ | Nghĩa | Chịu được |
|---|---|---|
| `written` | Lệnh ghi, flush, close (hoặc rename) đều báo thành công. Dữ liệu đã được giao cho hệ điều hành, nhưng có thể vẫn nằm trong bộ đệm của kernel | Giả định chịu được app bị dừng; cần kiểm chứng ở TC-12.27. Không chịu được mất nguồn hay khởi động lại cưỡng bức |
| `durable` | Dữ liệu (và bản ghi thư mục, nếu là rename) đã được thiết bị lưu trữ ghi bền, bằng một primitive **đã được kiểm chứng** | Mất nguồn, trong giới hạn của phần cứng |
| `committed` | Bước 3 của GS-12.2 (đổi tên `.tmp` thành `L.json`) báo thành công. Mức bền của commit bằng mức bền của backend | Như mức bền của backend |
| `confirmed` | Trạng thái logic của bộ chuyển sự kiện (GS-14.4): dòng đã đạt **mức bền của backend** và không có lỗi nào xen giữa | Như mức bền của backend |

- **Quy tắc:** không văn bản, log hay test nào được dùng `durable` cho dữ liệu chỉ đạt `written`.
- **Từ "sync"** trong v0.4.2 nay có nghĩa là lời gọi `sync_file` hoặc `sync_dir` của backend. Mức mà lời gọi đó thực sự đạt được do backend báo cáo.

---

## 12. Lưu tiến độ

### GS-12.2 (sửa cách diễn đạt; giữ nguyên các bước)

- Các bước 1–4 gọi qua backend:
  - Bước 1: `write_file`.
  - Bước 2: `copy_file`, sau đó `rename_replace`.
  - Bước 3: `rename_replace`.
  - Bước 4: `sync_dir`.
- Bước 3 thành công nghĩa là đã **`committed`**. Commit chỉ được gọi là `durable` khi backend có `file_sync = durable` **và** `dir_sync = durable`.

### GS-12.7 (giữ nguyên bảng WE và WK; thêm 2 câu)

- Với backend mặc định, `sync_dir` dự kiến trả về `unsupported` (xem GS-12.10).
  - WE-4 khi đó là **đường đi bình thường**: chỉ ghi log `dir_sync_unsupported` một lần mỗi lần chạy app.
  - Bước 4 trả về `failed` (khác với `unsupported`) vẫn được xử lý theo hàng WE-4.
- Lỗi "sync `.tmp`" (WE-1b) với backend mặc định nghĩa là: flush, close hoặc `get_error()` báo lỗi, hoặc bước đọc lại để kiểm tra phát hiện sai lệch (GS-12.8).

### GS-12.8 Giao diện `StorageBackend` (mới)

- **Phạm vi áp dụng:** gameplay, khôi phục và bộ chuyển sự kiện **không bao giờ** gọi trực tiếp `FileAccess` hay `DirAccess`. Mọi lời gọi đều đi qua giao diện này.
- **Thứ tự thực thi:** mọi thao tác chạy tuần tự trên **một hàng đợi duy nhất**. Như vậy chỉ có một tiến trình ghi, kể cả khi bộ chuyển xử lý file `.pending-*` của level khác.

**Các thao tác.** Mỗi thao tác trả về `{ok, level: written|durable, err}`.

| Thao tác | Yêu cầu |
|---|---|
| `capabilities()` | Trả về `{file_sync, dir_sync: none\|written\|durable\|unsupported, atomic_replace: verified\|assumed}`. Giá trị là **mức đã kiểm chứng** cho cặp backend + nền tảng đó (GS-12.10), không phải mức mong muốn |
| `read_file(path)` | Đọc toàn bộ file |
| `write_file(path, bytes, verify)` | Mở với chế độ ghi đè (truncate), ghi, flush, `sync_file` ở mức backend, close. Nếu `verify` bật: đọc lại và so SHA-256 |
| `copy_file(src, dst)` | Như `write_file` với nội dung của `src` |
| `rename_replace(src, dst)` | Thay thế atomic `dst` |
| `rename_noreplace(src, dst)` | Không bao giờ ghi đè. Backend mặc định thực hiện "kiểm tra tồn tại rồi đổi tên", hợp lệ vì chỉ có một tiến trình ghi |
| `append_line(path, bytes)` | Ghi nối vào cuối file. Tự chèn `\n` nếu file chưa kết thúc bằng `\n` (GS-14.5) |
| `sync_file(path)` | Đưa dữ liệu đã ghi lên mức của backend |
| `sync_dir(dir)` | Có thể trả về `unsupported` |
| `delete(path)`, `list(dir)` | — |

**Các backend:**

| Backend | Vai trò |
|---|---|
| `GodotFileBackend` | Mặc định. Dùng `FileAccess` và `DirAccess` của Godot |
| `FaultInjectingBackend` | Chỉ có trong build test. Bọc một backend khác và cung cấp: (a) các điểm WK, WE, EA, ES, AK; (b) **mô hình hai lớp**: lớp `written` và lớp `durable`, với hai thao tác giả lập là `crash()` (giữ lớp `written`) và `power_loss()` (chỉ giữ lớp `durable`, có thể cắt dở dòng cuối của file kho); (c) **nhật ký truy cập** theo từng đường dẫn, để test kiểm được câu "không đọc, không mở" |
| `NativeDurableBackend` | **Chỉ làm khi** cổng GS-12.10 không đạt. Dùng `fsync`, hoặc `fcntl(F_FULLFSYNC)` trên Apple, cùng với sync thư mục |

- **Đọc lại để kiểm tra (`verify`):**
  - Tắt theo mặc định.
  - Bật cho file tiến độ nếu TC-12.29 cho thấy lỗi ghi không được phát hiện qua giá trị trả về.
  - Đây là cách xử lý **đầu tiên**, phải thử trước khi xét tới native.

### GS-12.9 Tuyên bố độ bền (mới)

- Bảo đảm của GS-12.4, GS-14.6 và các bất biến của GS-12.7 được phát biểu **theo mức của backend**:
  - **Mức `written`:** chịu được app bị dừng, **với điều kiện** TC-12.27 và TC-12.28 đạt. Không có bảo đảm khi mất nguồn hoặc khởi động lại cưỡng bức. Lần commit gần nhất, kể cả các sự kiện `confirmed` mà nguồn của chúng đã được dọn, có thể mất.
  - **Mức `durable`:** chịu thêm được mất nguồn, trong giới hạn phần cứng và chỉ khi đã được kiểm chứng.
- Trước khi TC-12.26 đến 12.32 chạy trên thiết bị:
  - `capabilities()` của `GodotFileBackend` trên iOS được đặt ở mức `file_sync = written` và `atomic_replace = assumed`;
  - mọi bảo đảm được coi là **giả định thiết kế**.

### GS-12.10 Kiểm chứng API và cổng chọn backend (mới)

**Phiên bản mục tiêu:**
- Ghim **Godot 4.4.1-stable** cho MVP.
- Phiên bản iOS tối thiểu lấy theo export template 4.4.1, cần đọc khi tạo project.
- Thiết bị test: ít nhất một máy chạy iOS mới nhất và một máy chạy phiên bản tối thiểu được hỗ trợ.
- Chạy lại toàn bộ bộ kiểm chứng khi đổi bản Godot, đổi phiên bản iOS lớn, hoặc đổi backend.

**API cần xác minh trên iOS:**

| API (4.4.1) | Câu hỏi cần trả lời |
|---|---|
| `FileAccess.open(path, WRITE)` | Có truncate không; có chạy trên `user://` của iOS không |
| `FileAccess.store_string` / `store_buffer` (trả về `bool`) | Có báo `false` khi đầy bộ nhớ không |
| `FileAccess.flush()` (trả về `void`) và `get_error()` | flush có gọi `fsync` hoặc `F_FULLFSYNC` không; lỗi ghi có hiện ra qua `get_error()` không |
| `FileAccess.close()` | Lỗi phát sinh lúc close có được báo không |
| `FileAccess.open(path, READ_WRITE)` cùng `seek_end()` | Có dùng được để ghi nối vào kho sự kiện không |
| `DirAccess.rename_absolute()` (trả về `Error`) | Có thay thế atomic file đích đã tồn tại trên APFS không |
| `DirAccess.copy_absolute()` | Có sync không; báo lỗi thế nào |
| `DirAccess.remove_absolute()`, `get_files_at()` | Hoạt động bình thường trong thư mục `user://` |
| `OS.get_user_data_dir()` | Thư mục nằm ở đâu trên iOS; dữ liệu có còn sau khi cập nhật app không |
| `OS.crash()` | Có dùng được để giả lập WK trong build test trên thiết bị không |

**Cách xác minh:**
1. Đọc mã nguồn của 4.4.1 ở hai chỗ: driver file Unix, và phần iOS chọn driver nào.
2. Theo dõi system call bằng `fs_usage` khi chạy trên iOS Simulator, trên máy Mac.
3. Chạy test hành vi trên thiết bị thật: TC-12.26 đến 12.32.

Simulator không thay thế được thiết bị thật.

**Cổng chọn backend:**

| Mã | Yêu cầu | Đạt khi | Hệ quả nếu không đạt |
|---|---|---|---|
| Q1 (bắt buộc) | Chịu được app bị dừng | TC-12.27, 12.28, 12.30 đạt với `GodotFileBackend` | Chọn `NativeDurableBackend` |
| Q2 (bắt buộc) | Phát hiện được lỗi ghi | TC-12.29 đạt, kể cả khi phải bật `verify` | Chọn native nếu `verify` vẫn không đủ |
| Q3 (thông tin, **không** phải cổng) | Chịu được mất nguồn | Ghi nhận kết quả TC-12.31 | Đưa ra quyết định sản phẩm sau MVP; tuyên bố ở mức `written` (GS-12.9) |

---

## 13. Khôi phục

### GS-13.3 (viết lại ý về ngoại lệ)

Ngoại lệ dành cho bộ chuyển sự kiện (GS-14.9) đối với file của **level khác**:

- **Chỉ được phép:**
  - (a) `list` thư mục `progress/` để tìm các tên khớp mẫu `<id>.json[.bak].pending-{stale,corrupt}.<UTC>[-n]`;
  - (b) `read_file` **chính file `.pending-*` đó**, và chỉ dùng trường `outbox`;
  - (c) `rename_noreplace` **chính file đó**, đổi `.pending-X.<UTC>` thành `.X.<UTC>`, hoặc thành `.corrupt.<UTC>` nếu file không đọc được.
- **Cấm:**
  - mở, đọc, ghi, đổi tên hay xoá `<id>.json`, `<id>.json.bak`, các file tạm, file `.stale` hay `.corrupt` của level khác;
  - ghi vào file `.pending-*`;
  - xoá file `.pending-*`;
  - dùng file `.pending-*` làm tiến độ;
  - chạy bước E0 (dọn file tạm) cho level khác.

### GS-13.14 (sửa phần căn cứ)

- Giữ nguyên quy tắc và văn bản thông báo.
- Bỏ câu đề xuất thêm bộ đếm commit; thay bằng tham chiếu **KT-4**.

---

## 14. Sự kiện

### GS-14.4 (sửa bước 3 và 4)

- **Bước 3:** gọi `sync_file` của backend.
- **Bước 4:** khi `sync_file` thành công, các dòng tương ứng đạt `confirmed` ở **mức của backend**.
- Với `GodotFileBackend`, `confirmed` nghĩa là `written`, cộng với điều kiện không có lỗi xen giữa. Nó **không** có nghĩa là `durable`.
- `ES` là bất kỳ lỗi nào do `sync_file` báo về.

### GS-14.6 (bổ sung)

- Bảo đảm "ít nhất một dòng, đúng một bản ghi logic" có hiệu lực **ở mức bền của backend** (GS-12.9).
- Ở mức `written`: khi mất nguồn, có thể mất các dòng `confirmed` mà nguồn của chúng đã được dọn.

### GS-14.9 (sửa một câu)

- Quyền xử lý file của level khác **chỉ** gồm những gì liệt kê trong ngoại lệ ở GS-13.3.

---

# Test case

## Test sửa

| ID | Thay đổi |
|---|---|
| TC-12.15–12.22 | Chạy qua `FaultInjectingBackend`. Kỳ vọng giữ nguyên |
| TC-12.20 | Thêm trường hợp (c): `sync_dir` trả về `unsupported` thì chỉ ghi log một lần mỗi lần chạy app, không hiện cảnh báo |
| TC-14.22–14.25 | `ES` được tiêm qua backend. Kỳ vọng giữ nguyên |
| **TC-14.29** | Xem bảng dưới |

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-14.29 **[M]** (sửa) | U | Khi khởi động có các file `other_01.json`, `other_01.json.bak`, `other_01.json.stale.<T0>` và `other_01.json.pending-stale.<T>`; level đang mở là L. Chạy ba trường hợp: (a) kho hoạt động; (b) kho lỗi (EA/ES); (c) file `.pending` không đọc được | (a) Chuyển `outbox` rồi đổi tên thành `.stale.<T>`. (b) File `.pending` không đổi byte nào. (c) Đổi thành `.corrupt.<T>`. **Cả ba trường hợp:** nhật ký truy cập **không** có lần mở hoặc đọc nào tới `other_01.json`, `.bak` hay `.stale.<T0>`; ba file đó không đổi byte; không có lần ghi nào vào file `.pending`; file `.pending` không được dùng làm tiến độ | GS-14.9, 13.3 |

## Test mới

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-12.23 **[M]** | U | Kiểm tra tĩnh mã nguồn | Không có `FileAccess.`/`DirAccess.` ngoài các file backend | GS-12.8 |
| TC-12.24 **[M]** | U | Mô hình hai lớp: commit N+1 rồi `crash()`; commit N+1 rồi `power_loss()` khi backend ở mức `written` | `crash()` cho ra N+1. `power_loss()` cho ra một trạng thái hợp lệ (N, N+1, `.bak` hoặc tạo mới) với thông báo đúng; không crash | GS-12.9, 12.7 |
| TC-12.25 **[M]** | U | Gọi `capabilities()` của `GodotFileBackend` khi chưa có kết quả kiểm chứng | `file_sync = written`, `atomic_replace = assumed`, không bao giờ là `durable`; mọi log và chẩn đoán không dùng chữ `durable` | GS-12.9 |
| TC-12.26 **[D]** | D | Kiểm chứng API trên Simulator (`fs_usage`) và đọc mã nguồn 4.4.1 | Có báo cáo cho từng API trong bảng GS-12.10; `capabilities()` được cập nhật đúng theo kết quả. **Đạt** khi đã có báo cáo; báo cáo không tự kết luận hành vi trên thiết bị | GS-12.10 |
| TC-12.27 **[D]** | D | Trên thiết bị: mỗi điểm WK-1..5 dừng bằng `OS.crash()` 50 lần | 250/250 kết quả đúng bảng GS-12.7; 0 lần `L.json` không hợp lệ; 0 lần dùng file tạm | GS-12.2, 12.4, 12.10, 13.13 |
| TC-12.28 **[D]** | D | Vòng lặp 1000 commit, dừng app ở thời điểm ngẫu nhiên, lặp 100 lần | `L.json` luôn hợp lệ, hoặc được khôi phục đúng GS-13.4; không lần nào mất quá 1 commit | GS-12.4, 12.10 |
| TC-12.29 **[D]** | D | Làm đầy bộ nhớ thật của thiết bị | 100% số lần ghi lỗi được phát hiện **trước** bước đổi tên (qua giá trị trả về, `get_error` hoặc `verify`); `L.json` không bao giờ bị cắt cụt | GS-12.7, 12.8, 12.10 |
| TC-12.30 **[D]** | D | Ghi nối vào kho sự kiện, dừng app giữa lúc ghi, lặp 100 lần | Dòng ghi dở bị phát hiện qua `crc32`; không dòng hợp lệ nào bị hỏng; khử trùng logic đúng | GS-14.5, 12.10 |
| TC-12.31 **[D]** | D | Khởi động lại cưỡng bức thiết bị trong lúc vòng lặp ghi đang chạy, lặp 20 lần | **Chỉ ghi nhận (Q3), không chấm đạt hay không đạt về độ bền:** số commit bị mất, số lần `L.json` không hợp lệ, các `outcome`. **Bắt buộc:** không crash và `outcome` luôn là một giá trị đã định nghĩa | GS-12.9, 12.10 |
| TC-12.32 **[D]** | D | Cập nhật app đè lên bản cũ; đưa app xuống nền rồi để hệ thống thu hồi | Vị trí `user://` được ghi lại; tiến độ còn nguyên | GS-12.10 |

---

# Ma trận đối chiếu v0.4.3

Chỉ ghi các dòng thay đổi so với v0.4.2. Mọi dòng khác giữ nguyên v0.4.2.

| Mục | Quy tắc → test |
|---|---|
| 12 | 12.2: TC-12.7, 12.11, 12.12, 12.14, 12.16, 12.19–12.21, **12.27**, 14.6 · 12.4: TC-12.1, 12.2, **12.27, 12.28** · 12.7: TC-12.12, 12.15–12.20, 12.22, **12.24**, 13.37, 14.28 · **12.8: TC-12.23, 12.29** · **12.9: TC-12.24, 12.25, 12.31** · **12.10: TC-12.26–12.32** |
| 13 | 13.3: TC-13.15, 13.19, 13.27, 13.31, 13.32, **14.29 (a–c)** · 13.13: TC-12.7, 12.11–12.13, 12.21, **12.27**, 14.6 |
| 14 | 14.5: TC-13.25, 13.33, 14.4, 14.8, 14.9, 14.11, 14.17, 14.24, 14.26, **12.30** · 14.6: TC-14.2, 14.6–14.9, 14.14, 14.23, 14.24, **12.24** · 14.9: TC-13.30, 14.17, 14.18, 14.21, 14.23, **14.29 (a–c)**, 14.30 |

---

# Rà soát cuối: phân loại theo mức chắc chắn

**A. Đã kiểm tra trên tài liệu đặc tả (trong phiên này):**
- Mọi GS mới hoặc sửa (12.2, 12.7–12.10, 13.3, 13.14, 14.4, 14.6, 14.9) đều có test trong ma trận.
- Mọi TC mới hoặc sửa (12.23–12.32, 14.29) đều trỏ tới GS có thật.
- Các thuật ngữ `written`, `confirmed`, `durable`, `committed` được dùng nhất quán. Ba chỗ trong v0.4.2 viết "sync thành công" như thể đã ghi bền nay được ràng buộc theo mức của backend: GS-12.2, GS-14.4, GS-14.6.
- KT-4 nhất quán với GS-13.14 và R-9.
- TC-14.29 khớp từng ý với ngoại lệ của GS-13.3.

**B. Đã kiểm tra thực nghiệm trong phiên này, chỉ trên Linux** (Godot 4.4.1-stable, bản x86_64 headless, trong container). Đây **không** phải bằng chứng về iOS.
- Dump tài liệu lớp: `flush()` trả về `void`; `store_string` và `store_buffer` trả về `bool`; `rename_absolute` trả về `Error`.
- Theo dõi bằng strace, chạy trong scratchpad:
  - `open(WRITE)` dùng `O_WRONLY|O_CREAT|O_TRUNC`;
  - `store_string` chưa gọi `write()`, nghĩa là dữ liệu được đệm trong app;
  - `flush()` gọi `write()` và **không** gọi `fsync` hay `fdatasync`;
  - `rename_absolute` gọi `rename(2)`;
  - không có API nào để sync thư mục.
- Từ đó suy ra: nếu bản iOS dùng cùng driver Unix, thì `GodotFileBackend` chỉ đạt mức `written`. Điều này **chưa được xác minh trên iOS**.

**C. Giả định thiết kế, chưa được xác minh:**
- Bản iOS của Godot 4.4.1 dùng cùng driver file như bản Linux.
- `rename` trên APFS thay thế file đích một cách atomic.
- Dữ liệu ở mức `written` còn nguyên sau khi app bị dừng hoặc bị hệ thống thu hồi.
- `get_error()` hoặc giá trị trả về phản ánh được lỗi đầy bộ nhớ.
- Ghi nối bằng `READ_WRITE` + `seek_end` hoạt động đúng.
- Chỉ có một tiến trình ghi vào `progress/`.
- Đồng hồ UTC đủ tốt để đặt tên file; trường hợp trùng tên đã được xử lý.
- Mô hình hai lớp của `FaultInjectingBackend` phản ánh đúng hành vi thật.

**D. Phải kiểm chứng trên thiết bị thật:** toàn bộ TC-12.26 đến 12.32, cùng với TC-12.1, 12.2, 12.3 (đều là cấp D). Chưa test nào trong số này đã chạy. **Repo hiện chưa có code Godot nào, nên chưa có TC nào được thực thi.**

---

# Danh sách thay đổi so với v0.4.2

1. **Quyết định kiến trúc:** thêm KT-4 (thông báo `.bak`, không có bộ đếm commit), KT-5 (giao diện backend; native chỉ khi cổng không đạt), KT-6 (tuyên bố đúng mức bền).
2. **Thuật ngữ:** định nghĩa `written`, `durable`, `committed`, `confirmed`.
3. **Quy tắc mới:**
   - GS-12.8: giao diện `StorageBackend`, ba backend, mô hình hai lớp, nhật ký truy cập, tuỳ chọn `verify`.
   - GS-12.9: tuyên bố độ bền theo mức của backend.
   - GS-12.10: phiên bản mục tiêu, bảng API cần xác minh, cách xác minh, cổng Q1, Q2 và Q3.
4. **Quy tắc sửa:**
   - GS-12.2, GS-12.7: thêm trường hợp `dir_sync_unsupported` và định nghĩa WE-1b cho backend mặc định.
   - GS-13.3: liệt kê chính xác thao tác được phép và bị cấm.
   - GS-13.14: căn cứ theo KT-4.
   - GS-14.4, 14.6, 14.9: đặt `confirmed` theo mức của backend; giới hạn quyền xử lý file.
5. **Test:**
   - **Mới:** TC-12.23 đến 12.25 (U), TC-12.26 đến 12.32 (D).
   - **Sửa:** TC-14.29 (thêm a–c và nhật ký truy cập), TC-12.20 (thêm trường hợp c).
   - TC-12.15–12.22 và TC-14.22–14.25 nay chạy qua `FaultInjectingBackend`, kỳ vọng giữ nguyên.
   - Không bỏ test nào.

---

# Rủi ro còn lại

- **R-8 (viết lại):** bằng chứng trên Linux cho thấy API có sẵn của Godot 4.4.1 không gọi `fsync`.
  - Nếu iOS cũng vậy, MVP chỉ đạt mức `written`. Khi mất nguồn hoặc khởi động lại cưỡng bức, có thể mất commit gần nhất cùng các sự kiện `confirmed` mà nguồn đã được dọn.
  - Điều này được chấp nhận theo KT-6 và GS-12.4.
  - Native plugin chỉ cần đến khi Q1 hoặc Q2 không đạt.
- **R-9 (đã chốt bằng KT-4):** chấp nhận báo thừa, và chấp nhận bỏ lỡ thông báo nếu app dừng trước khi thông báo kịp hiện.
- **R-13 (mới):** mô hình lỗi chỉ là mô hình. Hành vi thật trên iOS có thể khác, nên các test cấp D là bắt buộc.
- **R-14 (mới):** toàn bộ đặc tả chưa có hiện thực nào; chưa có test nào chạy.
- **Giữ nguyên từ v0.4.2:** R-1 đến R-7 và R-10 đến R-12.

---

**Trạng thái repo** (đã kiểm tra thực tế trong lượt này bằng lệnh chỉ đọc):
- HEAD `8feed74` trên nhánh `claude/cloud-session-connection-check-hksw4v`; không có stash.
- `git status`, hash của phần thay đổi chưa commit và hash của các file chưa theo dõi đều trùng với mốc đã ghi.
- Mọi thử nghiệm Godot chỉ chạy trong scratchpad, ở `/tmp/claude-0/-home-user-Qgame/0fb10fa7-097d-5509-a238-153a396e5da7/scratchpad/fsprobe` và `.../doc443`. Không file nào trong repo bị tạo hay sửa.

Tôi dừng ở đây để bạn duyệt v0.4.3.
