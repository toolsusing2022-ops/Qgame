<!-- Lưu trữ nguyên văn bản đặc tả v0.1 từ phiên làm việc. Xem docs/spec/README.md để biết cách đọc. -->

# Đặc tả gameplay MVP — Pixel Bead Art ASMR (bản nháp v0.1, chờ duyệt)

**Cách đọc tài liệu:**
- Mỗi quy tắc có mã `GS-…` để test case trích dẫn.
- Các con số ghi *(mặc định, chỉnh được)* là tham số khởi đầu, sẽ tinh chỉnh qua test thiết bị. Đây chưa phải quyết định cuối.
- Mọi điểm còn chưa chốt được gom ở mục 14, đánh mã `Q-…`.

---

## 1. Phạm vi

| Trong MVP | Ngoài MVP (theo quyết định của bạn) |
|---|---|
| Chọn màu → chạm ô đúng → đặt 1 bead | Tô vùng liền, hoàn thành cả màu một lần, kéo để đặt liên tiếp |
| Làm nổi tĩnh các ô hợp lệ của màu đang chọn | Hít về ô gần nhất *(giả thuyết H1, mặc định tắt)* |
| Chạm sai không phạt, có phản hồi nhẹ | Tự chuyển màu khi hết *(giả thuyết H2, mặc định tắt)* |
| Nút **Tìm** | Combo, điểm số, giới hạn trợ giúp |
| Zoom / pan / nút toàn cảnh | Undo *(xem Q-3)* |
| Lưu và khôi phục tiến độ | Tranh tự do (freestyle), AI tạo tranh, backend |
| Âm thanh ASMR, haptic, cài đặt bật/tắt | iPad layout riêng (chỉ cần không hard-code kích thước) |
| Zen và Journey dùng chung hệ thống đặt hạt | |

---

## 2. Dữ liệu đầu vào (level schema v1, đã có validator)

- **GS-01.** Game chỉ nạp level hợp lệ theo `tools/LEVEL_SCHEMA.md`:
  - `width`, `height`;
  - `palette[i] = {id = i, hex, count, name?}`;
  - `cells` là mảng phẳng, với `cells[y*width + x]`;
  - giá trị `-1` là vị trí không có hạt;
  - `mask` (nếu có) chỉ dùng cho công cụ, gameplay bỏ qua.
- **GS-02.** Godot đọc mọi số trong JSON thành `float`, nên khi nạp phải ép `int()` và lưu thành `PackedInt32Array`. Level không hợp lệ thì không vào màn chơi, hiện thông báo lỗi thân thiện và ghi log mã lỗi.
- **GS-03. Định nghĩa:**
  - **Ô chơi được:** `cells[i] ≥ 0`.
  - **Ô hợp lệ cho màu `c`:** ô chơi được, chưa đặt hạt, và `cells[i] == c`.
  - **Màu xong:** không còn ô hợp lệ nào cho màu đó.
  - **Tranh xong:** mọi ô chơi được đã có hạt.

---

## 3. Mô hình trạng thái

| Trường | Ý nghĩa |
|---|---|
| `placed` (bitset, dài `width*height`) | Ô đã có hạt |
| `remaining[c]` | Số ô còn thiếu của màu `c`. Khởi tạo bằng `palette[c].count`, rồi trừ dần |
| `selected` | ID màu đang chọn, hoặc `none` |
| `camera` | Mức zoom và vị trí pan |
| `find_cursor[c]` | Ô cuối cùng mà nút Tìm đã đưa tới, theo từng màu |
| `mode` | `journey` hoặc `zen` |
| `completed` | Tranh đã hoàn thành chưa |

- **GS-04. Bất biến:** hai điều kiện sau phải luôn đúng; test logic kiểm tra sau mỗi thao tác.
  - `remaining[c] == count(i: cells[i]==c và chưa placed)`
  - `Σ remaining == 0 ⇔ completed`

---

## 4. Luồng màn chơi

- **GS-05. Vào màn:**
  - Nạp level và khôi phục tiến độ nếu có (mục 11).
  - Camera ở chế độ toàn cảnh.
  - Ô chưa đặt hạt hiện ở trạng thái "chưa đính" (mục 7). Ô đã đặt hiện hạt hoàn chỉnh.
- **GS-06. Màu được chọn khi vào màn:**
  - Nếu có tiến độ đã lưu: khôi phục màu `selected` đã lưu, miễn là màu đó chưa xong.
  - Nếu không: chọn màu chưa xong có ID nhỏ nhất. Pipeline đã xếp ID theo số ô giảm dần, nên đây là màu nhiều ô nhất.
  - Đây là lựa chọn ban đầu, **không** phải tự chuyển màu. Xem Q-1.
- **GS-07. Đổi màu:**
  - Chạm một swatch trong khay thì `selected` đổi ngay, vùng làm nổi đổi theo, phát tiếng "nhấc hạt" nhẹ.
  - **Camera không tự di chuyển** khi đổi màu.
  - Chạm swatch của màu đã xong thì màu đó được chọn nhưng không có ô nào nổi. Swatch hiện dấu tích. Không phát âm thanh lỗi.
- **GS-08. Hết một màu** (lần đặt cuối cùng của màu `c`):
  - Phát âm "hoàn thành màu", swatch chuyển sang trạng thái xong.
  - `selected` **giữ nguyên** (tự chuyển màu tắt theo mặc định, xem H2).
  - Hiện dòng nhắc "Màu này đã xong — chọn màu khác" ở khay. Các swatch còn màu chưa xong được viền nhẹ trong 1,5 giây, không nhấp nháy.
- **GS-09. Hết tranh:**
  - Khoá thao tác đặt hạt, phát âm "hoàn thành tranh" (≤ 3 giây).
  - Hiện màn hoàn thành với tranh trọn vẹn.
  - Lưu `completed = true`.
  - Journey mở khoá tranh kế tiếp; Zen quay về danh sách tranh.

---

## 5. Nhập liệu và phân biệt chạm với cử chỉ

- **GS-10. Một lần chạm** được tính khi thoả **đủ cả ba** điều kiện. Chỉ khi đó mới xét đặt hạt, và chỉ xét tại thời điểm **nhấc ngón tay**:
  - một ngón duy nhất;
  - quãng di chuyển từ lúc chạm xuống đến lúc nhấc lên ≤ **10pt** *(mặc định, chỉnh được)*;
  - thời gian giữ ≤ **500 ms** *(mặc định, chỉnh được)*.
- **GS-11.** Không thoả GS-10 thì coi là cử chỉ:
  - di chuyển quá ngưỡng là pan;
  - hai ngón trở lên là pinch hoặc pan;
  - giữ quá lâu thì không làm gì (để dành cho tính năng sau).
- **GS-12.** Đang pinch, hoặc vừa kết thúc pinch trong **150 ms**, thì mọi lần chạm đều bị bỏ qua. Mục đích là tránh đặt nhầm khi nhấc từng ngón khỏi màn hình.
- **GS-13. Xác định ô được chạm:**
  - Lấy ô chứa điểm nhấc tay, tính theo **toàn bộ hình vuông** của ô (không chỉ hình tròn của hạt).
  - Hít về ô gần nhất **tắt** theo mặc định (H1).
- **GS-14. Zoom:**
  - Mức nhỏ nhất là vừa khung tranh.
  - Mức lớn nhất là khi một ô cao **72pt** *(mặc định, chỉnh được)*.
  - Không dùng chạm đúp để zoom, vì dễ xung đột với chạm đặt hạt.
  - Nút **Toàn cảnh** đưa camera về vừa khung.

---

## 6. Kết quả của một lần chạm

| Mã | Tình huống | Kết quả | Phản hồi |
|---|---|---|---|
| GS-15 | Chạm vào ô hợp lệ của màu đang chọn | Đặt hạt, `remaining[sel] −1`, lưu (GS-30) | Hoạt ảnh hạt gắn vào, tiếng click, haptic nhẹ |
| GS-16 | Ô chưa đặt nhưng **khác màu** đang chọn | Không đặt hạt, không trừ gì | **Phản hồi chạm sai** (GS-20) |
| GS-17 | Ô đã có hạt | Không làm gì | Không phát âm thanh lỗi. Hạt có thể "rung" nhẹ một lần tuỳ chọn, xem Q-4 |
| GS-18 | Vị trí `-1` hoặc ngoài lưới | Không làm gì | Không phản hồi |
| GS-19 | `selected = none` hoặc màu đang chọn đã xong | Không đặt | Dòng nhắc ở khay "Chọn một màu" hoặc "Màu này đã xong" |

- **GS-20. Phản hồi chạm sai:** tất cả phải nhẹ và không gây khó chịu.
  - Ô vừa chạm hiện rõ số màu của nó trong **0,6 giây**, rồi mờ dần.
  - Swatch đúng màu trong khay sáng viền một lần (không lặp).
  - Phát một tiếng "tok" trầm, nhỏ hơn tiếng đặt hạt đúng khoảng **6 dB**.
  - **Không** dùng haptic báo lỗi. Tối đa là haptic rất nhẹ, xem Q-5.
  - Tiến độ không bị trừ, không có bộ đếm lỗi hiển thị.
- **GS-21.** Sau **3** lần chạm sai liên tiếp (không xen lần đặt đúng), hiện gợi ý chữ "Ô này cần màu số N — chạm vào ô màu N ở khay". Gợi ý tự ẩn sau 3 giây hoặc khi người chơi đặt đúng.
- **GS-22.** Zen có tuỳ chọn **tắt phản hồi chạm sai**. Khi tắt, chạm sai hoàn toàn im lặng.

---

## 7. Hiển thị lưới và làm nổi ô hợp lệ

- **GS-23. Ba trạng thái ô:**
  - **Chưa đính:** nền nhạt cùng tông màu đích, khoảng 25% độ bão hoà. Số màu hiện khi ô đủ lớn.
  - **Hợp lệ** (màu đang chọn, chưa đặt): nền đậm hơn, viền mảnh. Đây là hiệu ứng **tĩnh**: không nhấp nháy, không chuyển động lặp.
  - **Đã đặt:** hạt tròn có bóng và đúng mã màu `palette.hex`.
- **GS-24.** Số màu chỉ hiện khi ô ≥ **18pt** trên màn hình *(mặc định, chỉnh được)*. Ở mức zoom toàn cảnh, ô hợp lệ vẫn phải phân biệt được bằng độ đậm.
- **GS-25.** Màu hạt hiển thị phải trùng màu swatch trong khay. Không được thêm hiệu ứng làm lệch sắc độ quá mức đo được (ΔE00 ≤ 2 khi so màu trung bình của hạt với `hex`).

---

## 8. Khay màu

- **GS-26.** Khay nằm ở đáy màn hình dọc: một hàng swatch cuộn ngang, xếp theo thứ tự ID.
  - Mỗi swatch có: mã màu, số ID, số hạt còn lại `remaining[c]`.
  - Kích thước swatch ≥ **44×44pt**.
  - Swatch đang chọn to hơn khoảng 15% và có viền.
  - Swatch đã xong mờ đi và hiện dấu tích.
- **GS-27.** Số hạt còn lại cập nhật ngay khi đặt hạt. Không hiện hoạt ảnh đếm số kéo dài.
- **GS-28.** Khay không được che vùng tranh. Tranh co lại theo phần màn hình còn lại, tôn trọng safe area.

---

## 9. Nút Tìm

- **GS-29. Khi bấm Tìm:**
  - Nếu màu đang chọn còn ô hợp lệ: camera pan và zoom tới ô **gần tâm màn hình nhất** trong số các ô hợp lệ đang **nằm ngoài khung nhìn**. Nếu mọi ô hợp lệ đều đang trong khung nhìn thì chọn ô gần tâm nhất.
  - Zoom tối thiểu tới mức một ô ≥ **32pt** *(mặc định, chỉnh được)*.
  - Ô đích hiện một vòng sáng **mờ dần một lần** trong 1 giây, không nhấp nháy.
  - Bấm tiếp thì đi tới ô hợp lệ kế tiếp (gần ô vừa tìm nhất, không lặp lại cho tới khi đã đi hết), lưu vào `find_cursor`.
  - Nếu màu đang chọn đã xong hoặc `selected = none`: nút bị vô hiệu, kèm chú thích ngắn.
- **GS-29b. Chuyển động camera:**
  - Thời lượng 250–400 ms.
  - Khi Reduce Motion bật: thay bằng nhảy thẳng tới vị trí và mờ dần.
  - Người chơi chạm hoặc pan thì chuyển động lập tức dừng.
- **GS-29c.** MVP **không giới hạn** số lần dùng Tìm ở cả Zen lẫn Journey.

---

## 10. Âm thanh, haptic và hoạt ảnh

- **GS-31. Âm đặt hạt:**
  - Chọn ngẫu nhiên trong nhóm **4–6 mẫu**, không phát trùng mẫu liền kề.
  - Biến thiên cao độ ±3%.
  - Âm lượng mặc định vừa phải.
- **GS-32.** Tối đa **4** âm hiệu ứng phát cùng lúc. Âm mới thay âm cũ nhất. Chạm liên tục nhanh không được gây chồng âm vô hạn.
- **GS-33. Âm sự kiện:** "hoàn thành màu" ≤ 1,2 giây; "hoàn thành tranh" ≤ 3 giây; "chạm sai" là tiếng trầm và nhỏ. Không có âm thưởng hay combo.
- **GS-34. Âm nền:**
  - Có các lựa chọn: tắt, biển, mưa.
  - Âm lượng riêng với âm hiệu ứng.
  - Giảm âm (duck) nhẹ khi phát âm hoàn thành tranh.
- **GS-35. Haptic:**
  - Kiểu tác động nhẹ, mỗi lần đặt hạt **tối đa một lần**, giãn cách tối thiểu **40 ms**.
  - Bật/tắt riêng.
  - Thiết bị không hỗ trợ thì bỏ qua, không báo lỗi.
- **GS-36. Hoạt ảnh đặt hạt:**
  - Phóng 1,0 → 1,15 → 1,0 trong ≤ 200 ms.
  - Khi Reduce Motion bật: chỉ hiện mờ dần, không phóng to.
  - Hoạt ảnh không chặn thao tác: người chơi chạm tiếp được ngay.
- **GS-37.** Cài đặt có bốn mục riêng: âm hiệu ứng, âm nền (kèm lựa chọn loại), haptic, phản hồi chạm sai (chỉ Zen). Tất cả được lưu lại.

---

## 11. Lưu và khôi phục tiến độ

- **GS-30. Lưu tiến độ:**
  - Lưu cục bộ, gồm: `level_id`, `schema_version`, dấu vân tay `cells_hash` (SHA-256 của `width`, `height`, `cells` và các mã màu của palette), bitset `placed`, `selected`, `completed`, mốc thời gian.
  - Ghi trễ tối đa **1 giây** sau lần đặt hạt cuối, và ghi ngay khi app chuyển xuống nền hoặc bị đóng.
  - Ghi theo kiểu atomic: ghi ra file tạm rồi đổi tên.
- **GS-38. Khi khôi phục:**
  - Nếu `cells_hash` khớp: khôi phục chính xác trạng thái, và tính lại `remaining` từ bitset. Không tin số đếm đã lưu.
  - Nếu không khớp (dữ liệu level đã thay đổi): **không** áp tiến độ cũ. Hiện thông báo "Tranh đã được cập nhật, bắt đầu lại" và giữ một bản sao lưu file cũ.
  - Nếu file lưu hỏng: bắt đầu lại từ đầu, ghi log, không crash.
- **GS-39.** Cài đặt người dùng được lưu tách khỏi tiến độ level.

---

## 12. Zen và Journey

- **GS-40.** Hai chế độ dùng **chung toàn bộ** mục 4–11. Chỉ khác nhau ở:

| | Journey | Zen |
|---|---|---|
| Tiến triển | Tranh mở khoá theo thứ tự; xong tranh N mở tranh N+1 | Chọn bất kỳ tranh nào đã có |
| Phản hồi chạm sai | Luôn bật | Có thể tắt (GS-22) |
| Trợ giúp | Tìm không giới hạn (MVP) | Tìm không giới hạn |
| Điểm số, thời gian | Không có | Không có |

- **GS-41.** Tiến độ của một tranh là **của chung** cho cả hai chế độ, xem Q-6.

---

## 13. Yêu cầu phi chức năng

- **GS-42. Hiệu năng:**
  - Giữ **60 FPS** khi pan/zoom và khi chạm liên tục 5 lần/giây trên tranh **1024 ô** (`squid_relax_01`) trên iPhone mục tiêu.
  - Độ trễ từ lúc nhấc tay đến khi hạt bắt đầu xuất hiện ≤ **50 ms**.
  - Vẽ lưới theo lô (một lệnh vẽ hoặc MultiMesh), không dùng mỗi ô một Node.
- **GS-43. Trợ năng:**
  - Số trên ô cho người khó phân biệt màu.
  - Tôn trọng Reduce Motion.
  - Khay và các nút ≥ 44pt.
  - Mọi thông tin quan trọng không chỉ dựa vào màu sắc hay hoạt ảnh.
- **GS-44. Đo lường tối thiểu (offline, không SDK nặng):**
  - Các sự kiện: `level_start`, `bead_placed` (cộng dồn theo phiên), `wrong_tap`, `find_used`, `color_complete`, `level_complete`, `session_end`, `setting_changed`.
  - Đủ để kiểm chứng các giả thuyết H1–H6.

---

## 14. Giả thuyết cần thử nghiệm và câu hỏi mở

**Giả thuyết.** Mỗi giả thuyết có một cờ tính năng, mặc định **tắt**:

| Mã | Cờ tính năng | Giả thuyết | Đo gì | Tiêu chí bật (đề xuất) |
|---|---|---|---|---|
| H1 | `snap_to_nearest` | Hít về ô hợp lệ gần nhất trong bán kính ½ ô giúp giảm chạm sai mà không gây đặt nhầm | Tỷ lệ `wrong_tap`; số lần người chơi báo "đặt chỗ tôi không muốn" | `wrong_tap` giảm ≥ 50%; đặt nhầm do người chơi báo < 1% |
| H2 | `auto_switch_color` | Tự chuyển sang màu còn lại khi hết màu giúp nhịp chơi trơn hơn mà không làm mất cảm giác kiểm soát | Thời gian từ khi xong màu tới lần đặt kế tiếp; phản hồi định tính | Thời gian giảm ≥ 40% và ≤ 20% người chơi phàn nàn |
| H3 | — | Người chơi hoàn thành tranh Easy 300 ô mà không thấy mỏi | Tỷ lệ hoàn thành, điểm mỏi (1–5) | ≥ 80% hoàn thành, mỏi ≤ 2 |
| H4 | — | Tranh Relax 1024 ô cần thêm cơ chế tô nhanh | Tỷ lệ bỏ dở, điểm mỏi | Nếu bỏ dở > 30% hoặc mỏi ≥ 3 thì mở lại bàn bạc về B/C |
| H5 | — | Phản hồi chạm sai ở GS-20 đủ để người chơi hiểu lỗi | Số lần chạm sai liên tiếp trung bình trước khi đổi đúng màu | ≤ 2 |
| H6 | — | Nút Tìm giải quyết được việc tìm vài ô cuối | Thời gian xử lý 5% ô cuối; tần suất bấm Tìm | Thời gian 5% ô cuối ≤ 15% tổng thời gian chơi tranh |

**Câu hỏi mở cần bạn duyệt:**
- **Q-1.** Có tự chọn sẵn màu nhiều ô nhất khi vào màn lần đầu (GS-06) không? Hay để `selected = none` và yêu cầu người chơi tự chọn?
- **Q-2.** Ngưỡng chạm (10pt / 500 ms), cỡ ô để hiện số (18pt) và mức zoom tối đa (72pt) có chấp nhận làm mặc định ban đầu không?
- **Q-3.** Bỏ Undo khỏi MVP? Lập luận: hạt chỉ được đặt khi đúng màu, và H1 đang tắt, nên không thể đặt sai. Undo chỉ cần lại nếu bật H1.
- **Q-4.** Chạm vào ô đã có hạt: im lặng hoàn toàn, hay cho hạt rung nhẹ một lần?
- **Q-5.** Chạm sai có kèm haptic rất nhẹ, hay không có haptic?
- **Q-6.** Zen và Journey dùng chung tiến độ của một tranh, hay tách riêng?
- **Q-7.** Hai level hiện tại (`squid_easy_01` còn là bản thử, `squid_relax_01`) có được dùng làm dữ liệu test thiết bị không, trong khi preview chưa duyệt xong?

---

# Danh sách test case

**Cấp test:**
- **U:** test logic chạy headless bằng Godot, không có giao diện.
- **I:** test tích hợp có giao diện, mô phỏng cử chỉ chạm.
- **D:** test thủ công trên iPhone thật.
- **P:** test với người chơi.

**Dữ liệu test:**
- **F1:** level tổng hợp 3×2 hợp lệ, `cells = [0,1,2,-1,0,1]`.
- **F2:** `squid_easy_01` (20×15, 300 ô).
- **F3:** `squid_relax_01` (32×32, 1024 ô).
- **F4:** các level lỗi (thiếu trường, `cells` 2D, mã màu lạ).

### A. Nạp level và khởi tạo

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-01 | U | Nạp F1 | `remaining = [2,2,1]`; ô `-1` không chơi được; bất biến GS-04 đúng | GS-01, 03, 04 |
| TC-02 | U | Nạp từng level trong F4 | Từ chối nạp, trả mã lỗi; không crash | GS-02 |
| TC-03 | U | Nạp level có số dạng `float` (ví dụ `1.0`) như Godot đọc ra | Ép kiểu đúng; giá trị `cells` khớp bản JSON | GS-02 |
| TC-04 | U | Vào F2 khi chưa có tiến độ | `selected = 0`; camera ở chế độ toàn cảnh; không ô nào đã đặt | GS-05, 06 |
| TC-05 | U | Vào màn khi tiến độ đã lưu có `selected` là màu đã xong | Chọn màu chưa xong có ID nhỏ nhất | GS-06 |

### B. Đặt hạt và chạm sai

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-06 | U | F1, chọn 0, chạm (0,0) | Ô được đặt; `remaining[0] = 1`; phát sự kiện `bead_placed` | GS-15 |
| TC-07 | U | F1, chọn 0, chạm (1,0) (màu 1) | Không đặt; `remaining` không đổi; phát sự kiện `wrong_tap` kèm màu đúng = 1 | GS-16 |
| TC-08 | U | Chạm lại ô vừa đặt ở TC-06 | Không đổi trạng thái; không phát `wrong_tap` | GS-17 |
| TC-09 | U | Chạm ô (0,1) có giá trị `-1`; chạm toạ độ ngoài lưới | Không đổi trạng thái; không có sự kiện | GS-18 |
| TC-10 | U | `selected = none`, chạm ô bất kỳ | Không đặt; phát sự kiện nhắc chọn màu | GS-19 |
| TC-11 | U | 3 lần chạm sai liên tiếp, rồi 1 lần đúng, rồi 1 lần sai | Gợi ý xuất hiện sau lần sai thứ 3; lần đúng ẩn gợi ý và đặt lại bộ đếm về 0 | GS-21 |
| TC-12 | I | Zen, tắt phản hồi chạm sai, chạm sai | Không âm thanh, không hiệu ứng; trạng thái không đổi | GS-22 |
| TC-13 | U | Đặt toàn bộ F1 theo đúng màu | Đúng 5 lần đặt; sự kiện hoàn thành màu cho 0, 1, 2; `completed = true`; mọi chạm sau đó bị bỏ qua | GS-08, 09 |
| TC-14 | U | Phát lại toàn bộ F3 theo đúng màu (1024 lần đặt) | Hoàn thành; bất biến GS-04 đúng sau **mỗi** bước | GS-04 |
| TC-15 | U | 10.000 lần chạm ngẫu nhiên (màu và vị trí ngẫu nhiên, seed cố định) trên F2 | Không bao giờ có ô sai màu được đặt; bất biến luôn đúng | GS-04, 15, 16 |

### C. Phân biệt chạm với cử chỉ

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-16 | I | Chạm một ngón, di chuyển 6pt, giữ 200 ms | Tính là chạm, được đặt hạt nếu đúng màu | GS-10 |
| TC-17 | I | Chạm, kéo 15pt rồi nhấc | Tính là pan; không đặt hạt | GS-11 |
| TC-18 | I | Giữ 700 ms rồi nhấc, không di chuyển | Không đặt hạt | GS-10, 11 |
| TC-19 | I | Pinch zoom, nhấc ngón 1 rồi 80 ms sau nhấc ngón 2 trên một ô hợp lệ | Không đặt hạt | GS-12 |
| TC-20 | I | Chạm ở góc ô, ngoài hình tròn của hạt nhưng trong hình vuông của ô | Hạt được đặt vào đúng ô đó | GS-13 |
| TC-21 | I | Chạm đúp nhanh lên một ô hợp lệ | Lần chạm đầu đặt hạt, lần sau rơi vào GS-17; camera không zoom | GS-14, 17 |
| TC-22 | D | Pan và zoom liên tục 2 phút trên F3 | 0 hạt bị đặt ngoài ý muốn | GS-10–12 |

### D. Làm nổi ô và khay màu

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-23 | U | Chọn màu c | Tập ô được làm nổi bằng đúng tập ô hợp lệ của c | GS-23 |
| TC-24 | I | Quay video 3 giây khi đang làm nổi | Không có điểm ảnh nào thay đổi theo chu kỳ, tức là không nhấp nháy | GS-23 |
| TC-25 | I | Zoom tới các cỡ ô 17pt / 18pt / 40pt | Số màu ẩn ở 17pt, hiện ở 18pt và 40pt | GS-24 |
| TC-26 | I | Chụp màn hình hạt đã đặt cho từng màu của F2 | ΔE00 giữa màu trung bình của hạt và `hex` ≤ 2 | GS-25 |
| TC-27 | I | Đặt hạt | Số trên swatch giảm đúng 1 ngay trong khung hình kế tiếp | GS-27 |
| TC-28 | I | Đổi màu khi camera đang zoom tại một vị trí | Camera giữ nguyên vị trí và mức zoom | GS-07 |
| TC-29 | U/I | Đặt hết một màu | Swatch chuyển trạng thái xong; `selected` giữ nguyên; hiện dòng nhắc; không tự chuyển màu (H2 tắt) | GS-08 |
| TC-30 | D | Đo kích thước swatch và nút trên iPhone SE và iPhone Pro Max | ≥ 44pt; khay không che tranh; tôn trọng safe area | GS-26, 28 |

### E. Nút Tìm

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-31 | U | F3, chọn màu còn 3 ô nằm ngoài khung nhìn, bấm Tìm 4 lần | Đi qua 3 ô khác nhau theo thứ tự gần nhất; lần thứ 4 quay vòng về ô đầu | GS-29 |
| TC-32 | U | Mọi ô hợp lệ đều đang trong khung nhìn | Đi tới ô gần tâm màn hình nhất | GS-29 |
| TC-33 | I | Bấm Tìm khi màu đang chọn đã xong | Nút bị vô hiệu, có chú thích; camera không đổi | GS-29 |
| TC-34 | I | Bấm Tìm rồi chạm màn hình khi camera đang di chuyển | Chuyển động dừng ngay | GS-29b |
| TC-35 | I | Bật Reduce Motion rồi bấm Tìm | Không có chuyển động; nhảy thẳng tới vị trí và mờ dần | GS-29b |
| TC-36 | I | Ô đích sau khi Tìm | Vòng sáng mờ dần một lần, không lặp | GS-29 |

### F. Âm thanh, haptic, hoạt ảnh

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-37 | U | 100 lần đặt liên tiếp | Không có 2 mẫu âm giống nhau liền kề; cao độ nằm trong ±3% | GS-31 |
| TC-38 | I | Chạm đặt hạt 10 lần/giây trong 10 giây | Không bao giờ quá 4 âm phát cùng lúc; không rè, không treo | GS-32 |
| TC-39 | D | Chạm sai, so với chạm đúng | Tiếng sai nhỏ hơn khoảng 6 dB và trầm hơn; không có haptic lỗi | GS-20 |
| TC-40 | D | Tắt lần lượt từng mục: âm hiệu ứng, âm nền, haptic | Đúng mục đó tắt; các mục khác không bị ảnh hưởng; cài đặt còn sau khi khởi động lại | GS-34, 35, 37, 39 |
| TC-41 | D | Thiết bị hoặc chế độ không có haptic | Không có lỗi, không cảnh báo | GS-35 |
| TC-42 | I | Bật Reduce Motion rồi đặt hạt | Không phóng to, chỉ mờ dần | GS-36 |
| TC-43 | I | Chạm tiếp ngay trong lúc hoạt ảnh đặt hạt đang chạy | Lần chạm thứ hai được xử lý ngay | GS-36 |

### G. Lưu và khôi phục

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-44 | D | Đặt 37 hạt, buộc đóng app trong vòng 1 giây sau hạt cuối | Mở lại: đúng 36 hoặc 37 hạt, không bao giờ ít hơn 36; `remaining` tính lại khớp | GS-30, 38 |
| TC-45 | D | Đặt hạt rồi đưa app xuống nền ngay | Mở lại: đủ toàn bộ hạt | GS-30 |
| TC-46 | U | Khôi phục với `cells_hash` khác (level đã cập nhật) | Không áp tiến độ cũ; có thông báo; file cũ được sao lưu | GS-38 |
| TC-47 | U | File lưu bị hỏng (cắt ngang hoặc JSON sai) | Bắt đầu lại; ghi log; không crash | GS-38 |
| TC-48 | U | Ngắt điện giả lập giữa lúc ghi (file tạm còn dở) | File lưu chính còn nguyên bản cũ | GS-30 |
| TC-49 | D | Hoàn thành tranh, mở lại | Hiện trạng thái đã hoàn thành; Journey đã mở tranh kế tiếp | GS-09 |

### H. Zen và Journey

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-50 | U | Chạy cùng một chuỗi thao tác trên F2 ở cả Zen và Journey | Trạng thái đặt hạt giống hệt nhau | GS-40 |
| TC-51 | I | Journey: tranh N+1 khi chưa xong tranh N | Bị khoá; xong N thì mở được | GS-40 |
| TC-52 | I | Zen: tuỳ chọn tắt phản hồi chạm sai | Có trong Zen, **không** có trong Journey | GS-22, 40 |
| TC-53 | U | Chơi dở ở Zen rồi mở cùng tranh ở Journey | Hành vi đúng theo câu trả lời cho Q-6 | GS-41 |

### I. Hiệu năng và trợ năng

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-54 | D | F3: pan, zoom và chạm 5 lần/giây trong 60 giây trên iPhone mục tiêu | Khung hình p95 ≤ 16,7 ms (60 FPS); không tụt hình kéo dài | GS-42 |
| TC-55 | D | Đo độ trễ từ lúc nhấc tay tới khi hạt hiện (quay màn hình 240 fps) | ≤ 50 ms | GS-42 |
| TC-56 | D | Bật chế độ mô phỏng mù màu của hệ thống | Vẫn chơi được nhờ số trên ô; ô hợp lệ vẫn nhận ra được | GS-43 |
| TC-57 | U | Kiểm tra các sự kiện đo lường sau một phiên chơi F1 | Đủ các sự kiện của GS-44, đúng số lượng | GS-44 |

### J. Kiểm thử giả thuyết với người chơi

Mỗi giả thuyết test bằng cách bật/tắt cờ tính năng, 6–8 người mỗi vòng:

| ID | Cấp | Bước | Đo | Giả thuyết |
|---|---|---|---|---|
| TC-58 | P | F2, mỗi người chơi 2 bản: `snap` tắt và bật, thứ tự xáo trộn | Tỷ lệ `wrong_tap`; số lần đặt nhầm do người chơi báo; điểm thư giãn | H1 |
| TC-59 | P | F2: `auto_switch` tắt và bật | Thời gian từ khi xong màu tới lần đặt kế tiếp; phỏng vấn ngắn về cảm giác kiểm soát | H2 |
| TC-60 | P | Chơi trọn F2 | Tỷ lệ hoàn thành, thời gian, điểm mỏi | H3 |
| TC-61 | P | Chơi F3 trong 20 phút | Tỷ lệ bỏ dở, điểm mỏi, phần trăm hoàn thành | H4 |
| TC-62 | P | Đếm số lần chạm sai liên tiếp trước khi người chơi đổi đúng màu | Trung bình ≤ 2 | H5 |
| TC-63 | P | Thời gian xử lý 5% ô cuối cùng, và số lần bấm Tìm | Thời gian 5% ô cuối ≤ 15% tổng thời gian | H6 |

---

## Xác nhận trạng thái

Tôi không tạo, không sửa và không xoá file nào trong repo:
- HEAD vẫn là `8feed74` trên nhánh `claude/cloud-session-connection-check-hksw4v`, không có stash.
- `git status`, hash của phần thay đổi chưa commit và hash của mọi file chưa được theo dõi **trùng khớp** với mốc ghi lại trước đó.
- Không commit, push, reset, stash hay checkout.

Tôi dừng ở đây để bạn duyệt, nhất là 7 câu hỏi Q-1 đến Q-7.
