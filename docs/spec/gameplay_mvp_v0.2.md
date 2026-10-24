<!-- Lưu trữ nguyên văn bản đặc tả v0.2 từ phiên làm việc. Xem docs/spec/README.md để biết cách đọc. -->

# Đặc tả gameplay MVP v0.2 (chờ duyệt)

## A. Thay đổi so với v0.1

| # | Yêu cầu | Thay đổi trong v0.2 | Mục liên quan |
|---|---|---|---|
| 1 | `remaining` lấy từ `cells` và đối chiếu với `palette.count` | Game tự đếm `remaining` từ `cells` rồi so với `palette.count`. Lệch thì **từ chối nạp level** với mã `count_mismatch`, không tự sửa. Thêm luật từ chối màu không ô nào dùng, mã màu lạ và level không có ô chơi được | GS-02, GS-02a–d |
| 2 | Màu mặc định không phụ thuộc thứ tự palette | Quy tắc mới: chọn màu có `remaining` **lớn nhất**; bằng nhau thì chọn **ID nhỏ hơn**. Bỏ giả định "pipeline đã sắp xếp theo số lượng". Quy tắc này vẫn chỉ là mặc định, chỉnh được | GS-06 |
| 3 | Undo một bước | Thêm mục Undo mới: chỉ hoàn tác lần đặt gần nhất, không redo, không dùng sau khi xong tranh. Cập nhật `placed`, `remaining`, trạng thái màu; lưu ngay sau Undo. Câu hỏi Q-3 cũ đã được giải quyết | GS-45 đến GS-52 |
| 4 | Phân biệt tap/pan/pinch | Thay ngưỡng đơn giản bằng **phiên cử chỉ**: một phiên đã từng có từ 2 ngón trở lên thì không bao giờ tạo ra tap. Tap đặt hạt theo **điểm chạm xuống**, không theo điểm nhấc lên. Có quy tắc cho điểm nằm đúng biên ô, chạm khi tranh đang trôi theo quán tính, và vùng sát cạnh màn hình | GS-10 đến GS-13d |
| 5 | Giới hạn đặt hạt ở zoom toàn cảnh; hành vi nút Tìm | Ô nhỏ hơn 24pt (mặc định) thì chạm **không đặt hạt** mà phóng to quanh điểm chạm. Nút Tìm được định nghĩa tất định: chọn ô nào, khi hoà nhau thì sao, đi vòng thế nào, tương tác với Undo ra sao | GS-14a/b, GS-29 đến GS-29e |
| 6 | Lưu không dựa vào callback đóng app | Ghi ngay sau mỗi lần đặt/Undo (atomic, có bản sao lưu), ghi bù khi app xuống nền. **Không** dựa vào callback khi app bị đóng. Mất tối đa thao tác của lần ghi đang dở | GS-30, GS-30a–c |
| 7 | `cells_hash` gồm cả `hex` và phiên bản schema | Tách thành hai dấu vân tay có định dạng chuẩn hoá rõ ràng: `content_hash` (schema + kích thước + `hex` + `cells`) và `layout_hash` (chỉ kích thước + `cells`). Chỉ đổi màu thì giữ tiến độ kèm thông báo; đổi bố cục thì bắt đầu lại và sao lưu file cũ | GS-38, GS-38a–d |
| 8 | ΔE00 chỉ đo phần thân hạt | Chỉ đo vùng **thân** của hạt (vành khuyên 0,35r–0,65r, bỏ cung highlight), lấy **trung vị** màu Lab, chụp từ viewport của engine | GS-25, GS-25a |
| 9 | Thêm test | Thêm test cho: palette mâu thuẫn, level rỗng, Undo, đổi màu palette, lưu và khôi phục sau Undo, cử chỉ, biên ô, zoom toàn cảnh | TC-64 đến TC-92; sửa một số TC cũ |
| 10 | Thông số là mặc định chỉnh được | Gom mọi thông số cảm ứng, zoom và hành vi tự chuyển màu vào **bảng tham số** ở mục 0, tất cả đánh dấu "chờ thử thiết bị" | Mục 0, H1–H8 |

**Câu hỏi mở:** Q-3 (Undo) đã giải quyết. Q-1 được giải quyết một phần bởi GS-06. Thêm Q-8 đến Q-10.

---

## 0. Bảng tham số

Tất cả là **mặc định có thể chỉnh, chưa phải quyết định cuối**; chỉ chốt sau khi thử trên iPhone thật.

| Tham số | Mặc định | Căn cứ / ghi chú |
|---|---|---|
| `TAP_SLOP` | 10pt | Ngưỡng di chuyển để phân biệt tap với pan |
| `TAP_MAX_MS` | 500 ms | Giữ lâu hơn thì không tính là tap |
| `MULTI_TOUCH_COOLDOWN_MS` | 120 ms | Chặn tap ngay sau một phiên nhiều ngón |
| `MIN_PLACE_CELL` | 24pt | Theo mức tối thiểu WCAG 2.5.8 (AA); ô nhỏ hơn thì chạm sẽ zoom |
| `PLACE_ZOOM_CELL` | 32pt | Mức zoom đích khi chạm-để-zoom và khi bấm Tìm |
| `MAX_ZOOM_CELL` | 72pt | |
| `NUMBER_VISIBLE_CELL` | 18pt | Số màu vẫn hiện để đọc được dù chưa đủ lớn để đặt hạt |
| `EDGE_GUARD` | 0pt (tắt) | Bật nếu test thấy xung đột với cử chỉ hệ thống |
| `WRONG_TAP_HINT_AFTER` | 3 | |
| `SFX_VOICES_MAX` | 4 | |
| `HAPTIC_MIN_INTERVAL_MS` | 40 ms | |
| `auto_switch_color` | tắt | Giả thuyết H2 |
| `snap_to_nearest` | tắt | Giả thuyết H1 |
| `default_color_rule` | `max_remaining_then_min_id` | GS-06 |

**Hệ quả với hai level hiện có** (lề hai bên 16pt):
- Ở zoom toàn cảnh, Easy 20 cột có ô **17,1–19,9pt**; Relax 32 cột có ô **10,7–12,4pt**. Cả hai đều < `MIN_PLACE_CELL`.
- Vậy với mặc định 24pt, **cả hai level đều cần zoom trước khi đặt hạt** trên mọi iPhone.
- Đây là chỗ cần đo trên thiết bị thật (H7).

---

## 1. Phạm vi

| Trong MVP | Ngoài MVP |
|---|---|
| Chọn màu → chạm ô đúng → đặt 1 bead | Tô vùng liền, hoàn thành cả màu một lần, kéo để đặt liên tiếp |
| Làm nổi tĩnh các ô hợp lệ | Hít về ô gần nhất (H1, mặc định tắt) |
| Chạm sai không phạt, phản hồi nhẹ | Tự chuyển màu (H2, mặc định tắt) |
| Nút Tìm | Combo, điểm số, giới hạn trợ giúp |
| **Undo một bước** | Undo nhiều bước, Redo |
| Zoom, pan, nút Toàn cảnh, chạm-để-zoom khi ô quá nhỏ | Chạm đúp để zoom |
| Lưu và khôi phục tiến độ | Đồng bộ đám mây |
| Âm thanh ASMR, haptic, cài đặt | Tranh tự do (freestyle), AI tạo tranh |
| Zen và Journey dùng chung hệ thống đặt hạt | Layout iPad riêng |

---

## 2. Dữ liệu đầu vào

- **GS-01.** Chỉ nạp level theo schema v1:
  - `cells[y*width+x]` là mảng phẳng;
  - `-1` là vị trí không có hạt;
  - `palette[i].id == i`;
  - `mask` (nếu có) gameplay bỏ qua.
- **GS-02.** Godot đọc mọi số trong JSON thành `float`, nên phải ép `int()` và chỉ chấp nhận số nguyên đúng (từ chối giá trị kiểu `1.5`). Level không hợp lệ thì **không vào màn chơi**: hiện "Không mở được tranh này" và ghi log kèm mã lỗi.
- **GS-02a. Đếm lại từ dữ liệu:**
  - `remaining[c]` được **tự đếm** từ `cells`.
  - So với `palette[c].count`: chỉ cần một màu lệch là từ chối level (`count_mismatch`). **Không** tự lấy số đếm được để thay.
- **GS-02b.** Màu có trong palette nhưng không ô nào dùng thì từ chối (`unused_color`).
- **GS-02c.** `cells` chứa mã không có trong palette và khác `-1` thì từ chối (`unknown_color`).
- **GS-02d.** Không có ô chơi được nào (rỗng, hoặc toàn `-1`) thì từ chối (`no_playable_cells`). Sai kích thước (`len(cells) ≠ width×height`, hoặc `width`/`height` ngoài 1..128) thì từ chối (`grid_size`).
- **Ghi chú.** Các luật trên trùng với `validate_level.py`. Loader của game vẫn kiểm tra lại để phòng trường hợp file trong bản build bị hỏng hoặc bị sửa tay.
- **GS-03. Định nghĩa:**
  - **Ô chơi được:** `cells[i] ≥ 0`.
  - **Ô hợp lệ cho màu `c`:** chơi được, chưa đặt hạt, và `cells[i] == c`.
  - **Màu xong:** `remaining[c] == 0`.
  - **Tranh xong:** `Σ remaining == 0`.

---

## 3. Mô hình trạng thái

| Trường | Ý nghĩa |
|---|---|
| `placed` | Bitset dài `width*height`, đánh dấu ô đã có hạt |
| `remaining[c]` | Luôn tính được lại từ `cells` và `placed` |
| `selected` | ID màu đang chọn, hoặc `none` |
| `camera` | Mức zoom và vị trí pan |
| `last_placed` | Chỉ số ô của lần đặt gần nhất trong phiên, hoặc `none` (cho Undo) |
| `find_visited[c]` | Các ô mà nút Tìm đã đưa tới cho màu `c`, chỉ sống trong phiên |
| `completed`, `mode` | Tranh đã xong chưa; Journey hay Zen |

- **GS-04. Bất biến:** phải đúng sau **mọi** thao tác (đặt hạt, Undo, khôi phục).
  - `remaining[c] == count(i: cells[i]==c và chưa placed[i])`
  - `placed[i] ⇒ cells[i] ≥ 0`
  - `completed ⇔ Σ remaining == 0`

---

## 4. Luồng màn chơi

- **GS-05.** Vào màn: nạp level (mục 2), khôi phục tiến độ (mục 11), camera về chế độ toàn cảnh, `last_placed = none`.
- **GS-06. Màu được chọn khi vào màn** (tham số `default_color_rule`):
  1. Nếu khôi phục được tiến độ và `selected` đã lưu chưa xong thì giữ màu đó.
  2. Nếu không, chọn màu chưa xong có `remaining` **lớn nhất**; bằng nhau thì lấy **ID nhỏ nhất**.
  - Quy tắc này **không** dựa vào thứ tự sắp xếp của palette.
  - Phương án thay thế để thử nghiệm: để `selected = none` và yêu cầu người chơi tự chọn.
- **GS-07. Đổi màu:**
  - Chạm swatch thì đổi `selected`, vùng làm nổi đổi theo, phát tiếng "nhấc hạt".
  - **Camera không tự di chuyển.**
  - Chọn màu đã xong thì không có ô nào nổi; swatch hiện dấu tích.
  - Đổi màu **không** xoá khả năng Undo.
- **GS-08. Hết một màu:**
  - Phát âm hoàn thành màu, swatch chuyển sang trạng thái xong.
  - `selected` giữ nguyên, trừ khi bật `auto_switch_color` (H2).
  - Hiện dòng nhắc chọn màu khác; các swatch chưa xong được viền nhẹ trong 1,5 giây, không nhấp nháy.
- **GS-09. Hết tranh:**
  - Khoá thao tác đặt hạt và **Undo**; phát âm hoàn thành tranh (≤ 3 giây).
  - Hiện màn hoàn thành, lưu `completed = true`.
  - Journey mở khoá tranh kế tiếp; Zen quay về danh sách tranh.

---

## 5. Nhập liệu: tap, pan và pinch

- **GS-10. Phiên cử chỉ:**
  - Bắt đầu khi ngón đầu tiên chạm màn hình, kết thúc khi **mọi** ngón đã nhấc lên.
  - Một phiên chỉ tạo ra tap khi đồng thời:
    - suốt phiên chỉ có **đúng 1 ngón**;
    - quãng di chuyển tối đa so với điểm chạm xuống ≤ `TAP_SLOP`;
    - thời lượng ≤ `TAP_MAX_MS`;
    - camera **không** đang trôi theo quán tính lúc chạm xuống;
    - đã qua ít nhất `MULTI_TOUCH_COOLDOWN_MS` kể từ khi kết thúc phiên nhiều ngón gần nhất.
- **GS-11.** Một phiên đã từng có ≥ 2 ngón **không bao giờ** tạo tap, kể cả khi ngón cuối cùng đứng yên rồi nhấc lên. Sau pinch, ngón còn lại tiếp tục pan mượt, không làm camera giật.
- **GS-12.** Chạm xuống khi camera đang trôi thì camera **dừng lại**, và phiên đó không tạo tap (giống hành vi cuộn quen thuộc trên iOS).
- **GS-13. Xác định ô được chạm:**
  - Dựa vào **điểm chạm xuống**, vì điểm nhấc lên hay bị lệch do ngón tay lăn.
  - Ô là hình vuông `[x, x+1) × [y, y+1)` trong toạ độ lưới.
  - Điểm nằm **đúng trên biên** thuộc về ô bên phải hoặc bên dưới (làm tròn xuống), nên kết quả luôn tất định.
- **GS-13a.** Với `snap_to_nearest` tắt, chạm lệch sang ô bên cạnh **khác màu** sẽ nhận phản hồi chạm sai. Giảm rủi ro này bằng `MIN_PLACE_CELL` (GS-14a), không bằng cách đoán ý người chơi.
- **GS-13b.** Điểm chạm xuống nằm trên khay hoặc các nút thì do phần giao diện đó xử lý. Phiên bắt đầu trên tranh rồi kết thúc trên khay không tạo tap.
- **GS-13c.** Tranh không được nằm dưới vùng thanh home. Vùng sát mép màn hình có thể bị cử chỉ hệ thống chiếm; mặc định `EDGE_GUARD = 0`, chỉ bật nếu test thiết bị thấy xung đột (TC-76).
- **GS-13d.** Từ 3 ngón trở lên thì bỏ qua và không làm gì.
- **GS-14. Zoom:**
  - Pinch zoom quanh tâm của hai ngón.
  - Mức nhỏ nhất là toàn cảnh, mức lớn nhất là `MAX_ZOOM_CELL`.
  - Không dùng chạm đúp để zoom.
  - Nút Toàn cảnh đưa camera về vừa khung.
- **GS-14a. Ô quá nhỏ để đặt hạt.** Khi ô trên màn hình < `MIN_PLACE_CELL`:
  - Tap trên tranh **không đặt hạt và không có phản hồi sai**.
  - Camera phóng tới `PLACE_ZOOM_CELL`, lấy điểm vừa chạm làm tâm.
  - Lần đầu tiên xảy ra trong phiên chơi, hiện gợi ý "Phóng to để đặt hạt" một lần.
  - Khi Reduce Motion bật: nhảy thẳng tới mức zoom và mờ dần.
- **GS-14b.** Ở zoom toàn cảnh vẫn làm nổi ô hợp lệ và vẫn hiện số nếu ô ≥ `NUMBER_VISIBLE_CELL`, để người chơi nhìn tổng quan rồi mới chạm để vào gần.

---

## 6. Kết quả của một lần tap

Các trường hợp dưới đây áp dụng khi ô ≥ `MIN_PLACE_CELL`:

| Mã | Tình huống | Kết quả | Phản hồi |
|---|---|---|---|
| GS-15 | Ô hợp lệ của màu đang chọn | Đặt hạt; `remaining[sel] −1`; `last_placed = i`; lưu ngay | Hoạt ảnh hạt gắn vào, tiếng click, haptic nhẹ |
| GS-16 | Ô chưa đặt nhưng khác màu | Không đặt; không đổi trạng thái | Phản hồi chạm sai (GS-20) |
| GS-17 | Ô đã có hạt | Không làm gì; **không** đổi `last_placed` | Im lặng (xem Q-4) |
| GS-18 | Vị trí `-1` hoặc ngoài lưới | Không làm gì | Im lặng |
| GS-19 | `selected = none` hoặc màu đang chọn đã xong | Không đặt | Dòng nhắc ở khay |

- **GS-20. Phản hồi chạm sai:**
  - Ô vừa chạm hiện rõ số màu của nó trong 0,6 giây.
  - Swatch đúng màu sáng viền một lần.
  - Một tiếng "tok" trầm, nhỏ hơn tiếng đặt hạt khoảng 6 dB.
  - Không có haptic báo lỗi (Q-5).
  - Không trừ tiến độ, không ảnh hưởng tới Undo.
- **GS-21.** Sau `WRONG_TAP_HINT_AFTER` lần chạm sai liên tiếp, hiện gợi ý chữ. Lần đặt đúng hoặc Undo sẽ đưa bộ đếm về 0.
- **GS-22.** Zen có tuỳ chọn tắt phản hồi chạm sai.

---

## 7. Hiển thị ô và làm nổi

- **GS-23. Ba trạng thái ô:**
  - **Chưa đính:** nền nhạt cùng tông màu đích.
  - **Hợp lệ:** đậm hơn, có viền. Hiệu ứng **tĩnh**: không nhấp nháy, không có chuyển động lặp.
  - **Đã đặt:** hạt có thân cùng màu `hex`, highlight cố định ở góc trên-trái, bóng ở cạnh dưới-phải.
- **GS-24.** Số màu hiện khi ô ≥ `NUMBER_VISIBLE_CELL`.
- **GS-25. Độ chính xác màu, chỉ đo phần thân hạt:**
  - Chụp từ viewport của engine ở tỉ lệ 1:1, không dùng ảnh chụp màn hình thiết bị có lọc màu.
  - Vùng đo là **vành khuyên** 0,35r–0,65r tính từ tâm hạt, **bỏ cung 90° phía trên-trái** chứa highlight.
  - Đổi các pixel trong vùng sang Lab và lấy **trung vị**.
  - Yêu cầu ΔE00(trung vị, `hex`) ≤ **2,0**.
- **GS-25a.** Shader của hạt phải giữ màu gốc ở vùng thân (hệ số sáng ≈ 1). Highlight và bóng chỉ được nằm ngoài vùng đo ở GS-25. Nếu sau này đổi thiết kế hạt, phải định nghĩa lại vùng đo trước khi chạy test.

---

## 8. Khay màu

- **GS-26.** Khay là một hàng swatch cuộn ngang ở đáy màn hình, xếp theo ID.
  - Mỗi swatch có: mã màu, số ID, số còn lại `remaining`.
  - Kích thước swatch ≥ 44×44pt.
  - Swatch đang chọn to hơn và có viền; swatch đã xong mờ đi, có dấu tích.
- **GS-27.** Số còn lại cập nhật ngay sau mỗi lần đặt hoặc Undo.
- **GS-28.** Khay không che tranh; tôn trọng safe area.

**Hàng hành động phía trên khay** (mỗi nút ≥ 44pt): Tìm, Undo, Toàn cảnh, Cài đặt.

---

## 9. Nút Tìm

- **GS-29. Chọn ô đích:** chỉ xét các ô hợp lệ của `selected`.
  1. Ưu tiên các ô **chưa nằm trong `find_visited`** của màu đó và đang **nằm ngoài khung nhìn**.
  2. Nếu không có, chọn trong các ô chưa thăm (kể cả trong khung nhìn).
  3. Nếu đã thăm hết, xoá `find_visited` rồi chọn lại từ đầu.
  - Trong tập được chọn, lấy ô có khoảng cách Euclid nhỏ nhất tới ô ở tâm khung nhìn; hoà nhau thì lấy chỉ số `y*width+x` nhỏ nhất.
- **GS-29a. Camera:**
  - Pan tới ô đích với mức zoom = max(mức hiện tại, `PLACE_ZOOM_CELL`). Như vậy luôn đặt được hạt ngay sau khi Tìm.
  - Ô đích hiện vòng sáng mờ dần **một lần** trong 1 giây.
  - Chuyển động dài 250–400 ms; Reduce Motion bật thì nhảy thẳng.
  - Người chơi chạm hoặc pan thì chuyển động dừng ngay.
- **GS-29b.** Màu đang chọn đã xong, `selected = none`, hoặc tranh đã xong thì nút Tìm bị vô hiệu, kèm chú thích.
- **GS-29c.** Đổi màu thì nút Tìm dùng `find_visited` của màu mới. `find_visited` không được lưu giữa các phiên.
- **GS-29d.** Sau Undo, ô vừa hoàn tác lại là ô hợp lệ và được Tìm xét như các ô khác. Nếu ô đó đang trong `find_visited`, xoá nó khỏi tập để Tìm có thể đưa tới.
- **GS-29e.** MVP không giới hạn số lần Tìm ở cả hai chế độ.

---

## 10. Âm thanh, haptic, hoạt ảnh

- **GS-31.** Âm đặt hạt chọn ngẫu nhiên trong 4–6 mẫu, không lặp mẫu liền kề, biến thiên cao độ ±3%.
- **GS-32.** Tối đa `SFX_VOICES_MAX` âm phát cùng lúc; âm mới thay âm cũ nhất.
- **GS-33.** Âm hoàn thành màu ≤ 1,2 giây; hoàn thành tranh ≤ 3 giây; chạm sai là tiếng trầm và nhỏ; **Undo** là tiếng "nhấc hạt" nhẹ. Không có âm combo.
- **GS-34.** Âm nền có các lựa chọn: tắt, biển, mưa. Âm lượng tách riêng với âm hiệu ứng.
- **GS-35.** Haptic: tác động nhẹ khi đặt hạt, giãn cách tối thiểu `HAPTIC_MIN_INTERVAL_MS`. Không dùng haptic cho chạm sai và Undo (Q-5). Thiết bị không hỗ trợ thì bỏ qua.
- **GS-36. Hoạt ảnh:**
  - Đặt hạt: phóng 1,0 → 1,15 → 1,0 trong ≤ 200 ms.
  - Undo: hạt thu nhỏ và mờ đi trong ≤ 150 ms.
  - Khi Reduce Motion bật: chỉ mờ dần.
  - Không hoạt ảnh nào chặn thao tác.
- **GS-37.** Cài đặt gồm: âm hiệu ứng, âm nền, haptic, phản hồi chạm sai (chỉ Zen). Lưu riêng với tiến độ.

---

## 11. Lưu và khôi phục

- **GS-30. Khi nào ghi:**
  - **Ngay sau mỗi lần đặt hạt hoặc Undo**, không có độ trễ cố ý.
  - Nếu một lần ghi đang chạy, các thay đổi mới được gộp vào **đúng một** lần ghi tiếp theo.
  - Thêm một lần ghi khi app **xuống nền**, mất tiêu điểm, hoặc mở màn hình khác.
  - **Không** dựa vào callback khi app bị tắt hoặc bị đóng cưỡng bức.
- **GS-30a. Giới hạn mất dữ liệu:**
  - Nếu app bị đóng ≥ 200 ms sau thao tác cuối: **không mất gì**.
  - Nếu bị đóng ngay sau thao tác: mất tối đa thao tác thuộc lần ghi đang dở (thường ≤ 1).
- **GS-30b. Ghi atomic:**
  1. Ghi ra file tạm.
  2. Đẩy dữ liệu xuống đĩa (flush/sync) nếu nền tảng hỗ trợ.
  3. Đổi tên đè lên file chính.
  - Giữ bản trước đó dưới tên `*.bak`.
- **GS-30c. Nội dung file tiến độ:**
  - `save_version`, `level_id`, `content_hash`, `layout_hash`;
  - `placed` (bitset mã hoá base64), `selected`, `completed`, `updated_at`.
  - **Không** lưu `last_placed` và `find_visited` (xem Q-8).
- **GS-38. Hai dấu vân tay**, đều là SHA-256 dạng hex chữ thường của chuỗi UTF-8 chuẩn hoá:
  - `layout_hash` = `pbart-layout|w=<w>|h=<h>|cells=<c0>,<c1>,…`
  - `content_hash` = `pbart-content|schema=<schema_version>|w=<w>|h=<h>|palette=<id>:<hex>,…|cells=<c0>,…`
  - Quy ước chung: số nguyên ghi dạng thập phân, không có dấu cách. Palette xếp theo ID, `hex` ghi chữ thường kèm dấu `#`. `count` **không** đưa vào hash vì nó suy ra được từ `cells`.
  - Python và Godot phải cho ra cùng một chuỗi. Có test đối chiếu (TC-86).
- **GS-38a.** `content_hash` khớp thì khôi phục chính xác `placed` và `selected`; **tính lại** `remaining` từ `placed`, không tin số đã lưu.
- **GS-38b.** `content_hash` lệch nhưng `layout_hash` khớp (chỉ đổi màu `hex` hoặc đổi phiên bản schema nhưng vẫn tương thích): khôi phục `placed`, rồi hiện thông báo "Màu của tranh vừa được cập nhật". Xem Q-9.
- **GS-38c.** `layout_hash` lệch thì **không** khôi phục: sao lưu file cũ thành `*.stale`, hiện "Tranh đã được cập nhật, bắt đầu lại", tạo tiến độ mới.
- **GS-38d.** File hỏng: thử đọc `*.bak`; nếu vẫn hỏng thì bắt đầu lại và ghi log. Không bao giờ crash.
- **GS-39.** Cài đặt người dùng lưu riêng; tiến độ hỏng không ảnh hưởng tới cài đặt.

---

## 12. Undo một bước

- **GS-45.** Undo hoàn tác **lần đặt hạt gần nhất trong phiên chơi hiện tại**. Chỉ một bước, không có Redo.
- **GS-46.** Undo dùng được khi `last_placed ≠ none` **và** `completed = false`.
- **GS-47. Tác dụng:**
  - `placed[last_placed] = false`.
  - `remaining[c] += 1`, với `c = cells[last_placed]`.
  - Nếu màu `c` đang ở trạng thái xong thì trở lại chưa xong; swatch khôi phục.
  - Sau đó `last_placed = none`, nút Undo bị vô hiệu cho tới lần đặt hạt kế tiếp.
- **GS-48.** Undo **không** đổi `selected` và **không** di chuyển camera. Nếu ô vừa hoàn tác nằm ngoài khung nhìn, hiện một dòng nhắc ngắn "Đã hoàn tác 1 hạt".
- **GS-49.** Ghi tiến độ ngay sau Undo (GS-30). Bất biến GS-04 phải đúng.
- **GS-50.** Chạm sai, chạm ô đã có hạt, đổi màu, bấm Tìm và zoom đều **không** làm mất khả năng Undo. Chỉ lần đặt hạt mới mới thay đổi `last_placed`.
- **GS-51.** Khi tranh xong (GS-09), Undo bị khoá vĩnh viễn với tranh đó. Lý do: tránh huỷ việc mở khoá trong Journey.
- **GS-52.** Ghi nhận sự kiện `undo_used`. Lần hoàn thành màu xảy ra lại sau Undo vẫn phát âm thanh, nhưng sự kiện `color_complete` gắn cờ `repeat = true`.

---

## 13. Zen và Journey

- **GS-40.** Hai chế độ dùng chung toàn bộ mục 2–12. Chỉ khác ở:
  - Tiến triển: Journey mở khoá tranh theo thứ tự; Zen chọn bất kỳ.
  - Zen có tuỳ chọn tắt phản hồi chạm sai.
  - Giới hạn trợ giúp nếu sau này cần (MVP chưa có).
- **GS-41.** Tiến độ của một tranh dùng chung cho cả hai chế độ (Q-6).

---

## 14. Phi chức năng

- **GS-42. Hiệu năng:**
  - 60 FPS (khung hình p95 ≤ 16,7 ms) với tranh 1024 ô khi pan, zoom và chạm 5 lần/giây.
  - Độ trễ từ nhấc tay đến khi hạt bắt đầu xuất hiện ≤ 50 ms.
  - Vẽ lưới theo lô.
  - Việc ghi file không được làm rơi khung hình: ghi ngoài luồng vẽ, hoặc file đủ nhỏ để ghi < 2 ms.
- **GS-43. Trợ năng:**
  - Có số trên ô.
  - Tôn trọng Reduce Motion.
  - Khay và nút ≥ 44pt.
  - Không truyền thông tin chỉ bằng màu hoặc hoạt ảnh.
- **GS-44. Sự kiện đo lường:**
  - `level_start`, `bead_placed`, `wrong_tap`, `tap_to_zoom`, `find_used`, `undo_used`, `color_complete{repeat}`, `level_complete`, `save_restore{result}`, `session_end`, `setting_changed`.

---

## 15. Giả thuyết và câu hỏi mở

| Mã | Cờ tính năng / tham số | Giả thuyết | Tiêu chí (đề xuất) |
|---|---|---|---|
| H1 | `snap_to_nearest` | Hít về ô hợp lệ trong bán kính ½ ô giúp giảm chạm sai mà không gây đặt nhầm | `wrong_tap` giảm ≥ 50%; Undo ngay sau khi đặt < 1% |
| H2 | `auto_switch_color` | Tự chuyển màu khi hết giúp nhịp chơi trơn mà không mất cảm giác kiểm soát | Thời gian giữa hai màu giảm ≥ 40%; ≤ 20% người chơi phàn nàn |
| H3 | — | Easy 300 ô không gây mỏi | ≥ 80% hoàn thành; mỏi ≤ 2/5 |
| H4 | — | Relax 1024 ô cần cơ chế tô nhanh | Bỏ dở > 30% hoặc mỏi ≥ 3 thì mở lại bàn bạc |
| H5 | — | Phản hồi chạm sai đủ dễ hiểu | ≤ 2 lần chạm sai liên tiếp trước khi đổi đúng màu |
| H6 | — | Nút Tìm xử lý tốt các ô cuối | Thời gian 5% ô cuối ≤ 15% tổng thời gian |
| H7 | `MIN_PLACE_CELL` | Ngưỡng 24pt cân bằng giữa độ chính xác và số lần phải zoom | Tỷ lệ Undo ngay sau đặt < 1%, và ≤ 1 lần zoom mỗi phút |
| H8 | `TAP_SLOP`, `MULTI_TOUCH_COOLDOWN_MS` | Mặc định không gây đặt nhầm khi pan/pinch | 0 lần đặt nhầm trong test cử chỉ 2 phút; < 2% tap hợp lệ bị bỏ qua |

**Câu hỏi mở:**
- **Q-1** (còn một phần). Giữ quy tắc chọn sẵn màu nhiều ô nhất (GS-06), hay thử thêm phương án `selected = none`?
- **Q-2.** Duyệt các mặc định ở bảng tham số làm điểm khởi đầu để test thiết bị.
- **Q-4.** Chạm ô đã có hạt: im lặng (mặc định), hay rung nhẹ một lần?
- **Q-5.** Không dùng haptic cho chạm sai và Undo: đồng ý không?
- **Q-6.** Zen và Journey dùng chung tiến độ?
- **Q-7.** Có được dùng `squid_easy_01` và `squid_relax_01` làm dữ liệu test thiết bị khi preview chưa duyệt xong?
- **Q-8.** Undo **không** dùng được sau khi đóng và mở lại app (không lưu `last_placed`): đồng ý không?
- **Q-9.** Khi chỉ đổi màu `hex`, giữ tiến độ kèm thông báo (GS-38b), hay luôn bắt đầu lại?
- **Q-10.** Chạm-để-zoom khi ô < 24pt (GS-14a), hay cho phép đặt hạt ở mọi mức zoom và để H7 quyết định sau?

---

# Danh sách test case v0.2

**Ký hiệu:**
- Cấp test: **U** logic headless, **I** tích hợp mô phỏng chạm, **D** trên iPhone thật, **P** với người chơi.
- **[S]** = đã sửa so với v0.1; **[M]** = mới.

**Dữ liệu test:**
- **F1:** level 3×2 hợp lệ, `cells = [0,1,2,-1,0,1]`.
- **F2:** `squid_easy_01`.
- **F3:** `squid_relax_01`.
- **F4:** các level lỗi.
- **F5** [M]: F1 nhưng `palette[0].count = 3`.
- **F6** [M]: F1 thêm màu 3 có `count 0`.
- **F7** [M]: `cells` toàn `-1`.
- **F8** [M]: `cells = []` với `width = height = 0`.
- **F9** [M]: F1 nhưng đổi `hex` của màu 1.
- **F10** [M]: F1 nhưng đổi một giá trị trong `cells`.
- **F11** [M]: hai màu có `remaining` bằng nhau, và màu ID lớn hơn đứng trước trong file.

### A. Nạp level và dữ liệu

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-01 [S] | U | Nạp F1 | `remaining` tự đếm = `[2,2,1]` và khớp `count`; bất biến đúng | GS-02a, 04 |
| TC-02 | U | Nạp từng file trong F4 | Từ chối kèm đúng mã lỗi; không crash | GS-02 |
| TC-03 | U | Số kiểu `1.0` hợp lệ; `1.5` thì bị từ chối | Ép `int()` đúng; `1.5` cho lỗi | GS-02 |
| TC-64 [M] | U | Nạp F5 (`count` lệch) | Từ chối `count_mismatch`; **không** tự sửa; không vào màn | GS-02a |
| TC-65 [M] | U | Nạp F6 (màu không ô nào dùng) | Từ chối `unused_color` | GS-02b |
| TC-66 [M] | U | `cells` chứa mã 9 (không có trong palette) | Từ chối `unknown_color` | GS-02c |
| TC-67 [M] | U | Nạp F7 (toàn `-1`) và F8 (rỗng) | Từ chối `no_playable_cells` hoặc `grid_size` | GS-02d |
| TC-68 [M] | U | `len(cells) ≠ width×height` | Từ chối `grid_size` | GS-02d |
| TC-04 [S] | U | Vào F2 khi chưa có tiến độ | `selected` = màu có `remaining` lớn nhất | GS-06 |
| TC-69 [M] | U | Vào F11 (hai màu bằng nhau, ID lớn đứng trước trong file) | Chọn ID **nhỏ hơn**; kết quả không phụ thuộc thứ tự trong file | GS-06 |
| TC-05 | U | `selected` đã lưu là màu đã xong | Chọn lại theo quy tắc GS-06 | GS-06 |

### B. Đặt hạt và chạm sai

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-06 | U | F1, chọn 0, chạm (0,0) | Đặt hạt; `remaining[0] = 1`; `last_placed = 0` | GS-15 |
| TC-07 | U | F1, chọn 0, chạm (1,0) (màu 1) | Không đặt; `wrong_tap`; `last_placed` không đổi | GS-16, 50 |
| TC-08 | U | Chạm lại ô vừa đặt | Không đổi trạng thái; `last_placed` giữ nguyên | GS-17 |
| TC-09 | U | Chạm ô `-1`; chạm ngoài lưới | Không đổi trạng thái | GS-18 |
| TC-10 | U | `selected = none`, rồi chạm | Không đặt; hiện dòng nhắc | GS-19 |
| TC-11 | U | 3 lần sai → gợi ý; đặt đúng → gợi ý ẩn, đếm về 0 | Như mô tả | GS-21 |
| TC-12 | I | Zen, tắt phản hồi chạm sai, rồi chạm sai | Im lặng; trạng thái không đổi | GS-22 |
| TC-13 | U | Hoàn thành F1 | 5 lần đặt; 3 sự kiện hoàn thành màu; `completed`; mọi tap và Undo bị khoá | GS-09, 51 |
| TC-14 | U | Phát lại toàn bộ F3 | Bất biến đúng sau từng bước | GS-04 |
| TC-15 [S] | U | 10.000 thao tác ngẫu nhiên (tap / Undo / đổi màu / Tìm), seed cố định, trên F2 | Không bao giờ đặt sai màu; bất biến luôn đúng | GS-04, 15, 47 |

### C. Undo

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-70 [M] | U | F1: đặt (0,0) rồi Undo | `placed[0] = false`; `remaining[0] = 2`; `last_placed = none`; nút Undo bị vô hiệu | GS-46, 47 |
| TC-71 [M] | U | Undo hai lần liên tiếp | Lần thứ hai không làm gì | GS-45, 47 |
| TC-72 [M] | U | Đặt hạt cuối của màu 2 (màu xong) rồi Undo | Màu 2 trở lại chưa xong; swatch khôi phục; đặt lại thì phát `color_complete{repeat: true}` | GS-47, 52 |
| TC-73 [M] | U | Đặt → chạm sai → đổi màu → Tìm → zoom → Undo | Hạt vừa đặt được hoàn tác; `selected` và camera không đổi | GS-48, 50 |
| TC-74 [M] | U | Hoàn thành tranh rồi bấm Undo | Không làm gì; Journey vẫn giữ việc mở khoá | GS-51 |
| TC-75 [M] | I | Undo khi ô vừa đặt nằm ngoài khung nhìn | Hiện dòng nhắc; camera không di chuyển; Tìm có xét tới ô này | GS-48, 29d |
| TC-77 [M] | I | Bật Reduce Motion rồi Undo | Chỉ có mờ dần | GS-36 |

### D. Cử chỉ và biên ô

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-16 | I | Một ngón, di chuyển 6pt, giữ 200 ms | Là tap | GS-10 |
| TC-17 | I | Kéo 15pt rồi nhấc | Là pan, không đặt hạt | GS-10 |
| TC-18 | I | Giữ 700 ms rồi nhấc | Không đặt hạt | GS-10 |
| TC-19 [S] | I | Pinch; nhấc ngón 1; ngón 2 đứng yên 300 ms trên ô hợp lệ rồi nhấc | **Không** đặt hạt (phiên đã có nhiều ngón) | GS-11 |
| TC-78 [M] | I | Ngay sau pinch (60 ms), chạm một ngón vào ô hợp lệ | Không đặt hạt (trong thời gian chặn) | GS-10 |
| TC-79 [M] | I | Đã qua 200 ms sau pinch, chạm vào ô hợp lệ | Đặt hạt | GS-10 |
| TC-80 [M] | I | Đang pan có quán tính, chạm vào ô hợp lệ | Camera dừng; không đặt hạt | GS-12 |
| TC-81 [M] | I | Chạm xuống ở ô A, nhấc lên ở ô B, khoảng cách ≤ 10pt | Áp dụng cho ô **A** (điểm chạm xuống) | GS-13 |
| TC-82 [M] | U | Điểm nằm đúng biên x = 3,0 / y = 2,0 | Thuộc ô (3,2); lặp lại 1000 lần cho kết quả giống nhau | GS-13 |
| TC-83 [M] | I | Chạm lệch 2pt sang ô kề khác màu khi `snap` tắt | Phản hồi chạm sai; không đặt hạt | GS-13a |
| TC-84 [M] | I | Bắt đầu trên tranh, kết thúc trên khay | Không tạo tap; không đổi màu | GS-13b |
| TC-85 [M] | I | Chạm ba ngón | Bỏ qua | GS-13d |
| TC-20 | I | Chạm ở góc ô, ngoài hình tròn của hạt | Đặt vào đúng ô đó | GS-13 |
| TC-21 | I | Chạm đúp | Lần đầu đặt hạt; camera không zoom | GS-14 |
| TC-22 | D | Pan và zoom liên tục 2 phút trên F3 | 0 hạt đặt ngoài ý muốn | GS-10–12, H8 |
| TC-76 [M] | D | Chạm vào ô cách mép trái/phải ≤ 8pt, và ô gần vùng thanh home | Ghi lại tỷ lệ bị cử chỉ hệ thống chiếm; quyết định có bật `EDGE_GUARD` | GS-13c |

### E. Zoom toàn cảnh và nút Tìm

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-87 [M] | I | F3 ở zoom toàn cảnh (ô khoảng 11pt), chạm vào ô hợp lệ | Không đặt hạt; không có phản hồi sai; zoom tới ô 32pt quanh điểm chạm; gợi ý hiện một lần | GS-14a |
| TC-88 [M] | I | Lặp lại TC-87 lần thứ hai trong cùng phiên | Không hiện lại gợi ý | GS-14a |
| TC-89 [M] | I | Zoom toàn cảnh: kiểm tra làm nổi và số | Ô hợp lệ vẫn nổi; số hiện nếu ô ≥ 18pt | GS-14b, 24 |
| TC-31 [S] | U | Màu còn 3 ô ngoài khung nhìn; bấm Tìm 4 lần | 3 ô khác nhau theo thứ tự gần nhất; lần 4 xoá tập đã thăm và chọn lại theo quy tắc | GS-29 |
| TC-32 | U | Mọi ô hợp lệ đều đang trong khung nhìn | Chọn ô chưa thăm gần tâm nhất | GS-29 |
| TC-90 [M] | U | Hai ô cách đều tâm | Chọn ô có chỉ số nhỏ hơn | GS-29 |
| TC-91 [M] | I | Tìm từ zoom toàn cảnh | Mức zoom sau khi Tìm ≥ 32pt; chạm ngay vào ô đích thì đặt được hạt | GS-29a |
| TC-33 | I | Tìm khi màu đã xong, khi `none`, khi tranh đã xong | Nút bị vô hiệu kèm chú thích | GS-29b |
| TC-34, 35, 36 | I | Ngắt chuyển động; Reduce Motion; vòng sáng một lần | Như mô tả ở GS-29a | GS-29a |
| TC-92 [M] | U | Tìm tới ô X, đặt hạt X, Undo, rồi Tìm | X có thể được chọn lại | GS-29d |

### F. Hiển thị, khay, âm thanh

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-23, 24, 25 | U/I | Tập ô làm nổi; không nhấp nháy; ngưỡng hiện số | Như ở v0.1 | GS-23, 24 |
| TC-26 [S] | I | Với từng màu của F2: chụp viewport 1:1, đo vành khuyên 0,35r–0,65r bỏ cung highlight, lấy trung vị Lab | ΔE00 ≤ 2,0 | GS-25 |
| TC-26b [M] | I | Đối chứng: đo cả hạt (gồm highlight và bóng) | Ghi lại để chứng minh vùng đo đúng là phần thân; không dùng làm tiêu chí | GS-25a |
| TC-27 [S] | I | Đặt hạt, rồi Undo | Số trên swatch −1, rồi +1, ngay trong khung hình kế tiếp | GS-27 |
| TC-28, 29, 30 | I/D | Camera giữ nguyên khi đổi màu; xong màu; kích thước khay | Như ở v0.1 | GS-07, 08, 26, 28 |
| TC-37 đến 43 | U/I/D | Âm thanh, giới hạn số âm, haptic, cài đặt, Reduce Motion, không chặn thao tác | Như ở v0.1 | GS-31 đến 37 |

### G. Lưu và khôi phục

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-44 [S] | D | Đặt 37 hạt; đóng cưỡng bức **≥ 200 ms** sau hạt cuối (vuốt tắt app, hoặc dừng từ Xcode) | Mở lại: đủ 37 hạt | GS-30, 30a |
| TC-44b [M] | D | Đóng cưỡng bức **ngay** sau hạt thứ 37 | Mở lại có 36 hoặc 37 hạt; không ít hơn 36 | GS-30a |
| TC-45 | D | Đặt hạt rồi đưa app xuống nền ngay | Mở lại đủ hạt | GS-30 |
| TC-93 [M] | U | Mô phỏng: không có callback tắt app nào được gọi | Dữ liệu vẫn đúng như TC-44, vì không phụ thuộc callback | GS-30 |
| TC-94 [M] | D | Đặt hạt, Undo, đóng cưỡng bức sau ≥ 200 ms | Mở lại: hạt vừa hoàn tác **không** có; `remaining` đúng; nút Undo bị vô hiệu | GS-49, Q-8 |
| TC-95 [M] | U | Đặt → ghi → Undo → ghi; đọc lại file | `placed` và `remaining` đã tính lại khớp trạng thái sau Undo | GS-30, 38a |
| TC-46 [S] | U | Khôi phục với F10 (đổi `cells`) | `layout_hash` lệch nên bắt đầu lại; file cũ thành `.stale`; có thông báo | GS-38c |
| TC-96 [M] | U | Khôi phục với F9 (chỉ đổi `hex`) | `content_hash` lệch nhưng `layout_hash` khớp: giữ `placed` và hiện thông báo đổi màu (theo Q-9) | GS-38b |
| TC-97 [M] | U | Chỉ đổi `schema_version` | `content_hash` đổi; xử lý theo GS-38b nếu tương thích | GS-38 |
| TC-86 [M] | U | Tính `content_hash` và `layout_hash` cho F1, F2, F3 bằng Python và bằng Godot | Hai bên cho ra giống hệt nhau | GS-38 |
| TC-98 [M] | U | Đổi thứ tự khoá JSON, hoặc viết `hex` chữ hoa | Hash không đổi (nhờ chuẩn hoá) | GS-38 |
| TC-47 [S] | U | File chính hỏng, `.bak` còn tốt | Khôi phục từ `.bak` | GS-38d |
| TC-47b [M] | U | Cả file chính và `.bak` đều hỏng | Bắt đầu lại; ghi log; không crash; cài đặt vẫn còn | GS-38d, 39 |
| TC-48 | U | Ngắt giữa lúc ghi | File chính còn bản cũ hợp lệ | GS-30b |
| TC-49 | D | Hoàn thành tranh rồi mở lại | Hiện trạng thái đã hoàn thành; Undo bị khoá | GS-09, 51 |

### H. Zen, Journey, hiệu năng, trợ năng, người chơi

| ID | Cấp | Nội dung | Quy tắc |
|---|---|---|---|
| TC-50 đến 53 | U/I | Như ở v0.1: hai chế độ đặt hạt giống nhau; Journey khoá theo thứ tự; tuỳ chọn tắt chạm sai chỉ có ở Zen; tiến độ dùng chung theo Q-6 | GS-40, 41 |
| TC-54 [S] | D | F3: pan, zoom, chạm 5 lần/giây trong 60 giây, **kèm ghi file sau mỗi lần đặt** → p95 ≤ 16,7 ms | GS-42 |
| TC-55 | D | Độ trễ từ nhấc tay đến khi hạt xuất hiện ≤ 50 ms | GS-42 |
| TC-56 | D | Chế độ mô phỏng mù màu vẫn chơi được | GS-43 |
| TC-57 [S] | U | Sự kiện đo lường đầy đủ, gồm cả `tap_to_zoom`, `undo_used`, `save_restore` | GS-44 |
| TC-58 đến 63 | P | H1–H6 như ở v0.1 | — |
| TC-99 [M] | P | H7: so sánh `MIN_PLACE_CELL` 20 / 24 / 28pt | Tỷ lệ Undo ngay sau đặt; số lần zoom mỗi phút | H7 |
| TC-100 [M] | P/D | H8: phiên cử chỉ tự do 5 phút cho mỗi người | Số lần đặt nhầm; số tap hợp lệ bị bỏ qua | H8 |

---

## Xác nhận trạng thái

Tôi chỉ đọc repo và tính toán số học (không tạo hay sửa file trong repo):
- HEAD `8feed74` trên nhánh `claude/cloud-session-connection-check-hksw4v`, không có stash.
- `git status`, hash của phần thay đổi chưa commit và hash của mọi file chưa theo dõi **trùng khớp** với mốc đã ghi.
- Không commit, push, reset, stash hay checkout.

Tôi dừng ở đây để bạn duyệt, đặc biệt là Q-1, Q-2 và Q-4 đến Q-10.
