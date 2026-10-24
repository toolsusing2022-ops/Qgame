<!-- Lưu trữ nguyên văn bản đặc tả v0.4.9 từ phiên làm việc. Xem docs/spec/README.md để biết cách đọc. -->

# Phần A. Đặc tả v0.4.9 (các mục sửa)

**Phạm vi:** chỉ sửa 3 điểm P1, 2 điểm P2 và chốt R-25 theo đề nghị của bạn. Mọi mục không nhắc tới ở đây giữ nguyên v0.4.8.
- Giữ KT-1 đến KT-6.
- Không đụng gameplay hay schema level.
- **Chưa có quy tắc nào được kiểm chứng trên thiết bị.**

## 0. Quyết định sản phẩm (mới)

**KT-7.** Khi app ở trạng thái `save_blocked`, gameplay **không bị chặn**:
- Banner "Không lưu được tiến độ. Tiến độ hiện chỉ còn trong phiên này." hiện **ngay khi** chuyển sang `save_blocked`.
- Banner là lớp phủ cố định trên màn chơi, không nằm trong phần cài đặt.
- Banner chỉ được gỡ sau một lần ghi có kết quả `replaced`.
- Sự kiện chỉ nằm trong bộ nhớ không được chuyển vào kho.
- Nếu người chơi thoát app trong trạng thái này, phần tiến độ chưa commit có thể mất. Ta chấp nhận điều đó.
- KT-7 không thay đổi điều kiện kỹ thuật để công nhận commit.

R-25 được đóng nhờ KT-7.

## P1-A. Đường ghi khi `L.json` không đọc được (GS-12.2, 12.7, 13.4)

**Đường U** (trước đây gọi là "R3 rồi chạy bước 1 và 3"; nay đặt tên và viết đầy đủ):

| Bước | Hành vi khi đi đường U |
|---|---|
| Điều kiện vào | Cờ `needs_reconcile` đang bật **và** bước R cho kết quả R3. R3 bao gồm: `L.json` lỗi I/O; tồn tại nhưng không đọc được; đọc được nhưng hash không khớp `H_pending` lẫn `H_commit`; hoặc vắng mặt trong khi `H_commit ≠ none` |
| Bước 2a và 2b | **Bỏ qua cả hai.** Không đọc `L.json`. Không tạo `.bak.tmp`. Không gọi `rename_replace` lên `.bak`. **`.bak` giữ nguyên từng byte** |
| Bước 1 | Ghi `B_new` vào `.tmp` như thường lệ |
| Bước 3 | `rename_replace(.tmp, L.json, H_pending)`. Nếu `L.json` tồn tại nhưng không đọc được thì `pre_dst = unreadable` và primitive vẫn được gọi (GS-12.8) |
| Bước 3 cho `replaced` | Commit. Tắt `needs_reconcile`. Chạy bộ chuyển sự kiện cho `B_new` |
| Bước 3 không cho `replaced` | **Không commit.** Kết quả không bao giờ là `unchanged` khi `pre_dst = unreadable`, nên sẽ là `indeterminate` hoặc `precheck_failed`. `.bak` vẫn nguyên. Cờ `needs_reconcile` vẫn bật. Tăng `k` |

**Đường vào đường U khi `L.json` lỗi giữa phiên** (lần ghi bình thường):
1. Bước 2a đọc `L.json` thất bại → ra WE-2a. Huỷ lần ghi, **không** chạy 2b và 3, bật `needs_reconcile`, tăng `k`.
2. Lần ghi kế tiếp chạy bước R → R3 → đường U.

Vậy lần ghi sau một lỗi đọc giữa phiên **luôn tốn ít nhất 2 lần thử**. Đây là chủ đích: không có lần thử nào vừa phát hiện lỗi vừa ghi đè trong cùng một lượt.

**Đường vào đường U khi `L.json` lỗi ngay lúc khởi động** (`L.json` là `io_error` ở GS-13.4 E1):
- `needs_reconcile` được bật ngay từ mốc ban đầu, nên lần ghi đầu tiên đi thẳng vào đường U.

**Phân biệt hai việc trong GS-13.4:**
- **"Lưu trữ"** nghĩa là đổi tên ứng viên thành `.corrupt` qua `rename_noreplace`. Việc này cần `H_read`, nên **không áp dụng** cho file `io_error`.
- **"Thay thế ở bước 3 của đường U"** nghĩa là ghi đè `L.json` bằng `B_new`. Việc này **được phép** với file `io_error`.

Câu tương ứng trong GS-13.4 được sửa cho đúng nghĩa này.

## P1-B. Chống đệ quy khi ghi danh sách `suspended` (GS-12.8)

1. **Tạm ngưng trong bộ nhớ trước, đồng bộ.** Khi phát hiện vi phạm, `record_id` được thêm ngay vào tập `suspended` trong bộ nhớ, trước mọi thao tác ghi. Thao tác này idempotent.
2. **Ngữ cảnh ghi.** Mỗi lời gọi backend mang theo `context ∈ {progress, archive, pending, settings_evidence, settings_other}`.
3. **Lên lịch ghi danh sách.**
   - Chỉ vi phạm trong ngữ cảnh `progress`, `archive` hoặc `pending` mới lên lịch ghi file cài đặt.
   - Mỗi lúc chỉ có tối đa **một** lần ghi `settings_evidence` đang chờ hoặc đang chạy. Các vi phạm mới trong lúc đó được gộp vào tập trong bộ nhớ và được ghi cùng lần ghi đang chờ (nếu lần đó chưa bắt đầu), hoặc ở lần lên lịch kế tiếp.
4. **Vi phạm trong chính lần ghi `settings_evidence`:**
   - Ghi log `rename_contract_violation{context: settings_evidence}`.
   - Thêm `record_id` vào tập `suspended` trong bộ nhớ.
   - **Không** lên lịch thêm lần ghi danh sách nào do chính lỗi này.
5. **Ghi danh sách thất bại** (dù vì vi phạm hay lỗi I/O):
   - Chỉ ghi log. Trạng thái `suspended` trong bộ nhớ giữ tới hết phiên.
   - Lần ghi lại kế tiếp chỉ được lên lịch bởi một vi phạm **mới** trong ngữ cảnh `progress`, `archive` hoặc `pending`.
6. **Giới hạn cứng:** tối đa `EVIDENCE_WRITE_MAX_PER_SESSION` lần ghi `settings_evidence` mỗi phiên (mặc định 3). Vượt giới hạn thì chỉ ghi log.
7. Việc ghi `settings_evidence` **không bao giờ** ảnh hưởng tới quyết định commit tiến độ.

## P1-C. Quản lý `needs_reconcile` qua nhiều lần thử (GS-12.2)

| Kết thúc của một lần ghi | `needs_reconcile` sau đó | `k` | Bộ chuyển sự kiện |
|---|---|---|---|
| `replaced` (kể cả WE-3r) | **Tắt.** Đây là cách duy nhất để tắt cờ | Về 0 | Chạy cho `B_new` |
| WE-2a do đọc `L.json` lỗi; WE-2b-i; WE-2b-p; WE-3i; WE-3p; bước 3 của đường U không cho `replaced` | **Bật** (dù trước đó bật hay tắt) | +1 | Không chạy |
| WE-1a, WE-1b; WE-2a do ghi `.bak.tmp` lỗi; WE-2b, WE-2b-v, WE-3, WE-3v (trạng thái có bằng chứng); WE-R | **Giữ nguyên giá trị cũ**: lần thử lỗi **không bao giờ tắt** cờ | +1 | Không chạy |

**Quy tắc kèm theo:**
- Khi cờ đang bật, **mọi** lần thử, kể cả lần thử ở `save_blocked`, đều chạy bước R trước.
- Bước R lấy đúng các byte vừa đọc, không dùng kết quả của lần thử trước.
- Banner chỉ được gỡ sau `replaced` (KT-7).
- Không lần thử thất bại nào được ghi log commit hay coi là commit.

## P2-A. Tách `rename_noreplace` khỏi `rename_replace` (GS-12.8)

| | `rename_replace` | `rename_noreplace` |
|---|---|---|
| `dst` vắng mặt (kiểm tra tồn tại thành công) | Gọi primitive | Gọi primitive |
| `dst` tồn tại và đọc được | Gọi primitive | **Không gọi.** `err = dst_exists`. `state_after = unchanged` nếu `src` còn với hash đúng; nếu không thì `indeterminate` |
| `dst` tồn tại nhưng **không đọc được** | Gọi primitive (`pre_dst = unreadable`); không bao giờ cho `unchanged` | **Không gọi. Không bao giờ ghi đè.** `err = dst_exists`. Áp dụng điều kiện như dòng trên |
| Không kiểm tra được `dst` có tồn tại hay không | `precheck_failed`, `indeterminate` | `precheck_failed`, `indeterminate` |
| Điều kiện `unchanged` sau khi gọi | `src` còn với hash đúng **và** `dst` khớp `pre_dst` (theo hash) | `src` còn với hash đúng **và** `dst` vẫn vắng mặt. `noreplace` không bao giờ tạo nội dung `dst` nếu không thành công |

**Phía gọi `rename_noreplace`:**
- Khi nhận `dst_exists`, phía gọi thử hậu tố kế tiếp (`-1`, `-2`, … theo GS-13.3).
- Khi nhận `indeterminate`:
  - ở GS-13.4 E3.1: kết thúc với `archive_failed`;
  - ở GS-14.9: **giữ nguyên file `.pending-*`**, thử lại ở lần quét sau.

## P2-B. TC-12.52: tách hai nhóm tiêu chí

- **Nhóm 1, nạp bằng chứng:** với từng biến thể (a)–(l), kiểm tra:
  - hồ sơ nào được dùng, hồ sơ nào bị loại;
  - nhãn được áp dụng (`verified` hay `assumed`);
  - giá trị `storage_evidence_suspended` sau khi chạy;
  - log tương ứng.
- **Nhóm 2, lưu tiến độ:** ở mỗi biến thể, chạy bộ kịch bản WE chuẩn. **Chỉ** kiểm tra hai điều:
  - commit xảy ra ⇔ `state_after = replaced`;
  - không có hồ sơ nào bị nâng lên `verified` vì thiếu bằng chứng.
  - **Không** yêu cầu trạng thái file giống nhau giữa các biến thể.

## Test

**Sửa:**

| ID | Thay đổi |
|---|---|
| TC-12.55 | (b) Chuỗi cụ thể: lần 1 ra WE-2a (đọc `L.json` lỗi) → bật cờ, không chạy 2b/3. Lần 2 ra R3 → đường U: `.bak` không đổi byte nào, `pre_dst = unreadable` → `replaced` → tắt cờ → chạy bộ chuyển cho `B_new`. **(c) mới:** cờ đang bật → R12 → bước 2b ra WE-2b-i → cờ vẫn bật, `k` tăng, bộ chuyển không chạy. Lần sau R12 → xoay `.bak` thành công → `replaced` → tắt cờ. **(d) mới:** đường U, bước 3 ra `indeterminate` → không commit, `.bak` không đổi byte, cờ vẫn bật. **(e) mới:** đang `save_blocked`, banner hiện từ lần thứ 3 và vẫn hiện qua các lần thử thất bại, chỉ được gỡ sau `replaced` |
| TC-12.56 | (a) Lần ghi đầu đi đường U ngay, không qua WE-2a. Ghi rõ: file `io_error` không được lưu trữ nhưng được thay ở bước 3 |
| TC-12.51 | Bổ sung: `rename_noreplace` khi `dst` tồn tại và không đọc được → `dst_exists`, primitive không được gọi, `dst` không đổi |
| TC-12.52 | Tách thành Nhóm 1 và Nhóm 2 như P2-B |

**Mới:**

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-12.57 **[M]** | I | Đưa app vào `save_blocked` khi đang chơi | Banner hiện ngay trên màn chơi. Vẫn đặt hạt được. Banner không mất khi mở hay đóng màn khác. Chỉ gỡ sau `replaced` | KT-7, GS-12.2 |
| TC-12.58 **[M]** | U | Vi phạm trong ngữ cảnh `progress` → ghi `settings_evidence` → chính lần ghi này cũng gặp V-u. Biến thể: lặp vi phạm `progress` 10 lần | Hồ sơ bị `suspended` trong bộ nhớ ngay lập tức. Log có `context: settings_evidence`. **Không có lần ghi lồng nhau.** Số lần ghi `settings_evidence` ≤ `EVIDENCE_WRITE_MAX_PER_SESSION`. Không có vòng lặp. Commit tiến độ không bị ảnh hưởng | GS-12.8 |
| TC-12.59 **[M]** | U | `rename_noreplace` với `dst` ở ba trạng thái: tồn tại và đọc được; tồn tại nhưng không đọc được; không kiểm tra được tồn tại. Chạy ở E3.1 và ở GS-14.9 | Hai trạng thái đầu: `dst_exists`, nhật ký không có lời gọi primitive, phía gọi thử hậu tố kế tiếp. Trạng thái thứ ba: `indeterminate`; E3.1 ra `archive_failed`; GS-14.9 giữ nguyên `.pending-*` | GS-12.8, 13.3, 13.15, 14.9 |
| TC-12.60 **[M]** | U | Bảng P1-C: mỗi loại kết thúc × giá trị cờ trước đó (bật/tắt) | Cờ, `k` và việc chạy bộ chuyển sự kiện đúng từng ô của bảng. Không ô nào tắt cờ khi không có `replaced` | GS-12.2 |

**Thêm tham số vào 0.2:** `EVIDENCE_WRITE_MAX_PER_SESSION = 3`, dùng cho TC-12.58.

**Ma trận** (chỉ các dòng thay đổi):
- 12.2: thêm TC-12.55 (b–e), 12.56, 12.57, 12.60.
- 12.7: thêm TC-12.55, 12.60.
- 12.8: thêm TC-12.51, 12.52, 12.58, 12.59.
- 13.4: thêm TC-12.56.
- 13.15: thêm TC-12.59.
- 14.4: thêm TC-12.55 (c), 12.60.
- 14.9: thêm TC-12.59.
- KT-7: TC-12.57.
- 0.2: TC-12.58.

**Rà tham chiếu chéo:**
- Đường U khớp với R3, GS-13.4 `io_error`, quy tắc `pre_dst = unreadable` và bảng WE.
- `noreplace` không bao giờ ghi đè, ở cả GS-12.8, 13.3, 13.15 và 14.9.
- Cờ `needs_reconcile` chỉ được tắt bởi `replaced`.
- Bộ chuyển sự kiện chỉ nhận dữ liệu phân tích từ byte đã commit.

**Rủi ro mới:**
- **R-28:** đường U luôn tốn thêm một lần thử khi lỗi đọc xảy ra giữa phiên.
- **R-29:** khi việc ghi danh sách `suspended` thất bại, việc tạm ngưng chỉ có hiệu lực trong phiên (mở rộng R-23).

---

# Phần B. Hướng dẫn chi tiết tới bước chạy test và kiểm chứng

## Trạng thái thực tế hôm nay (kiểm tra trong lượt này)

| Hạng mục | Trạng thái |
|---|---|
| Test Python của công cụ nội dung | **Đã chạy lượt này:** `Ran 68 tests … OK`. Working tree không đổi sau khi chạy (tôi dùng `-B` để không ghi bytecode) |
| Code Godot của game | **Chưa có.** Mọi TC-12.x, 13.x, 14.x đều **chưa chạy được** |
| Godot 4.4.1 headless | Có sẵn trong scratchpad. Đã xác minh lượt này: một script chạy bằng `-s` trả mã thoát qua `quit(code)` (kết quả `exit=3`), nên dùng được làm test runner cho CI |
| Mac, Xcode, iPhone | Container này **không có**. Mọi bước cấp D cần máy của bạn |

## Giai đoạn 0: Chốt những việc đang treo (cần bạn quyết)

1. **Duyệt preview Bước 2** (`content/levels/previews/*`, `content/trials/previews/*`). Sau đó nhắn "commit" để tôi commit Bước 2 lên nhánh `claude/cloud-session-connection-check-hksw4v`.
2. **Duyệt đặc tả v0.4.9.** Nếu được, cho phép tôi lưu đặc tả thành file trong repo, ví dụ `docs/spec/gameplay_mvp_v0.4.9.md`. Hiện đặc tả chỉ nằm trong hội thoại.
3. **Cho phép bắt đầu viết code Godot** (Giai đoạn 1). Bước này sửa repo, nên tôi chỉ làm khi bạn nói rõ.

## Giai đoạn 1: Unit test trên Linux (làm được ngay trong container)

**1.1 Cấu trúc đề xuất:**

```
game/
  project.godot
  storage/   storage_backend.gd, godot_file_backend.gd,
             fault_injecting_backend.gd, model_fs.gd      ← GS-12.8, TC-12.24
  save/      progress_writer.gd (GS-12.2/12.7, bước R, đường U, save_blocked)
             restore.gd (GS-13.4), evidence_loader.gd (GS-12.8 vòng đời hồ sơ)
  events/    event_store.gd (GS-14.5), dispatcher.gd (GS-14.4/14.9)
  tests/     run_unit.gd, unit/test_*.gd
```

**1.2 Test runner.** Viết `tests/run_unit.gd` không phụ thuộc thư viện ngoài:
- `extends SceneTree`;
- quét `res://tests/unit/`;
- gọi các hàm có tên bắt đầu bằng `test_`;
- in một dòng cho mỗi test kèm mã TC;
- gọi `quit(0)` nếu tất cả đạt, `quit(1)` nếu có test hỏng.

**1.3 Lệnh chạy:**

```bash
# Test Python (đã chạy được hôm nay)
python3 -B -m unittest discover -s tools/tests -p 'test_*.py'

# Unit test Godot (sau khi có code)
godot --headless --path game -s res://tests/run_unit.gd ; echo "exit=$?"

# TC-12.23: không gọi FileAccess hoặc DirAccess ngoài thư mục storage/
grep -rnE 'FileAccess\.|DirAccess\.' game --include='*.gd' | grep -v '^game/storage/' && echo "VI PHẠM" || echo "OK"
```

**1.4 Thứ tự hiện thực, nối với test:**

| Đợt | Phần code | Test phải đạt |
|---|---|---|
| 1 | `model_fs` và `FaultInjectingBackend` (hai lớp, nhật ký truy cập, các điểm WK/WE/EA/ES/AK) | TC-12.24, 12.38 |
| 2 | Hợp đồng `rename_replace` / `rename_noreplace` | TC-12.33–12.35, 12.40, 12.41, 12.54, 12.59 |
| 3 | `progress_writer`: GS-12.2, bước R, đường U, `needs_reconcile`, `save_blocked` | TC-12.7, 12.11–12.22, 12.29, 12.34, 12.42–12.47, 12.49, 12.55, 12.60 |
| 4 | `restore`: GS-13.4, 13.11, 13.13–13.15, có `B_read`/`H_read`/`E_read` và `io_error` | TC-13.x, 12.44, 12.53, 12.56 |
| 5 | `event_store` và `dispatcher` | TC-14.x, 12.45, 12.50 |
| 6 | `evidence_loader` | TC-12.25, 12.48, 12.52, 12.58 |

**1.5 Probe trên Linux** (chỉ để tham khảo, **không** phải bằng chứng cho iOS). Lặp lại cách tôi đã làm:

```bash
strace -f -e trace=openat,write,fsync,fdatasync,rename,renameat2,unlink \
  godot --headless --path probe -s probe.gd
```

**Tiêu chí hoàn thành Giai đoạn 1:**
- Mọi test cấp U đều đạt.
- TC-12.23 cho kết quả `OK`.
- Có báo cáo ghi rõ số test đã chạy.

## Giai đoạn 2: macOS (cần Mac, bằng chứng bổ trợ)

1. Cài Godot 4.4.1 cho macOS cùng export templates 4.4.1.
2. Chạy lại toàn bộ unit test:
   ```bash
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://tests/run_unit.gd
   ```
3. **TC-12.37** (ổ đĩa APFS nhỏ, dọn được hoàn toàn):
   ```bash
   hdiutil create -size 64m -fs APFS -volname QTEST /tmp/qtest.dmg
   hdiutil attach /tmp/qtest.dmg            # được gắn vào /Volumes/QTEST
   # chạy probe làm đầy ổ, đường dẫn gốc là /Volumes/QTEST
   hdiutil detach /Volumes/QTEST && rm /tmp/qtest.dmg
   ```
4. **TC-12.26, phần syscall.** Chạy `sudo fs_usage -w -f filesys <tên tiến trình>` trong lúc probe chạy. Nếu export được bản Simulator thì chạy cả trên Simulator. Tôi **chưa xác minh** export templates 4.4.1 có hỗ trợ Simulator hay không.

**Ghi chú bắt buộc trong báo cáo:** kết quả macOS **không** được dùng làm bằng chứng cho iOS (GS-12.8).

## Giai đoạn 3: iOS trên thiết bị thật (cấp D, cần máy và tài khoản của bạn)

**3.1 Chuẩn bị:**
- Tài khoản Apple Developer.
- **Một iPhone dành riêng cho test** (không dùng máy cá nhân, vì TC-12.36 làm gần đầy bộ nhớ).
- Bản Xcode tương thích với Godot 4.4.1. Kiểm tra trong tài liệu export iOS của 4.4.1.

**3.2 Build test riêng:**
- Tạo export preset `iOS-StorageTest`:
  - thêm custom feature `storage_test`;
  - bundle id riêng, ví dụ `…qgame.storagetest`, để sandbox tách khỏi app thật.
- Trong code, các hook (`OS.crash()` tại các điểm WK, tiêm lỗi, file đệm làm đầy bộ nhớ) chỉ bật khi `OS.has_feature("storage_test")`.

**3.3 Chạy:**
1. Export ra project Xcode, mở `.xcodeproj`, chọn signing team, rồi Run trên thiết bị.
2. Màn hình test runner chọn TC theo mã và ghi kết quả vào `user://test_results/<run_id>.json`. Mỗi lần thử phải có:
   - phân loại: đạt / vi phạm / không xác định;
   - model máy, phiên bản iOS, bản Godot, phiên bản backend.
3. Các test có crash (TC-12.27, 12.28, 12.39e) cần mở lại app sau mỗi lần crash, ví dụ 250 lần cho TC-12.27.
   - Có thể tự động bằng một vòng lặp trên Mac dùng `xcrun devicectl device process launch --device <UDID> <bundle-id>` (Xcode 15 trở lên).
   - **Cần kiểm tra lại lệnh này trên bản Xcode của bạn.** Nếu không dùng được thì phải mở lại thủ công.
4. **Lấy kết quả:** Xcode → Window → Devices and Simulators → chọn app → **Download Container**. TC-12.32 xác định thư mục `user://` trên iOS nằm ở đâu.

**3.4 Ngưỡng đạt:**

| Test | Số lần thử tối thiểu (số lần "đạt") | Điều kiện đạt |
|---|---|---|
| TC-12.27 | 50 lần cho mỗi điểm WK | 0 vi phạm, 0 "không xác định" |
| TC-12.28 | 100 lần | 0 vi phạm, 0 "không xác định" |
| TC-12.30 | 100 lần | 0 vi phạm, 0 "không xác định" |
| TC-12.39 | (a)–(d) mỗi loại 100 lần; (e) 50 lần | 0 vi phạm, 0 "không xác định" |
| TC-12.36 | Theo quy trình an toàn: file đệm đặt trong `user://ballast/`, bị xoá khi app khởi động và khi kết thúc test | 0 lần bỏ sót lỗi |
| TC-12.31 | 20 lần | Chỉ ghi nhận, không có ngưỡng đạt |

**3.5 Phân tích kết quả.**
- Viết một script Python trong `tools/` (khi bạn cho phép) để đọc các file JSON kết quả, đối chiếu với ngưỡng ở 3.4, rồi in ra kết luận đạt hay không đạt cho Q1 và Q2.
- Nếu đạt, script tạo **bản nháp** hồ sơ bằng chứng.

## Giai đoạn 4: Hồ sơ bằng chứng và cổng chọn backend

1. **Q1 và Q2 đều đạt:**
   - Tạo hồ sơ `verified` cho `atomic_replace`, `file_sync = written`, `noreplace` và `dir_sync = unsupported`.
   - Ghi kèm N, điều kiện thử và tổ hợp máy/OS/Godot/backend.
   - **Không** tạo hồ sơ `durable`, vì chưa có D3.
2. **Có test không đạt:**
   - Lập hồ sơ quyết định, phân loại theo N1–N5.
   - Chỉ xét native backend khi lỗi thuộc N4 và đủ cả ba bằng chứng (GS-12.10).
3. **Báo cáo cuối** phân rõ bốn nhóm: đã rà trên tài liệu, đã thử trên Linux, đã thử trên macOS, đã kiểm chứng trên iOS.

---

**Trạng thái repo**, đã kiểm tra lượt này bằng lệnh chỉ đọc:
- HEAD là `8feed74` trên nhánh `claude/cloud-session-connection-check-hksw4v`; không có stash.
- Status, diff và các file chưa theo dõi đều trùng mốc trước và sau khi chạy test Python.
- Probe mã thoát chỉ chạy trong scratchpad. Không có file nào trong repo bị tạo hay sửa.

Tôi dừng ở đây. Bước tiếp theo cần bạn chọn:
- **(1)** duyệt preview Bước 2 và nhắn "commit";
- **(2)** duyệt v0.4.9 và cho phép lưu đặc tả vào repo;
- **(3)** cho phép tôi bắt đầu Giai đoạn 1, tức viết code Godot và chạy unit test trong container.
