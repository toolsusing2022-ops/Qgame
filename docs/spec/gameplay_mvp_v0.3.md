<!-- Lưu trữ nguyên văn bản đặc tả v0.3 từ phiên làm việc. Xem docs/spec/README.md để biết cách đọc. -->

# Đặc tả gameplay MVP v0.3 — Pixel Bead Art ASMR (chờ duyệt)

Bản v0.3 là bản **hoàn chỉnh, thay thế v0.2**.

**Thay đổi về cách đánh số:**
- Mã quy tắc đổi sang dạng `GS-<mục>.<số>`, test case đổi sang `TC-<mục>.<số>`, để mỗi test trỏ đúng vào mục nó kiểm tra.
- Bảng đối chiếu mã cũ của v0.2 với mã mới nằm ở phần **B**, sau bản đặc tả.

---

## 0. Quyết định đã chốt và tham số

### 0.1 Quyết định đã chốt

| Mã | Quyết định |
|---|---|
| D-1 | Màu mặc định là màu có `remaining` lớn nhất; bằng nhau thì chọn ID nhỏ nhất. Không phụ thuộc thứ tự palette |
| D-2 | Mọi thông số cảm ứng, zoom và kích thước ô ở mục 0.2 chỉ là **mặc định để thử trên iPhone thật** |
| D-3 | Có Undo một bước: chỉ hoàn tác lần đặt hạt thành công gần nhất trong phiên hiện tại; không có Redo |
| D-4 | Chạm vào ô đã có hạt: im lặng, không haptic, không thay đổi trạng thái Undo |
| D-5 | Haptic chỉ dùng khi đặt hạt thành công. Không haptic cho chạm sai hay Undo |
| D-6 | Zen và Journey dùng chung tiến độ của từng level |
| D-7 | `squid_easy_01` và `squid_relax_01` chỉ dùng cho kiểm thử nội bộ, sau khi qua validator; chưa phải nội dung phát hành |
| D-8 | Không lưu `last_placed` qua lần mở app. Sau khi khởi động lại, Undo bị vô hiệu cho tới lần đặt hạt mới |
| D-9 | Chỉ đổi `hex` (bố cục và ID ô giữ nguyên) thì giữ tiến độ kèm thông báo. Đổi schema thì chỉ giữ tiến độ khi có migration đã định nghĩa và kiểm thử |
| D-10 | Ô nhỏ hơn `MIN_PLACE_CELL` thì chạm sẽ zoom quanh điểm đó: không đặt hạt, không báo chạm sai |

### 0.2 Tham số (đều là mặc định, chờ thử thiết bị)

| Tham số | Mặc định | Ghi chú |
|---|---|---|
| `TAP_SLOP` | 10pt | Ngưỡng phân biệt tap với pan |
| `TAP_MAX_MS` | 500 ms | |
| `MULTI_TOUCH_COOLDOWN_MS` | 120 ms | Thời gian chặn tap sau một phiên nhiều ngón |
| `NUMBER_VISIBLE_CELL` | 18pt | Cỡ ô tối thiểu để hiện số |
| `MIN_PLACE_CELL` | 24pt | Theo WCAG 2.5.8 mức AA |
| `PLACE_ZOOM_CELL` | 32pt | Mức zoom đích của chạm-để-zoom và nút Tìm |
| `MAX_ZOOM_CELL` | 72pt | |
| `EDGE_GUARD` | 0pt (tắt) | |
| `WRONG_TAP_HINT_AFTER` | 3 | |
| `SFX_VOICES_MAX` | 4 | |
| `HAPTIC_MIN_INTERVAL_MS` | 40 ms | |
| `FIND_ANIM_MS` | 250–400 ms | |
| `auto_switch_color` | tắt | Giả thuyết H2 |
| `snap_to_nearest` | tắt | Giả thuyết H1 |

- **Ràng buộc giữa các tham số:**
  - Phải luôn có: `NUMBER_VISIBLE_CELL ≤ MIN_PLACE_CELL ≤ PLACE_ZOOM_CELL ≤ MAX_ZOOM_CELL`.
  - Bản build debug dừng ngay khi khởi động nếu cấu hình vi phạm ràng buộc này (TC-5.23).
- **Hệ quả với hai level nội bộ** (lề hai bên 16pt):
  - Ở zoom toàn cảnh, Easy có ô 17,1–19,9pt và Relax có ô 10,7–12,4pt.
  - Cả hai đều nhỏ hơn 24pt, nên trên mọi iPhone, lần chạm đầu tiên sẽ là chạm-để-zoom.

---

## 1. Phạm vi

| Trong MVP | Ngoài MVP |
|---|---|
| Chọn màu → chạm ô đúng → đặt 1 bead | Tô vùng liền, hoàn thành cả màu, kéo để đặt liên tiếp |
| Làm nổi tĩnh các ô hợp lệ; chạm sai không phạt | Hít về ô gần nhất (H1), tự chuyển màu (H2) |
| Nút Tìm, Undo một bước, zoom/pan, Toàn cảnh, chạm-để-zoom | Undo nhiều bước, Redo, chạm đúp để zoom |
| Lưu và khôi phục; migration theo danh sách đăng ký (MVP chưa có migration nào) | Đặt lại tiến độ để chơi lại, đồng bộ đám mây |
| Âm thanh ASMR, haptic, cài đặt; sự kiện phân tích lưu cục bộ | Combo, điểm số, giới hạn trợ giúp |
| Zen và Journey dùng chung hệ thống đặt hạt và tiến độ | Layout iPad riêng |

---

## 2. Dữ liệu level

- **GS-2.1. Định dạng:** level dùng schema v1.
  - `cells[y*width+x]` là mảng phẳng; `-1` là vị trí không có hạt.
  - `palette[i].id == i`.
  - `mask` (nếu có) gameplay bỏ qua.
- **GS-2.2. Kiểu số:** Godot đọc mọi số trong JSON thành `float`.
  - Ép `int()` và chỉ chấp nhận giá trị là số nguyên đúng (ví dụ `1.0` được, `1.5` bị từ chối).
  - Lưu `cells` thành `PackedInt32Array`.
- **GS-2.3. Đếm số ô còn lại:**
  - `remaining[c]` được **tự đếm** từ `cells` rồi đối chiếu với `palette[c].count`.
  - Lệch ở bất kỳ màu nào thì từ chối (`count_mismatch`). Không bao giờ tự sửa số.
- **GS-2.4. Các lỗi palette dẫn tới từ chối:**
  - `unknown_color`: trong `cells` có giá trị âm khác `-1`, hoặc ≥ số màu.
  - `unused_color`: màu có trong palette nhưng không ô nào dùng.
  - `bad_hex`: mã màu không đúng dạng `#rrggbb`.
  - `duplicate_color`: hai màu trùng `hex`.
  - `palette_id`: `id ≠` vị trí trong mảng.
  - Các lỗi thiếu trường hoặc sai kiểu.
- **GS-2.5. Các lỗi lưới dẫn tới từ chối:**
  - `no_playable_cells`: lưới rỗng hoặc toàn `-1`.
  - `grid_size`: `width`/`height` ngoài khoảng 1..128, hoặc `len(cells) ≠ width×height`.
- **GS-2.6. Xử lý level bị từ chối:**
  - Không bao giờ vào màn chơi và không nạp một phần.
  - Hiện "Không mở được tranh này", ghi log mã lỗi.
  - Loader của Godot và `validate_level.py` phải cho **cùng kết quả** (chấp nhận/từ chối và mã lỗi) trên cùng bộ dữ liệu.
- **GS-2.7. Định nghĩa:**
  - **Ô chơi được:** `cells[i] ≥ 0`.
  - **Ô hợp lệ cho màu `c`:** chơi được, chưa đặt hạt, và `cells[i] == c`.
  - **Màu xong:** `remaining[c] = 0`.
  - **Tranh xong:** `Σ remaining = 0`.

---

## 3. Trạng thái

| Trường | Lưu qua lần mở app? | Ý nghĩa |
|---|---|---|
| `placed` (bitset dài `w×h`) | Có | Ô đã có hạt |
| `remaining[c]` | Không — luôn tính lại | |
| `selected` | Có | ID màu đang chọn, hoặc `none` |
| `completed`, `completion_reported` | Có | |
| `colors_ever_completed` (bitset dài bằng số màu) | Có | Dùng để phân biệt sự kiện hoàn thành màu lần đầu với lần lặp lại |
| `last_placed` | **Không** (D-8) | Ô của lần đặt thành công gần nhất trong phiên |
| `find_visited[c]` | Không | Các ô nút Tìm đã đưa tới |
| `camera` | Không | Mỗi lần vào màn đều bắt đầu ở toàn cảnh |
| `wrong_streak` | Không | Số lần chạm sai liên tiếp |

- **GS-3.1. Bất biến:** phải đúng sau mọi thao tác (đặt hạt, Undo, khôi phục, migration).
  - `remaining[c] = count(i: cells[i]=c và chưa placed[i])`
  - `placed[i] ⇒ cells[i] ≥ 0`
  - `completed ⇔ Σ remaining = 0`
  - `colors_ever_completed ⊇ {c : remaining[c] = 0}`
- **GS-3.2. Phiên chơi** bắt đầu khi vào màn của một level và kết thúc khi rời màn đó, hoặc khi tiến trình app bị dừng. Đưa app xuống nền mà tiến trình vẫn sống thì phiên **vẫn tiếp tục**.

---

## 4. Luồng màn chơi

- **GS-4.1. Vào màn:**
  - Nạp level (mục 2), khôi phục tiến độ (mục 13).
  - Camera về toàn cảnh.
  - `last_placed = none`, `find_visited` rỗng, `wrong_streak = 0`.
- **GS-4.2. Màu được chọn khi vào màn (D-1):**
  - Nếu `selected` đã lưu và màu đó chưa xong thì giữ.
  - Nếu không, chọn màu chưa xong có `remaining` lớn nhất; bằng nhau thì lấy ID nhỏ nhất.
- **GS-4.3. Đổi màu:**
  - Chạm swatch thì `selected` đổi, vùng làm nổi đổi theo, phát tiếng nhấc hạt.
  - Camera **không** di chuyển.
  - Chọn màu đã xong thì không có ô nào nổi.
  - Đổi màu **không** ảnh hưởng tới `last_placed` và `find_visited`.
- **GS-4.4. Hết một màu:**
  - Phát tiếng hoàn thành màu, swatch chuyển sang trạng thái xong.
  - `selected` giữ nguyên (`auto_switch_color` tắt).
  - Hiện dòng nhắc chọn màu khác; các swatch còn màu chưa xong được viền nhẹ trong 1,5 giây, không nhấp nháy.
- **GS-4.5. Hết tranh:**
  - Khoá đặt hạt, Undo và Tìm; phát tiếng hoàn thành tranh.
  - Ghi `completed = true` và `completion_reported = true` trong **cùng một lần ghi atomic**.
  - Hiện màn hoàn thành.
  - Journey mở khoá tranh kế tiếp (suy ra từ `completed`); Zen quay về danh sách tranh.
- **GS-4.6. Mở lại level đã xong:** chỉ hiện tranh đã hoàn thành.
  - Không đặt hạt, không Undo, không Tìm.
  - Không phát sự kiện `level_complete`.
  - MVP không có tính năng đặt lại tiến độ.

---

## 5. Cử chỉ: tap, pan, pinch và zoom

- **GS-5.1. Điều kiện để một phiên cử chỉ tạo ra tap.** Phiên cử chỉ kéo dài từ lúc ngón đầu tiên chạm xuống tới khi mọi ngón đã nhấc. Phiên chỉ tạo tap khi thoả **đủ** các điều kiện:
  - (a) suốt phiên chỉ có đúng 1 ngón;
  - (b) quãng di chuyển tối đa ≤ `TAP_SLOP`;
  - (c) thời lượng ≤ `TAP_MAX_MS`;
  - (d) lúc chạm xuống, camera **không** đang chuyển động (kể cả trôi theo quán tính hay hoạt ảnh do game tự chạy);
  - (e) đã qua ≥ `MULTI_TOUCH_COOLDOWN_MS` kể từ khi phiên nhiều ngón gần nhất kết thúc.
- **GS-5.2. Phiên nhiều ngón:** một phiên đã từng có ≥ 2 ngón thì không bao giờ tạo tap. Ngón còn lại sau pinch tiếp tục pan mượt.
- **GS-5.3. Chạm khi camera đang chuyển động:** chạm xuống khi camera đang trôi hoặc đang chạy hoạt ảnh thì chuyển động **dừng lại**, và phiên đó không tạo tap.
- **GS-5.4. Xác định ô được chạm:**
  - Dùng **điểm chạm xuống**, quy đổi theo trạng thái camera **tại thời điểm chạm xuống**.
  - Ô là hình vuông `[x, x+1) × [y, y+1)`. Điểm nằm đúng trên biên thuộc về ô bên phải hoặc bên dưới, nên kết quả luôn tất định.
  - Vùng chạm là toàn bộ hình vuông của ô, không chỉ hình tròn của hạt.
- **GS-5.5. Chạm lệch:** với `snap_to_nearest` tắt, chạm lệch sang ô bên cạnh được xử lý như một lần chạm vào chính ô bên cạnh đó.
- **GS-5.6. Ranh giới với giao diện:**
  - Phiên bắt đầu trên khay hoặc nút thì do giao diện đó xử lý.
  - Phiên bắt đầu trên tranh mà kết thúc ngoài tranh thì không tạo tap.
- **GS-5.7.** Từ 3 ngón trở lên thì bỏ qua.
- **GS-5.8. Mép màn hình:** tranh không nằm dưới thanh home. `EDGE_GUARD` mặc định tắt; chỉ bật nếu TC-5.13 cho thấy xung đột với cử chỉ hệ thống.
- **GS-5.9. Zoom:**
  - Pinch zoom quanh tâm hai ngón, giới hạn từ toàn cảnh tới `MAX_ZOOM_CELL`.
  - Không có chạm đúp để zoom.
  - Nút Toàn cảnh đưa camera về vừa khung.
- **GS-5.10. Chạm-để-zoom (D-10).** Nếu lúc chạm xuống, cỡ ô trên màn hình < `MIN_PLACE_CELL`:
  - Tap không đặt hạt, không có phản hồi sai, không phát âm thanh, không đổi `last_placed`.
  - Camera phóng tới `PLACE_ZOOM_CELL`, lấy điểm chạm làm tâm.
  - Gợi ý "Phóng to để đặt hạt" hiện một lần mỗi phiên.
  - Khi Reduce Motion bật: nhảy thẳng tới mức zoom.
- **GS-5.11. Không bao giờ tự đặt hạt khi zoom:**
  - Pinch, chạm-để-zoom, nút Tìm và nút Toàn cảnh đều không đặt hạt.
  - Không xếp hàng tap trong lúc camera đang chạy hoạt ảnh.
  - Sau khi hoạt ảnh kết thúc, cần một tap mới thì mới đặt hạt.
- **GS-5.12. Ở zoom toàn cảnh:** vẫn làm nổi ô hợp lệ, vẫn hiện số nếu ô ≥ `NUMBER_VISIBLE_CELL`.

---

## 6. Kết quả của một tap

Mục này áp dụng khi lúc chạm xuống, cỡ ô ≥ `MIN_PLACE_CELL`.

| Mã | Tình huống | Trạng thái | Phản hồi |
|---|---|---|---|
| GS-6.1 | Ô hợp lệ của màu đang chọn | Đặt hạt; `remaining −1`; `last_placed = i`; `wrong_streak = 0`; ghi tiến độ (GS-12.1) | Tiếng đặt hạt, hoạt ảnh, haptic (D-5) |
| GS-6.2 | Ô chưa đặt nhưng khác màu đang chọn | Không đổi; `wrong_streak +1`; `last_placed` không đổi | Phản hồi chạm sai (GS-6.6), không haptic |
| GS-6.3 | Ô đã có hạt (D-4) | Không đổi; `last_placed` không đổi | Im lặng hoàn toàn |
| GS-6.4 | Vị trí `-1` hoặc ngoài lưới | Không đổi | Im lặng |
| GS-6.5 | `selected = none` hoặc màu đang chọn đã xong | Không đổi | Dòng nhắc ở khay, không âm thanh |

- **GS-6.6. Phản hồi chạm sai:**
  - Ô vừa chạm hiện số của nó trong 0,6 giây.
  - Swatch đúng màu sáng viền một lần.
  - Một tiếng "tok" trầm, nhỏ hơn tiếng đặt hạt khoảng 6 dB.
  - Không haptic.
- **GS-6.7. Gợi ý khi sai liên tiếp:**
  - Khi `wrong_streak ≥ WRONG_TAP_HINT_AFTER`, hiện gợi ý chữ trong 3 giây.
  - `wrong_streak` về 0 khi: đặt hạt thành công, Undo, hoặc đổi màu.
- **GS-6.8. Tắt phản hồi chạm sai (chỉ Zen):** tắt cả phần nhìn lẫn phần nghe. Trạng thái và sự kiện phân tích vẫn ghi như bình thường.

---

## 7. Hiển thị

- **GS-7.1. Ba trạng thái ô:**
  - **Chưa đính:** nền nhạt cùng tông màu đích.
  - **Hợp lệ:** đậm hơn, có viền, **tĩnh**: không nhấp nháy, không có chuyển động lặp.
  - **Đã đặt:** hạt đúng màu `hex`.
- **GS-7.2.** Số màu hiện khi ô ≥ `NUMBER_VISIBLE_CELL`.
- **GS-7.3. Đo độ chính xác màu:**
  - Chụp từ viewport của engine ở tỉ lệ 1:1 (sRGB), không dùng ảnh chụp màn hình thiết bị.
  - Vùng đo là vành khuyên **0,35r–0,65r** tính từ tâm hạt, **bỏ góc phần tư trên-trái**.
  - Đổi các pixel trong vùng sang Lab và lấy **trung vị**.
  - Yêu cầu ΔE00(trung vị, `hex`) ≤ 2,0.
- **GS-7.4. Ràng buộc với shader của hạt** (để phép đo ở GS-7.3 có nghĩa):
  - Highlight chỉ nằm trong góc phần tư trên-trái.
  - Bóng chỉ nằm ở vùng r > 0,65.
  - Trong vùng đo, hệ số sáng ≈ 1.
  - Nếu thiết kế hạt thay đổi, phải định nghĩa lại vùng đo **trước khi** chạy test.

---

## 8. Khay màu và hàng hành động

- **GS-8.1. Khay:**
  - Swatch xếp theo ID, mỗi swatch ≥ 44×44pt.
  - Mỗi swatch hiện mã màu, số ID, `remaining`.
  - Swatch đang chọn to hơn, có viền; swatch đã xong mờ đi, có dấu tích.
- **GS-8.2.** Số `remaining` cập nhật ngay trong khung hình kế tiếp sau khi đặt hạt hoặc Undo.
- **GS-8.3.** Khay không che tranh; tôn trọng safe area.
- **GS-8.4. Hàng hành động:** Tìm, Undo, Toàn cảnh, Cài đặt, mỗi nút ≥ 44pt. Trạng thái vô hiệu của Tìm và Undo phải nhìn thấy được và đọc được bằng VoiceOver.

---

## 9. Nút Tìm

- **GS-9.1. Chọn ô đích:** chỉ xét các ô hợp lệ của `selected`. Thứ tự ưu tiên:
  1. Ô chưa có trong `find_visited[selected]` **và** đang nằm ngoài khung nhìn.
  2. Ô chưa có trong `find_visited[selected]`.
  3. Nếu đã thăm hết: xoá `find_visited[selected]` rồi chọn trong tất cả ô hợp lệ.
  - Trong tập được chọn, lấy ô có tâm gần tâm khung nhìn nhất (khoảng cách Euclid trong toạ độ lưới). Hoà nhau thì lấy chỉ số `y*w+x` nhỏ nhất.
- **GS-9.2. Camera:**
  - Zoom = max(mức hiện tại, `PLACE_ZOOM_CELL`), hoạt ảnh `FIND_ANIM_MS`.
  - Reduce Motion bật thì nhảy thẳng.
  - Có chạm thì dừng ngay, và lần chạm đó không tạo tap (GS-5.3).
  - Ô đích hiện vòng sáng mờ dần một lần.
- **GS-9.3.** `find_visited` tính riêng theo từng màu, chỉ tồn tại trong phiên.
- **GS-9.4.** Nút Tìm bị vô hiệu khi `selected = none`, màu đang chọn đã xong, hoặc tranh đã xong.
- **GS-9.5.** Sau Undo, ô vừa hoàn tác bị xoá khỏi `find_visited` của màu nó.
- **GS-9.6.** Tìm không bao giờ đặt hạt, không đổi `selected`, không đổi `last_placed`. MVP không giới hạn số lần Tìm.

---

## 10. Undo (D-3, D-8)

- **GS-10.1. Phạm vi:** Undo hoàn tác **lần đặt hạt thành công gần nhất trong phiên hiện tại** (GS-3.2). Chỉ một bước, không có Redo.
- **GS-10.2. Khi nào dùng được:** chỉ khi `last_placed ≠ none` **và** `completed = false`.
- **GS-10.3. Tác dụng:**
  - `placed[i] = false`, `remaining[c] += 1`, với `c = cells[i]`.
  - Nếu `c` đang ở trạng thái xong thì trở lại chưa xong.
  - `last_placed = none`, nút Undo bị vô hiệu.
  - `colors_ever_completed` **không** bị xoá.
- **GS-10.4.** Undo không đổi `selected` và không di chuyển camera. Nếu ô vừa hoàn tác nằm ngoài khung nhìn, hiện dòng nhắc ngắn "Đã hoàn tác 1 hạt".
- **GS-10.5. Những thao tác KHÔNG ghi đè `last_placed`:**
  - chạm sai;
  - chạm ô đã có hạt;
  - chạm `-1` hoặc ngoài lưới;
  - chạm-để-zoom;
  - đổi màu;
  - Tìm;
  - pan, pinch, Toàn cảnh;
  - mở Cài đặt;
  - đưa app xuống nền khi tiến trình vẫn sống.
  - Chỉ một lần đặt hạt thành công mới thay `last_placed`.
- **GS-10.6. Khi nào `last_placed` bị xoá:**
  - sau khi Undo;
  - khi tranh xong;
  - khi rời màn của level;
  - khi tiến trình app bị dừng.
- **GS-10.7. Phản hồi và lưu:**
  - Tiếng nhấc hạt; hạt thu nhỏ và mờ đi trong ≤ 150 ms; không haptic.
  - Ghi tiến độ ngay (GS-12.1).
- **GS-10.8.** Undo đưa `wrong_streak` về 0.

---

## 11. Âm thanh, haptic, hoạt ảnh

Phần này tách hẳn khỏi sự kiện phân tích (mục 14).

- **GS-11.1. Âm thanh theo từng tình huống:**

| Tình huống | Âm thanh |
|---|---|
| Đặt hạt thành công | 4–6 mẫu chọn ngẫu nhiên, không lặp mẫu liền kề, cao độ ±3% |
| Chạm sai | Tiếng "tok" trầm, nhỏ hơn khoảng 6 dB (có thể tắt trong Zen) |
| Undo | Tiếng nhấc hạt |
| Đổi màu | Tiếng nhấc hạt nhẹ |
| Hoàn thành màu | Chuông ngắn ≤ 1,2 giây, phát ở **mọi** lần chuyển sang trạng thái xong, kể cả lần lặp lại sau Undo |
| Hoàn thành tranh | ≤ 3 giây, chỉ một lần |
| Chạm ô đã có hạt, `-1`/ngoài lưới, chạm-để-zoom, Tìm, dòng nhắc | Im lặng |

- **GS-11.2.** Tối đa `SFX_VOICES_MAX` âm phát cùng lúc; âm mới thay âm cũ nhất.
- **GS-11.3. Âm nền:** có các lựa chọn tắt, biển, mưa. Âm lượng tách riêng với âm hiệu ứng; giảm nhẹ khi phát tiếng hoàn thành tranh.
- **GS-11.4. Haptic (D-5):**
  - **Chỉ** khi đặt hạt thành công: tác động nhẹ, giãn cách ≥ `HAPTIC_MIN_INTERVAL_MS`.
  - Bật/tắt riêng.
  - Thiết bị không hỗ trợ thì bỏ qua, không báo lỗi.
- **GS-11.5. Hoạt ảnh:**
  - Đặt hạt: phóng 1,0 → 1,15 → 1,0 trong ≤ 200 ms.
  - Undo: thu nhỏ và mờ đi trong ≤ 150 ms.
  - Khi Reduce Motion bật: chỉ mờ dần.
  - Không hoạt ảnh nào chặn thao tác.
- **GS-11.6.** Cài đặt gồm âm hiệu ứng, âm nền, haptic, phản hồi chạm sai (chỉ Zen). Lưu tách riêng với tiến độ.

---

## 12. Lưu tiến độ

- **GS-12.1. Khi nào ghi:**
  - Ghi **ngay sau mỗi lần đặt hạt thành công và mỗi lần Undo**, không có độ trễ cố ý.
  - Nếu một lần ghi đang chạy thì gộp các thay đổi mới vào đúng **một** lần ghi kế tiếp.
  - Ghi thêm khi app xuống nền, mất tiêu điểm, hoặc rời màn của level.
  - **Không** dựa vào callback khi app bị tắt hay bị đóng cưỡng bức.
- **GS-12.2. Ghi atomic:**
  1. Ghi ra file tạm.
  2. Flush, và sync nếu nền tảng hỗ trợ.
  3. Đổi tên đè lên file chính.
  - Bản trước đó được giữ lại thành `.bak`.
- **GS-12.3. Nội dung file tiến độ (mỗi level một file):**
  - Định danh: `save_version`, `level_id`, `level_schema_version`.
  - Dấu vân tay: `layout_hash`, `content_hash`.
  - Tiến độ: `placed` (bitset mã hoá base64), `selected`, `completed`, `completion_reported`, `colors_ever_completed`, `updated_at`.
  - **Không lưu:** `last_placed`, `find_visited`, `camera`, `wrong_streak`.
- **GS-12.4. Mục tiêu mất dữ liệu** (mục tiêu thiết kế và kiểm thử, **không phải bảo đảm tuyệt đối**):
  - Tiến trình bị dừng ≥ 200 ms sau thao tác cuối: không mất thao tác nào.
  - Bị dừng ngay sau thao tác: mất tối đa 1 thao tác.
  - Mục tiêu này không áp dụng cho: mất nguồn hoặc thiết bị treo giữa lúc ghi xuống bộ nhớ, lỗi phần cứng lưu trữ, hệ điều hành hoãn ghi. Các trường hợp này được giảm thiểu bằng ghi atomic, `.bak` và luồng khôi phục ở mục 13.
- **GS-12.5.** Việc ghi file không được làm rơi khung hình: ghi ngoài luồng vẽ, hoặc mỗi lần ghi < 2 ms.
- **GS-12.6.** Hỏng file tiến độ không ảnh hưởng tới cài đặt, và ngược lại.

---

## 13. Dấu vân tay, khôi phục, migration

- **GS-13.1. Chuỗi chuẩn hoá để băm.** Băm bằng SHA-256 trên chuỗi UTF-8, kết quả là hex chữ thường.
  - `layout_hash` băm chuỗi: `pbart-layout-1|w=<w>|h=<h>|n=<số màu>|cells=<c0>,<c1>,…`
  - `content_hash` băm chuỗi: `pbart-content-1|schema=<schema_version>|w=<w>|h=<h>|palette=<id>:<hex>,…|cells=<c0>,…`
  - Quy tắc viết:
    - Số nguyên viết thập phân ASCII, không có số 0 đứng đầu, số âm có dấu `-`.
    - `hex` viết `#` kèm 6 ký tự chữ thường; palette xếp theo ID tăng dần.
    - Không có dấu cách, không có ký tự xuống dòng.
  - **Không đưa vào hash:** `count` (suy ra được từ `cells`), `name`, `mask`, `title`, `id`, `difficulty`, `modes`.
  - Tiền tố `pbart-…-1` là phiên bản của **cách băm**, tách biệt với phiên bản schema.
- **GS-13.2. Giá trị tham chiếu.** Tính bằng Python; Godot phải ra kết quả giống hệt.
  - **F1:**
    - `cells = [0,1,2,-1,0,1]`, palette `#2f86b8,#e2553d,#f3dcd2`, schema 1.
    - `layout_hash = b09305c9fea477ff6a5ba10b4f13a255ab9892d484f27d7b40d1bf9f3910f8aa`
    - `content_hash = dc70ea18d4a5edfd1dcf79ac21a466ca6b417ddc8b6b97ebcdd453542e0c7a14`
  - **F9** (F1 với màu 1 đổi thành `#c9362f`):
    - `layout_hash` giống F1.
    - `content_hash = 5206fe955572afbe7e8fed4d516fc98aa36c5bce1df98c6eaf4a29c8ea9a38ca`
  - **F10** (F1 với `cells[5] = 0`, `count` đổi thành `[3,1,1]`):
    - `layout_hash = 910660ec8fccc6ff44459b418df8e86c241d31aee0e8f36db33b5195cd9cc4c8`
    - `content_hash = 24c69fac36cfbf754ad12182b949bfca8c00c3568386c0f231aee71c25db0581`
- **GS-13.3. Thứ tự quyết định khi khôi phục:** dừng ngay ở bước đầu tiên khớp.
  1. **Không đọc được file:**
     - Thử đọc `.bak`.
     - Nếu `.bak` cũng hỏng: đổi tên cả hai file thành `.corrupt`, bắt đầu lại từ đầu, ghi log `corrupt_fresh`.
  2. **`level_id` không khớp:** coi như file hỏng (bước 1).
  3. **`save_version` khác phiên bản hiện tại:**
     - Có migration định dạng save đã đăng ký thì chạy migration rồi đi tiếp.
     - Nếu không: sao lưu file thành `.stale` và bắt đầu lại (`backup_no_migration`).
  4. **`level_schema_version` khác schema của level hiện tại:**
     - Có migration schema đã đăng ký thì chạy migration rồi đi tiếp.
     - Nếu không: sao lưu thành `.stale`, **không tự khôi phục**, bắt đầu lại (`backup_no_migration`).
  5. **`layout_hash` lệch** (bố cục, số màu hoặc ý nghĩa ID trong `cells` đã đổi):
     - Sao lưu thành `.stale`, bắt đầu lại (`backup_layout_changed`).
     - MVP không có migration cho bố cục.
  6. **`layout_hash` khớp nhưng `content_hash` lệch** (chỉ đổi `hex`, cùng schema):
     - Giữ tiến độ, thông báo "Màu của tranh vừa được cập nhật" (`restored_hex_changed`).
  7. **Cả hai hash đều khớp:** khôi phục bình thường (`restored`).
- **GS-13.4. Migration:**
  - Có hai danh sách đăng ký riêng: migration định dạng save (theo `save_version`) và migration schema level (theo `level_schema_version`).
  - Mỗi migration là một hàm thuần, nhận từ phiên bản A sang B, và **phải có unit test bằng file mẫu** trước khi được đăng ký. Cho phép nối nhiều migration thành chuỗi.
  - Sau khi migration xong: tính lại hai hash, kiểm tra lại bất biến GS-3.1, rồi đi tiếp từ bước 5. Bất kỳ bước kiểm tra nào thất bại thì xử lý như không có migration.
  - **Bản phát hành MVP chưa đăng ký migration nào.** Riêng phần test có một migration mẫu để kiểm tra cơ chế.
- **GS-13.5. Lưu giữ file sao lưu:**
  - `.stale` và `.corrupt` không bao giờ bị xoá tự động trong MVP.
  - Người chơi nhận một thông báo ngắn: "Tranh đã được cập nhật, bắt đầu lại".
- **GS-13.6. Sau khi khôi phục:**
  - Tính lại `remaining` từ `placed`.
  - Nếu bitset sai độ dài, hoặc đánh dấu ô `-1`: coi như file hỏng (bước 1).
  - Nếu `colors_ever_completed` thiếu một màu đang ở trạng thái xong: bổ sung **mà không phát sự kiện**.
  - `last_placed = none`.
- **GS-13.7.** Ở bước 6, giữ nguyên `colors_ever_completed`, `completed` và `completion_reported`.

---

## 14. Sự kiện phân tích

- **GS-14.1. Tách khỏi âm thanh:**
  - Sự kiện phân tích là luồng riêng, chỉ ghi cục bộ (offline).
  - Bật/tắt âm thanh hay haptic **không** ảnh hưởng tới sự kiện.
  - Âm thanh không được dùng làm điều kiện để phát sự kiện, và ngược lại.
- **GS-14.2. Danh sách sự kiện:** mỗi sự kiện có `event_id` (UUID) và `ts`.

| Sự kiện | Các trường |
|---|---|
| `level_start` | `level_id`, `mode`, `restore_result` |
| `bead_placed` | `cell`, `color`, `ms_since_prev` |
| `wrong_tap` | `cell`, `cell_color`, `selected` |
| `tap_to_zoom` | `cell_size_pt` |
| `find_used` | `color`, `target_cell`, `was_offscreen` |
| `undo_used` | `cell`, `color`, `ms_since_place` |
| `color_complete` | `color`, `occurrence: first \| repeat` |
| `level_complete` | `level_id`, `mode` |
| `restore_result` | `result` ∈ {`fresh`, `restored`, `restored_hex_changed`, `migrated`, `backup_no_migration`, `backup_layout_changed`, `corrupt_recovered_bak`, `corrupt_fresh`} |
| `setting_changed` | `key`, `value` |
| `session_end` | `duration`, `placed`, `wrong`, `undo`, `find`, `tap_to_zoom` |

- **GS-14.3. Chống trùng:**
  - `level_complete` chỉ phát khi `completed` chuyển từ false sang true. `completion_reported` được lưu trong cùng lần ghi atomic với `completed` (GS-4.5). Khôi phục một level đã xong thì không phát lại.
  - `color_complete.occurrence = first` khi màu chưa có trong `colors_ever_completed`; ngược lại là `repeat`.
  - Bộ ghi sự kiện bỏ qua mọi sự kiện có `event_id` đã ghi trước đó.

---

## 15. Zen và Journey

- **GS-15.1. Khác biệt duy nhất:** hai chế độ dùng chung mục 2–14. Chỉ khác ở ba điểm:
  - Journey mở khoá tranh theo thứ tự; Zen chọn tranh tự do.
  - Chỉ Zen có tuỳ chọn tắt phản hồi chạm sai.
  - Giới hạn trợ giúp (nếu sau này có).
- **GS-15.2. Chung tiến độ (D-6):** mỗi level chỉ có một file tiến độ. Việc mở khoá trong Journey suy ra từ `completed`, nên tranh hoàn thành ở Zen cũng mở khoá tranh kế tiếp trong Journey.
- **GS-15.3.** Đổi chế độ khi đang chơi dở thì giữ tiến độ. Đổi chế độ nghĩa là rời màn, nên `last_placed` bị xoá (GS-10.6).

---

## 16. Phi chức năng

- **GS-16.1. Khung hình:** trên tranh 1024 ô, khi pan, zoom và chạm 5 lần/giây **kèm ghi file**, khung hình p95 ≤ 16,7 ms.
- **GS-16.2. Độ trễ:** từ lúc nhấc ngón tay tới khi hạt bắt đầu hiện ≤ 50 ms.
- **GS-16.3. Trợ năng:**
  - Có số trên ô.
  - Tôn trọng Reduce Motion.
  - Khay và nút ≥ 44pt; trạng thái nút đọc được bằng VoiceOver.
  - Không truyền thông tin chỉ bằng màu hoặc hoạt ảnh.
- **GS-16.4. Dữ liệu kiểm thử (D-7):** level nội bộ phải qua `validate_level.py --strict` trước khi dùng cho test, và không được đóng gói vào bản phát hành.

---

## 17. Giả thuyết

| Mã | Cờ / tham số | Giả thuyết | Tiêu chí (đề xuất) |
|---|---|---|---|
| H1 | `snap_to_nearest` | Hít về ô hợp lệ trong bán kính ½ ô giảm chạm sai mà không gây đặt nhầm | `wrong_tap` giảm ≥ 50%; Undo trong vòng 2 giây sau khi đặt < 1% |
| H2 | `auto_switch_color` | Tự chuyển màu giúp nhịp chơi trơn hơn | Thời gian chuyển màu giảm ≥ 40%; ≤ 20% người chơi phàn nàn |
| H3 | — | Easy 300 ô không gây mỏi | ≥ 80% hoàn thành; điểm mỏi ≤ 2/5 |
| H4 | — | Relax 1024 ô cần cơ chế tô nhanh | Bỏ dở > 30% hoặc mỏi ≥ 3 thì bàn lại |
| H5 | — | Phản hồi chạm sai dễ hiểu | Trung bình ≤ 2 lần sai liên tiếp trước khi chọn đúng màu |
| H6 | — | Nút Tìm xử lý tốt các ô cuối | Thời gian 5% ô cuối ≤ 15% tổng thời gian |
| H7 | `MIN_PLACE_CELL`, `PLACE_ZOOM_CELL` | Cặp 24/32pt cân bằng giữa độ chính xác và số lần phải zoom | Undo trong vòng 2 giây sau đặt < 1%; ≤ 1 lần `tap_to_zoom` mỗi phút sau phút đầu |
| H8 | `TAP_SLOP`, `MULTI_TOUCH_COOLDOWN_MS` | Mặc định không gây đặt nhầm khi pan/pinch | 0 lần đặt nhầm trong 2 phút; < 2% tap hợp lệ bị bỏ qua |

---

# Test case v0.3

**Cấp test:**
- **U:** logic chạy headless trên Godot.
- **I:** tích hợp, mô phỏng chạm.
- **D:** trên iPhone thật.
- **P:** với người chơi.

**Bộ dữ liệu test (fixture):**
- **F1:** lưới 3×2, `cells = [0,1,2,-1,0,1]`, `count = [2,2,1]`, palette như GS-13.2.
- **F2:** `squid_easy_01`; **F3:** `squid_relax_01`. Cả hai chỉ dùng sau khi qua kiểm tra `--strict` (TC-2.11).
- **F4:** bộ level sai định dạng: thiếu trường, `cells` 2D, `hex` sai, `id ≠` vị trí.
- **F5:** F1 nhưng `count[0] = 3`.
- **F6:** F1 thêm màu 3 có `count = 0`.
- **F7:** `cells` toàn `-1`.
- **F8:** `width × height ≠ len(cells)`.
- **F9:** F1 với màu 1 đổi thành `#c9362f`.
- **F10:** F1 với `cells[5] = 0`, `count = [3,1,1]`.
- **F11:** hai màu có `remaining` bằng nhau, màu ID lớn hơn đứng trước trong file.
- **F12:** F1 nhưng `schema_version = 2` (chỉ dùng trong test).
- **F14:** F1 nhưng hai màu trùng `hex`.

### 2. Dữ liệu level

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-2.1 | U | Nạp F1 | `remaining = [2,2,1]` do tự đếm, khớp `count`; bất biến đúng | GS-2.1, 2.3, 3.1 |
| TC-2.2 | U | Nạp từng file F4 | Từ chối kèm đúng mã lỗi; không vào màn; không crash | GS-2.1, 2.4, 2.6 |
| TC-2.3 | U | Giá trị `1.0` và `1.5` | `1.0` được chấp nhận; `1.5` bị từ chối | GS-2.2 |
| TC-2.4 | U | F5 | Từ chối `count_mismatch`; không tự sửa | GS-2.3 |
| TC-2.5 | U | F6 | Từ chối `unused_color` | GS-2.4 |
| TC-2.6 | U | `cells` chứa 9, và chứa −2 | Từ chối `unknown_color` | GS-2.4 |
| TC-2.7 | U | F14 | Từ chối `duplicate_color` | GS-2.4 |
| TC-2.8 | U | F7 | Từ chối `no_playable_cells` | GS-2.5 |
| TC-2.9 | U | F8, và `width = 0`/`129` | Từ chối `grid_size` | GS-2.5 |
| TC-2.10 | U | Chạy Python và Godot trên F1–F8, F14 | Cùng kết quả chấp nhận/từ chối, cùng mã lỗi | GS-2.6 |
| TC-2.11 | U | `validate_level.py --strict` trên F2 và F3 | 0 lỗi, 0 cảnh báo; nếu không đạt thì F2/F3 không được dùng | GS-16.4 |

### 4. Luồng màn chơi

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-4.1 | U | Vào F2, chưa có tiến độ | Màu được chọn có `remaining` lớn nhất; camera ở toàn cảnh; Undo bị vô hiệu | GS-4.1, 4.2, 10.2 |
| TC-4.2 | U | Vào F11 | Chọn màu có ID nhỏ hơn, bất kể thứ tự trong file | GS-4.2 |
| TC-4.3 | U | `selected` đã lưu là màu đã xong | Chọn lại theo GS-4.2 | GS-4.2 |
| TC-4.4 | I | Đổi màu khi camera đang zoom | Camera giữ nguyên; Undo vẫn dùng được | GS-4.3, 10.5 |
| TC-4.5 | U | Hoàn thành một màu | Swatch chuyển trạng thái xong; `selected` giữ nguyên; hiện dòng nhắc; không tự chuyển màu | GS-4.4 |
| TC-4.6 | U | Hoàn thành F1 | Khoá đặt hạt, Undo, Tìm; `completed` và `completion_reported` cùng được ghi | GS-4.5 |
| TC-4.7 | U | Mở lại level đã xong | Chỉ hiện tranh hoàn thành; không phát `level_complete`; không đặt hạt được | GS-4.6, 14.3 |

### 5. Cử chỉ và zoom

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-5.1 | I | Một ngón, di chuyển 6pt, giữ 200 ms | Là tap | GS-5.1 |
| TC-5.2 | I | Kéo 15pt | Là pan; không đặt hạt | GS-5.1 |
| TC-5.3 | I | Giữ 700 ms | Không đặt hạt | GS-5.1 |
| TC-5.4 | I | Pinch → nhấc ngón 1 → ngón 2 đứng yên 300 ms trên ô hợp lệ rồi nhấc | Không đặt hạt | GS-5.2 |
| TC-5.5 | I | Tap sau khi phiên nhiều ngón kết thúc 60 ms, và sau 200 ms | 60 ms: không đặt; 200 ms: đặt được | GS-5.1(e) |
| TC-5.6 | I | Chạm khi tranh đang trôi theo quán tính | Camera dừng; không đặt hạt | GS-5.3 |
| TC-5.7 | I | Chạm khi hoạt ảnh của Tìm hoặc chạm-để-zoom đang chạy | Camera dừng; không đặt hạt | GS-5.3, 5.11 |
| TC-5.8 | I | Chạm xuống ở ô A, nhấc lên ở ô B (≤ 10pt) | Áp dụng cho ô A | GS-5.4 |
| TC-5.9 | U | Điểm nằm đúng biên (3,0; 2,0), lặp 1000 lần | Luôn ra ô (3,2) | GS-5.4 |
| TC-5.10 | I | Chạm lệch 2pt sang ô kề khác màu | Xử lý như chạm sai vào ô kề đó; không đặt hạt | GS-5.5, 6.2 |
| TC-5.11 | I | Phiên bắt đầu trên tranh, kết thúc trên khay | Không tạo tap; không đổi màu | GS-5.6 |
| TC-5.12 | I | Chạm ba ngón | Bỏ qua | GS-5.7 |
| TC-5.13 | D | Chạm vào ô cách mép ≤ 8pt, và ô gần thanh home | Ghi lại tỷ lệ bị hệ thống chiếm; quyết định có bật `EDGE_GUARD` | GS-5.8 |
| TC-5.14 | I | Chạm góc ô, ngoài hình tròn của hạt | Đặt vào đúng ô đó | GS-5.4 |
| TC-5.15 | I | Chạm đúp vào ô hợp lệ | Lần 1 đặt hạt; lần 2 im lặng; camera không zoom | GS-5.9, 6.3 |
| TC-5.16 | D | Pan và zoom tự do 2 phút trên F3 | 0 hạt bị đặt ngoài ý muốn | GS-5.1–5.3, H8 |
| TC-5.17 | I | F3 ở zoom toàn cảnh, chạm ô hợp lệ | Không đặt, không phản hồi sai, không âm thanh; zoom tới 32pt quanh điểm chạm; gợi ý hiện 1 lần; `last_placed` không đổi | GS-5.10, 10.5 |
| TC-5.18 | I | Lặp lại TC-5.17 trong cùng phiên | Không hiện lại gợi ý | GS-5.10 |
| TC-5.19 | I | Ở toàn cảnh, chạm ô **khác** màu | Chỉ zoom; không phản hồi sai; `wrong_streak` không đổi | GS-5.10 |
| TC-5.20 | I | Sau khi hoạt ảnh chạm-để-zoom kết thúc | Không có hạt nào tự được đặt; cần một tap mới mới đặt | GS-5.11 |
| TC-5.21 | I | F1 ở toàn cảnh (ô ≥ 24pt) | Tap đặt hạt ngay, không zoom | GS-5.10 |
| TC-5.22 | I | Ở toàn cảnh: kiểm tra làm nổi và hiện số | Ô hợp lệ vẫn nổi; số chỉ hiện khi ô ≥ 18pt | GS-5.12, 7.2 |
| TC-5.23 | U | Cấu hình vi phạm ràng buộc tham số (ví dụ `MIN_PLACE > PLACE_ZOOM`) | Bản debug báo lỗi ngay khi khởi động | Mục 0.2 |

### 6. Kết quả tap

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-6.1 | U | F1, chọn màu 0, chạm (0,0) | `placed`; `remaining[0] = 1`; `last_placed = 0`; đúng 1 haptic; 1 tiếng đặt hạt; 1 lần ghi | GS-6.1, 11.4, 12.1 |
| TC-6.2 | U | Chạm ô khác màu | Không đổi trạng thái; có phản hồi sai; `last_placed` giữ nguyên; không haptic | GS-6.2, 6.6, 10.5 |
| TC-6.3 | U | Chạm ô đã có hạt, rồi Undo | Không âm thanh, không haptic, không đổi trạng thái; Undo vẫn hoàn tác đúng hạt trước đó | GS-6.3, 10.5 |
| TC-6.4 | U | Chạm `-1`; chạm ngoài lưới | Im lặng; không đổi | GS-6.4 |
| TC-6.5 | U | `selected = none` / màu đã xong, rồi chạm | Dòng nhắc; không đổi | GS-6.5 |
| TC-6.6 | U | Sai 3 lần → gợi ý; rồi lần lượt: đặt đúng, Undo, đổi màu | Mỗi thao tác đưa `wrong_streak` về 0 | GS-6.7, 10.8 |
| TC-6.7 | I | Zen: tắt phản hồi sai rồi chạm sai; Journey: tìm tuỳ chọn này | Zen: im lặng nhưng vẫn ghi `wrong_tap`. Journey: không có tuỳ chọn | GS-6.8, 15.1 |
| TC-6.8 | U | Hoàn thành F1 | 5 `bead_placed`; 3 `color_complete{first}`; 1 `level_complete` | GS-4.5, 14.2 |
| TC-6.9 | U | Phát lại toàn bộ F3 | Bất biến đúng sau mỗi bước | GS-3.1 |
| TC-6.10 | U | 10.000 thao tác ngẫu nhiên (tap, Undo, đổi màu, Tìm, zoom), seed cố định, trên F2 | Không bao giờ đặt sai màu; bất biến luôn đúng; `last_placed` chỉ đổi khi đặt thành công hoặc Undo | GS-3.1, 6.1, 10.3, 10.5 |

### 7. Hiển thị

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-7.1 | U | Chọn màu c | Tập ô được làm nổi bằng đúng tập ô hợp lệ của c | GS-7.1 |
| TC-7.2 | I | Quay video 3 giây khi đang làm nổi | Không có điểm ảnh nào thay đổi theo chu kỳ | GS-7.1 |
| TC-7.3 | I | Ô cỡ 17 / 18 / 40pt | Số ẩn ở 17pt; hiện ở 18 và 40pt | GS-7.2 |
| TC-7.4 | I | Mỗi màu của F2: đo vùng thân theo GS-7.3 | ΔE00 trung vị ≤ 2,0 | GS-7.3 |
| TC-7.5 | I | Kiểm tra ràng buộc shader: vị trí highlight và bóng; đo đối chứng cả hạt (không dùng làm tiêu chí) | Highlight chỉ ở góc trên-trái; bóng chỉ ở r > 0,65 | GS-7.4 |

### 8. Khay và hàng hành động

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-8.1 | I | Đặt hạt, rồi Undo | Số trên swatch −1 rồi +1, ngay trong khung hình kế tiếp | GS-8.2 |
| TC-8.2 | D | iPhone SE và Pro Max | Swatch và nút ≥ 44pt; không che tranh; đúng safe area | GS-8.1, 8.3, 8.4 |
| TC-8.3 | I | Kiểm tra Undo và Tìm ở trạng thái vô hiệu | Nhìn thấy rõ và VoiceOver đọc đúng | GS-8.4, 9.4, 10.2, 16.3 |

### 9. Nút Tìm

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-9.1 | U | Còn 3 ô ngoài khung nhìn; bấm Tìm 4 lần | 3 ô khác nhau, gần nhất trước; lần thứ 4 xoá tập đã thăm rồi chọn lại | GS-9.1, 9.3 |
| TC-9.2 | U | Mọi ô hợp lệ đều trong khung nhìn | Chọn ô chưa thăm gần tâm nhất | GS-9.1 |
| TC-9.3 | U | Hai ô cách đều tâm | Chọn ô có chỉ số nhỏ hơn | GS-9.1 |
| TC-9.4 | I | Tìm từ zoom toàn cảnh, rồi chạm ngay vào ô đích | Mức zoom ≥ 32pt; đặt hạt được | GS-9.2 |
| TC-9.5 | I | Tìm khi màu đã xong / `none` / tranh đã xong | Nút bị vô hiệu | GS-9.4 |
| TC-9.6 | I | Chạm khi hoạt ảnh Tìm đang chạy | Hoạt ảnh dừng; không đặt hạt | GS-9.2, 5.3 |
| TC-9.7 | I | Bật Reduce Motion | Nhảy thẳng tới ô; vòng sáng mờ dần một lần | GS-9.2 |
| TC-9.8 | U | Tìm tới X → đặt X → Undo → Tìm | X có thể được chọn lại | GS-9.5 |
| TC-9.9 | U | Bấm Tìm nhiều lần | Không đặt hạt; `selected` và `last_placed` không đổi | GS-9.6, 10.5 |
| TC-9.10 | U | Đổi màu rồi Tìm; sau đó khởi động lại | Tập đã thăm tách theo từng màu; mất sau khi khởi động lại | GS-9.3 |

### 10. Undo

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-10.1 | U | Đặt hạt rồi Undo | Trạng thái về như trước khi đặt; nút Undo bị vô hiệu | GS-10.2, 10.3 |
| TC-10.2 | U | Undo hai lần liên tiếp | Lần thứ hai không làm gì | GS-10.1, 10.3 |
| TC-10.3 | U | Đặt hạt cuối của một màu → Undo → đặt lại | Màu trở lại chưa xong rồi xong lại; lần đầu `occurrence = first`, lần sau `repeat`; tiếng chuông phát cả hai lần | GS-10.3, 11.1, 14.3 |
| TC-10.4 | U | Đặt → chạm sai → chạm ô đã có hạt → đổi màu → Tìm → pan/pinch → Toàn cảnh → mở Cài đặt → Undo | Hoàn tác đúng hạt ban đầu | GS-10.5 |
| TC-10.5 | U | Hoàn thành tranh rồi bấm Undo | Không làm gì | GS-10.2, 10.6, 4.5 |
| TC-10.6 | I | Rời màn rồi quay lại (tiến trình vẫn sống) | Undo bị vô hiệu | GS-10.6, 3.2 |
| TC-10.7 | D | Đưa app xuống nền rồi mở lại (tiến trình vẫn sống) | Undo vẫn dùng được | GS-10.6, 3.2 |
| TC-10.8 | D | Tắt hẳn app rồi mở lại | Undo bị vô hiệu cho tới lần đặt hạt mới | GS-10.6 |
| TC-10.9 | I | Undo khi ô nằm ngoài khung nhìn | Hiện dòng nhắc; camera không đổi | GS-10.4 |
| TC-10.10 | I | Phản hồi của Undo | Tiếng nhấc hạt; không haptic; Reduce Motion bật thì chỉ mờ dần | GS-10.7, 11.4, 11.5 |
| TC-10.11 | U | Sai 2 lần → Undo → sai 2 lần | Gợi ý **không** xuất hiện (bộ đếm đã về 0) | GS-10.8, 6.7 |

### 11. Âm thanh, haptic, hoạt ảnh

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-11.1 | U | 100 lần đặt hạt | Không lặp mẫu liền kề; cao độ trong ±3% | GS-11.1 |
| TC-11.2 | I | Chạm 10 lần/giây trong 10 giây | Không quá 4 âm phát cùng lúc | GS-11.2 |
| TC-11.3 | D | So tiếng chạm sai với tiếng đặt hạt | Nhỏ hơn khoảng 6 dB; không haptic | GS-6.6, 11.4 |
| TC-11.4 | D | Bật/tắt từng mục cài đặt | Mỗi mục độc lập; còn sau khi khởi động lại | GS-11.3, 11.4, 11.6 |
| TC-11.5 | D | Thiết bị không hỗ trợ haptic | Không lỗi | GS-11.4 |
| TC-11.6 | I | Reduce Motion bật rồi đặt hạt | Chỉ mờ dần | GS-11.5 |
| TC-11.7 | I | Chạm tiếp trong lúc hoạt ảnh đặt hạt đang chạy | Lần chạm mới được xử lý ngay | GS-11.5 |
| TC-11.8 | U | Chạy cùng một chuỗi thao tác khi âm thanh và haptic tắt, rồi khi bật | Danh sách sự kiện phân tích giống hệt nhau | GS-14.1 |
| TC-11.9 | U | Chuỗi hỗn hợp: đặt, sai, chạm ô đã có hạt, Undo, chạm-để-zoom | Số lần haptic bằng đúng số lần đặt hạt thành công | GS-11.4 |

### 12. Lưu tiến độ

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-12.1 | D | Đặt 37 hạt; tắt hẳn app ≥ 200 ms sau hạt cuối | Mở lại thấy đủ 37 hạt | GS-12.1, 12.4 |
| TC-12.2 | D | Tắt hẳn app **ngay** sau hạt thứ 37, lặp 20 lần | ≥ 36 hạt ở mọi lần (mục tiêu kiểm thử) | GS-12.4 |
| TC-12.3 | D | Đặt hạt rồi đưa app xuống nền ngay | Mở lại thấy đủ hạt | GS-12.1 |
| TC-12.4 | U | Mô phỏng: không callback tắt app nào được gọi | Kết quả như TC-12.1 | GS-12.1 |
| TC-12.5 | D | Đặt hạt → Undo → tắt hẳn app ≥ 200 ms sau | Hạt vừa hoàn tác không có; `remaining` đúng; Undo bị vô hiệu | GS-12.1, 10.6, 13.6 |
| TC-12.6 | U | Đặt → ghi → Undo → ghi → đọc lại file | Nội dung khớp trạng thái sau Undo, đủ các trường của GS-12.3 | GS-12.1, 12.3 |
| TC-12.7 | U | Ngắt giữa lúc đang ghi file tạm | File chính còn nguyên bản cũ hợp lệ | GS-12.2 |
| TC-12.8 | U | 20 lần đặt trong lúc một lần ghi đang chạy | Tối đa 1 lần ghi chờ; file cuối cùng có đủ 20 hạt | GS-12.1 |
| TC-12.9 | U | Làm hỏng file cài đặt, rồi làm hỏng file tiến độ | Mỗi file hỏng không ảnh hưởng tới file kia | GS-12.6 |

### 13. Dấu vân tay, khôi phục, migration

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-13.1 | U | Tính hash cho F1, F9, F10 bằng Python và Godot | Khớp đúng giá trị tham chiếu ở GS-13.2 | GS-13.1, 13.2 |
| TC-13.2 | U | Tính hash cho F2, F3 bằng Python và Godot | Hai bên giống hệt nhau | GS-13.2 |
| TC-13.3 | U | Đảo thứ tự khoá JSON; viết `hex` chữ hoa | Hash không đổi | GS-13.1 |
| TC-13.4 | U | Hash khớp hoàn toàn | `restored` | GS-13.3 bước 7 |
| TC-13.5 | U | Tiến độ cũ của F1, mở với F9 | Giữ `placed`; có thông báo; `restored_hex_changed` | GS-13.3 bước 6, 13.7 |
| TC-13.6 | U | Tiến độ cũ của F1, mở với F10 | Sao lưu `.stale`; bắt đầu lại; `backup_layout_changed` | GS-13.3 bước 5 |
| TC-13.7 | U | F12 có migration mẫu (chỉ trong test) v1→v2 | Migration chạy rồi khôi phục; bất biến đúng; `migrated` | GS-13.3 bước 4, 13.4 |
| TC-13.8 | U | F12 không có migration nào | Sao lưu `.stale`; **không** khôi phục; `backup_no_migration` | GS-13.3 bước 4, 13.5 |
| TC-13.9 | U | Có migration nhưng kết quả sai bất biến | Xử lý như không có migration | GS-13.4 |
| TC-13.10 | U | `save_version` cũ, có và không có migration | Hai kết quả tương ứng với TC-13.7 và TC-13.8 | GS-13.3 bước 3, 13.4 |
| TC-13.11 | U | File chính hỏng, `.bak` tốt | Khôi phục từ `.bak`; `corrupt_recovered_bak` | GS-13.3 bước 1 |
| TC-13.12 | U | Cả hai file đều hỏng | Đổi tên thành `.corrupt`; bắt đầu lại; không crash; cài đặt vẫn còn | GS-13.3 bước 1, 12.6 |
| TC-13.13 | U | Bitset sai độ dài, hoặc đánh dấu ô `-1`; và `level_id` sai | Coi như file hỏng | GS-13.3 bước 1–2, 13.6 |
| TC-13.14 | U | Sau khi khôi phục | `remaining` bằng giá trị tính lại; `last_placed = none` | GS-13.6 |
| TC-13.15 | U | Khởi động và lưu nhiều lần sau khi đã có `.stale` / `.corrupt` | Các file này không bị xoá | GS-13.5 |
| TC-13.16 | U | `colors_ever_completed` thiếu một màu đang ở trạng thái xong | Được bổ sung; không phát sự kiện | GS-13.6 |

### 14. Sự kiện phân tích

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-14.1 | U | Một phiên chơi F1 có đủ các loại thao tác | Đúng số lượng từng loại sự kiện; đủ trường | GS-14.2 |
| TC-14.2 | U | Hoàn thành tranh; tắt app trước hoặc sau khi ghi; mở lại | `level_complete` không bao giờ bị phát lần thứ hai | GS-14.3, 4.5 |
| TC-14.3 | U | Màu xong ở phiên 1; phiên 2 đặt hạt rồi Undo hạt cuối của màu khác rồi đặt lại | Màu ở phiên 1: `first`; lần đặt lại ở phiên 2: `repeat` | GS-14.3 |
| TC-14.4 | U | Ghi hai lần cùng một `event_id` | Chỉ lưu một bản | GS-14.3 |
| TC-14.5 | U | Chạy từng nhánh khôi phục của GS-13.3 | Phát đúng giá trị `restore_result` tương ứng | GS-14.2 |

### 15–16. Chế độ chơi và phi chức năng

| ID | Cấp | Bước | Kết quả mong đợi | Quy tắc |
|---|---|---|---|---|
| TC-15.1 | U | Chạy cùng một chuỗi thao tác ở Zen và ở Journey | Trạng thái giống hệt nhau | GS-15.1 |
| TC-15.2 | I | Journey: thử mở tranh khi tranh trước chưa xong | Bị khoá; hoàn thành tranh trước thì mở được | GS-15.1 |
| TC-15.3 | U | Chơi dở ở Zen, mở ở Journey; hoàn thành ở Zen | Thấy cùng tiến độ; Journey mở khoá tranh kế tiếp | GS-15.2 |
| TC-15.4 | I | Đổi chế độ khi đang chơi dở | Giữ tiến độ; Undo bị vô hiệu | GS-15.3, 10.6 |
| TC-16.1 | D | F3: pan, zoom, chạm 5 lần/giây trong 60 giây, có ghi file | Khung hình p95 ≤ 16,7 ms | GS-16.1, 12.5 |
| TC-16.2 | D | Đo độ trễ bằng quay màn hình 240 fps | ≤ 50 ms | GS-16.2 |
| TC-16.3 | D | Chế độ mô phỏng mù màu và VoiceOver | Vẫn chơi được; nút được đọc đúng | GS-16.3 |

### 17. Kiểm thử với người chơi (bật/tắt cờ, 6–8 người mỗi vòng)

| ID | Giả thuyết |
|---|---|
| TC-17.1 | H1 |
| TC-17.2 | H2 |
| TC-17.3 | H3 |
| TC-17.4 | H4 |
| TC-17.5 | H5 |
| TC-17.6 | H6 |
| TC-17.7 | H7 (so `MIN_PLACE_CELL` 20/24/28pt) |
| TC-17.8 | H8 (phiên cử chỉ tự do 5 phút) |

### Ma trận đối chiếu quy tắc ↔ test

Mỗi quy tắc GS có ít nhất một test, và mỗi test trỏ vào một quy tắc có thật:

| Mục | Quy tắc → test |
|---|---|
| 2 | 2.1: TC-2.1, 2.2 · 2.2: TC-2.3 · 2.3: TC-2.1, 2.4 · 2.4: TC-2.2, 2.5–2.7 · 2.5: TC-2.8, 2.9 · 2.6: TC-2.2, 2.10 · 2.7: TC-2.1, 6.1 |
| 3 | 3.1: TC-2.1, 6.9, 6.10 · 3.2: TC-10.6, 10.7 |
| 4 | 4.1: TC-4.1 · 4.2: TC-4.1–4.3 · 4.3: TC-4.4 · 4.4: TC-4.5 · 4.5: TC-4.6, 6.8, 10.5 · 4.6: TC-4.7 |
| 5 | 5.1: TC-5.1–5.3, 5.5, 5.16 · 5.2: TC-5.4 · 5.3: TC-5.6, 5.7, 9.6 · 5.4: TC-5.8, 5.9, 5.14 · 5.5: TC-5.10 · 5.6: TC-5.11 · 5.7: TC-5.12 · 5.8: TC-5.13 · 5.9: TC-5.15 · 5.10: TC-5.17–5.19, 5.21 · 5.11: TC-5.7, 5.20, 9.9 · 5.12: TC-5.22 · 0.2: TC-5.23 |
| 6 | 6.1: TC-6.1 · 6.2: TC-6.2, 5.10 · 6.3: TC-6.3, 5.15 · 6.4: TC-6.4 · 6.5: TC-6.5 · 6.6: TC-6.2, 11.3 · 6.7: TC-6.6, 10.11 · 6.8: TC-6.7 |
| 7 | 7.1: TC-7.1, 7.2 · 7.2: TC-7.3, 5.22 · 7.3: TC-7.4 · 7.4: TC-7.5 |
| 8 | 8.1–8.3: TC-8.1, 8.2 · 8.4: TC-8.2, 8.3 |
| 9 | 9.1: TC-9.1–9.3 · 9.2: TC-9.4, 9.6, 9.7 · 9.3: TC-9.1, 9.10 · 9.4: TC-9.5, 8.3 · 9.5: TC-9.8 · 9.6: TC-9.9 |
| 10 | 10.1: TC-10.2 · 10.2: TC-10.1, 10.5, 4.1 · 10.3: TC-10.1–10.3 · 10.4: TC-10.9 · 10.5: TC-10.4, 6.2, 6.3, 5.17, 9.9, 4.4 · 10.6: TC-10.5–10.8, 15.4 · 10.7: TC-10.10, 12.6 · 10.8: TC-10.11 |
| 11 | 11.1: TC-11.1, 10.3 · 11.2: TC-11.2 · 11.3: TC-11.4 · 11.4: TC-6.1, 11.3, 11.5, 11.9 · 11.5: TC-11.6, 11.7, 10.10 · 11.6: TC-11.4 |
| 12 | 12.1: TC-12.1, 12.3–12.6, 12.8 · 12.2: TC-12.7 · 12.3: TC-12.6 · 12.4: TC-12.1, 12.2 · 12.5: TC-16.1 · 12.6: TC-12.9, 13.12 |
| 13 | 13.1: TC-13.1, 13.3 · 13.2: TC-13.1, 13.2 · 13.3: TC-13.4–13.8, 13.10–13.13 · 13.4: TC-13.7, 13.9, 13.10 · 13.5: TC-13.8, 13.15 · 13.6: TC-12.5, 13.13, 13.14, 13.16 · 13.7: TC-13.5 |
| 14 | 14.1: TC-11.8 · 14.2: TC-14.1, 14.5, 6.8 · 14.3: TC-14.2–14.4, 10.3, 4.7 |
| 15–16 | 15.1: TC-15.1, 15.2, 6.7 · 15.2: TC-15.3 · 15.3: TC-15.4 · 16.1: TC-16.1 · 16.2: TC-16.2 · 16.3: TC-16.3, 8.3 · 16.4: TC-2.11 |
| 17 | H1–H8: TC-17.1–17.8 |

---

# B. Thay đổi so với v0.2

**Đánh số lại:**
- Quy tắc: `GS-01…52` → `GS-<mục>.<số>`.
- Test: `TC-01…100` → `TC-<mục>.<số>`.
- Đối chiếu chính với v0.2:
  - GS-01–03 → 2.x; GS-04 → 3.1; GS-05–09 → 4.x; GS-10–14b → 5.x; GS-15–22 → 6.x
  - GS-23–25a → 7.x; GS-26–28 → 8.x; GS-29–29e → 9.x; GS-45–52 → 10.x
  - GS-31–37 → 11.x; GS-30–30c, 39 → 12.x; GS-38–38d → 13.x; GS-44 → 14.x
  - GS-40/41 → 15.x; GS-42/43 → 16.x

**Thay đổi nội dung:**

1. **Quyết định A1–A10:** ghi vào mục 0.1 (D-1 đến D-10). Đóng các câu hỏi Q-1, Q-2, Q-4 đến Q-10.
2. **Dữ liệu level (GS-2.4):** thêm luật từ chối `duplicate_color`, `bad_hex`, `palette_id`. Thêm yêu cầu Python và Godot phải cho cùng kết quả (GS-2.6, TC-2.10).
3. **Hash (GS-13.1):**
   - Đặt quy tắc viết chuẩn hoá đầy đủ, gồm tiền tố phiên bản của cách băm.
   - `layout_hash` có thêm `n` (số màu).
   - Ghi rõ những trường không đưa vào hash.
   - Thêm giá trị hash tham chiếu cho F1, F9, F10 (GS-13.2).
4. **Khôi phục:** thay ba nhánh của v0.2 bằng **7 bước có thứ tự** (GS-13.3).
   - Có xử lý cho `save_version`, cho `level_schema_version` và cho migration.
   - **Đổi schema mà không có migration thì không tự khôi phục** (sửa so với v0.2, vốn cho phép khôi phục khi "tương thích").
5. **Migration (GS-13.4):** thêm danh sách đăng ký, điều kiện phải có test trước khi đăng ký, và kiểm tra lại sau khi chạy. MVP chưa có migration nào.
6. **Undo:**
   - Định nghĩa "phiên chơi" (GS-3.2).
   - Liệt kê đầy đủ các thao tác không ghi đè trạng thái Undo (GS-10.5) và các thời điểm Undo bị xoá (GS-10.6).
   - Thêm trường `colors_ever_completed` để phân biệt sự kiện hoàn thành màu lần đầu với lần lặp lại.
7. **Âm thanh và sự kiện:**
   - Tách thành hai mục riêng (11 và 14); thêm bảng âm thanh theo từng tình huống.
   - Thêm `completion_reported` (ghi cùng `completed`) và `event_id` để không phát `level_complete` hai lần.
   - Mở lại level đã xong thì không phát sự kiện (GS-4.6). Ghi rõ MVP không có đặt lại tiến độ.
8. **Lưu (GS-12.4):** "mất tối đa 1 thao tác" chuyển thành **mục tiêu thiết kế và kiểm thử**, có liệt kê các ngoại lệ. Vẫn giữ: ghi sau mỗi lần đặt/Undo, ghi atomic, `.bak`, không phụ thuộc callback.
9. **Cử chỉ:**
   - Thêm "camera đang chuyển động" bao gồm cả hoạt ảnh do game tự chạy (GS-5.1d, 5.3).
   - Quy đổi toạ độ theo camera **tại lúc chạm xuống** (GS-5.4).
   - Thêm quy tắc không bao giờ tự đặt hạt khi zoom và không xếp hàng tap (GS-5.11).
   - Thêm ràng buộc thứ tự giữa các tham số và test cho nó (TC-5.23).
10. **Chạm-để-zoom (GS-5.10):** ghi rõ không âm thanh, không đổi `wrong_streak`, không đổi `last_placed` (TC-5.19).
11. **Haptic:** chỉ khi đặt thành công; có test đếm số lần haptic chính xác (TC-11.9).
12. **ΔE00 (GS-7.3/7.4):** đổi "bỏ cung 90° phía trên-trái" thành "bỏ **góc phần tư** trên-trái"; thêm ràng buộc vị trí của bóng (r > 0,65) để vùng đo không dính bóng.
13. **Nút Tìm:** định nghĩa chính xác thứ tự ba mức ưu tiên (GS-9.1); thêm GS-9.6 (Tìm không đặt hạt, không đổi Undo).
14. **Zen/Journey:** việc mở khoá suy ra từ `completed` dùng chung (GS-15.2). Thêm TC-15.3 và TC-15.4.
15. **Rà soát test:**
    - **Bỏ trùng:**
      - TC-12.9 cũ (hiệu năng khi ghi) gộp vào TC-16.1.
      - Mục 16.4 trỏ tới TC-2.11 thay vì tạo test mới.
      - Các TC v0.2 gộp nhóm kiểu "TC-23, 24, 25" được tách thành từng test riêng.
    - **Sửa mâu thuẫn:**
      - TC-96 cũ (giữ tiến độ khi chỉ đổi schema) đổi thành TC-13.8: **không** khôi phục nếu không có migration.
      - TC-47 cũ được tách thành TC-13.11 và TC-13.12.
    - **Bổ sung test còn thiếu:**
      - Ràng buộc tham số (TC-5.23).
      - Chạm-để-zoom vào ô khác màu (TC-5.19).
      - Đếm số lần haptic (TC-11.9).
      - Tách sự kiện khỏi âm thanh (TC-11.8).
      - Gộp lần ghi (TC-12.8).
      - Hỏng file cài đặt và file tiến độ không ảnh hưởng nhau (TC-12.9).
      - Các nhánh migration (TC-13.7, 13.9, 13.10).
      - Giữ file `.stale` (TC-13.15).
      - Chống trùng `event_id` (TC-14.4).
      - Mọi nhánh `restore_result` (TC-14.5).
      - Undo khi đưa app xuống nền và khi tắt hẳn (TC-10.7, 10.8).
    - Thêm **ma trận đối chiếu** quy tắc ↔ test.

---

# C. Quyết định đã chốt và thông số cần thử trên thiết bị

**Đã chốt:** D-1 đến D-10 (mục 0.1).

**Cần thử trên iPhone thật trước khi chốt:**
- **Cảm ứng:** `TAP_SLOP`, `TAP_MAX_MS`, `MULTI_TOUCH_COOLDOWN_MS`.
- **Zoom và cỡ ô:** `MIN_PLACE_CELL`, `PLACE_ZOOM_CELL`, `MAX_ZOOM_CELL`, `NUMBER_VISIBLE_CELL`.
- **Mép màn hình:** `EDGE_GUARD`.
- **Phản hồi:** `WRONG_TAP_HINT_AFTER`, `HAPTIC_MIN_INTERVAL_MS`, `SFX_VOICES_MAX`, `FIND_ANIM_MS`.
- **Âm lượng tương đối:** tiếng chạm sai so với tiếng đặt hạt (−6 dB).
- **Cờ giả thuyết:** `auto_switch_color` (H2), `snap_to_nearest` (H1).
- **Ngưỡng hiệu năng** GS-16.1 và GS-16.2 trên máy mục tiêu cụ thể (cần bạn chọn model iPhone).

---

# D. Rủi ro còn lại trước khi triển khai

1. **Thiết bị và môi trường:**
   - Container này không có macOS/Xcode, nên mọi test cấp **D** phụ thuộc vào máy Mac và iPhone của bạn.
   - Tôi chỉ chạy được test **U** (Godot headless) và một phần test **I**.
2. **Godot trên iOS (cần làm prototype xác minh sớm):**
   - Điều khiển haptic kiểu nhẹ (`UIImpactFeedbackGenerator`) có thể cần plugin native; `Input.vibrate_handheld` có thể không đủ tinh chỉnh.
   - Đọc cài đặt **Reduce Motion** của hệ thống có thể không có sẵn trong engine; nếu không đọc được, cần thêm một tuỳ chọn trong game làm phương án dự phòng.
   - Khả năng sync và rename atomic của `FileAccess` cần kiểm chứng trên iOS.
   - Xử lý đa chạm (`InputEventScreenTouch`/`Drag` với chỉ số ngón) khi có Control chồng lên nhau dễ phát sinh lỗi về phiên cử chỉ.
3. **Cảm giác chơi:**
   - Với mặc định 24pt, **cả hai level nội bộ đều bắt buộc zoom** trước lần đặt đầu tiên; có thể tạo cảm giác thêm một bước thừa (H7).
   - Khi tắt hít về ô gần nhất, chạm lệch ở ô 24–32pt có thể làm tỷ lệ chạm sai cao (H1).
4. **Hash giữa Python và Godot:** cách định dạng số và chữ hoa/thường của `hex` dễ lệch nhau. Đã giảm rủi ro bằng giá trị tham chiếu và TC-13.1/13.2, nhưng test phải được viết trước khi làm phần lưu.
5. **Migration:** cơ chế mới chỉ được kiểm tra bằng migration mẫu. Khi schema thật sự thay đổi, phải viết và test migration thật. Nếu không có, người chơi sẽ bắt đầu lại, dù tiến độ cũ vẫn được sao lưu.
6. **Ghi file sau mỗi hạt:** với khoảng 5 lần ghi mỗi giây, cần đo xem có tụt khung hình hoặc tốn pin không (TC-16.1). Nếu có, phải chuyển sang ghi ở luồng nền.
7. **Dữ liệu phân tích:** chỉ ghi cục bộ, chưa có cách xuất ra. Để đo H1–H8 khi chơi thử cần thêm một cách xuất log, ví dụ chia sẻ file.
8. **Nội dung:** mask và preview của hai level vẫn đang chờ duyệt, và Bước 2 vẫn chưa được commit. Nếu container hết hạn trước khi commit, các thay đổi đó sẽ mất.
9. **Phạm vi:** spec này chưa có màn chọn tranh, onboarding hay hoàn thiện iPad. Tài liệu MVP gốc có nhắc tới các phần này, nhưng chúng cần một đặc tả riêng.

---

**Xác nhận trạng thái:**
- Hash tham chiếu được tính trong bộ nhớ, không ghi ra file nào.
- Tôi không tạo, sửa hay xoá file nào trong repo; không commit, push, reset, stash hay checkout.
- HEAD vẫn là `8feed74` trên nhánh `claude/cloud-session-connection-check-hksw4v`.
- `git status`, hash của phần thay đổi chưa commit và hash của các file chưa theo dõi đều **trùng khớp** với mốc đã ghi; không có stash.

Tôi dừng ở đây để bạn duyệt v0.3.
