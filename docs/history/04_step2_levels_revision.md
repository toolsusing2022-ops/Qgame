<!-- Lưu trữ nguyên văn báo cáo từ phiên làm việc. -->

Cả hai level đã được chỉnh theo quyết định A, B, C. Relax có thêm lòng trắng mắt trái và giữ được đầu xúc tu. Easy có đủ hai mắt kèm lòng trắng và miệng. Tôi **chưa commit, chưa push** và đang dừng để chờ bạn duyệt.

Riêng thumbnail Easy 96×96 thì khuôn mặt vẫn chỉ là các chấm, nên tôi đề xuất đơn giản hoá ảnh nguồn ở cuối báo cáo.

## Thay đổi so với preview trước

**Relax `squid_relax_01`** (vẫn 32×32, 14 màu, palette giữ nguyên các mã màu):
- **Mắt trái:**
  - Mask nháp cũ thiếu mí mắt và lông mi (màu nâu tối, bị coi là không phải chủ thể). Tôi thêm một elip chỉnh tay cho vùng đó và nới elip chính thêm vài pixel.
  - Mask thêm 166 pixel, không bớt pixel nào, chỉ 0,6% số pixel thêm vào là màu xanh nước.
  - Ô (14,14) chuyển từ `body` sang `eye_white`. Giờ cả hai mắt đều có lòng trắng.
- **Đầu xúc tu:** mask vốn đã ôm trọn cả 5 đầu xúc tu, nên chúng bị cụt **do bước chuyển sang lưới chứ không phải do mask**. Với `--keep-tips 0.25`, 6 ô được chuyển thành chủ thể: (14,26), (14,27), (22,27), (22,28), (25,29), (26,21).
  - Không còn phần nhô nào ≥ 1/4 ô bị mất.
  - Vẫn còn một đầu xúc tu cong trên cùng bên trái hụt khoảng 0,19 ô, vì ô đó chỉ được mask phủ dưới 25%.
- **Chỉ số:** tổng cộng 7 ô đổi màu, ô chủ thể từ 310 lên 316. IoU 0,872 → 0,868, recall 0,927 → 0,934, precision 0,936 → 0,925. Không có vùng nền nào bị nhận nhầm vào chủ thể.

**Easy `squid_easy_01`** (vẫn 20×15, 8 màu, giữ `deep_red`):
- **Mắt phải** có thêm lòng trắng ở ô (12,7). Bản trước chỉ mắt trái có lòng trắng.
- **Hai con ngươi và miệng** vốn đã có ô riêng; giờ các ô này được khoá để chi tiết khác không ghi đè.
- **Có 4 ô đầu xúc tu được giữ** (15,12), (16,12), (16,13), (18,7). Không còn phần nhô nào bị mất.
- **Chỉ số:** tổng cộng 5 ô đổi màu, ô chủ thể từ 133 lên 137. IoU 0,833 → 0,832, recall 0,909 → 0,922, precision 0,909 → 0,895.

## Thay đổi trong pipeline (không tăng lưới, không gộp màu)

- **`--keep-tips MIN_COV`:** chỉ xét những phần nhô ra của mask mà lưới làm rơi. Ô nào chứa phần đó và có coverage ≥ ngưỡng thì được chuyển thành chủ thể.
  - Ở 0,25: giữ được đầu xúc tu, không thêm nền.
  - Ở 0,15: chuyển quá tay, có khoảng 0,32 ô nền bị nhận nhầm vào chủ thể. Vì vậy tôi không chọn mức này.
- **`preserve_min_area` trong palette:** mỗi vùng liền đủ lớn của một màu quan trọng được bảo đảm ít nhất 1 ô, đặt ở ô mà vùng đó phủ nhiều nhất. Ô đã đặt bị khoá; màu đứng trước trong file palette được ưu tiên. Cách này xử lý được trường hợp chi tiết nằm vắt qua giao điểm 4 ô, điều mà `min_share` không làm được.
  - Ngưỡng được chọn theo số liệu đo, ví dụ con ngươi 5657–8534 px còn đốm sáng phản quang chỉ ≤ 442 px.
- **`preserve_regions`:** hộp toạ độ do người thiết kế đánh dấu quanh mắt và miệng. Lý do cần thêm: chỉ dùng diện tích thì lòng trắng mắt ở Relax sẽ bị đặt nhầm lên mantle (vùng sáng ở đó rộng 991 px, lớn hơn cả hai vùng lòng trắng thật). Ở Easy, nó cũng ngăn việc ép thêm hạt `deep_red` vào các vùng bóng dưới xúc tu.
- **Sheet preview** giờ có thumbnail đúng 96×96 px (bản phẳng và bản hạt tròn) và bản phóng ×3 để soi.

## Thumbnail Easy 96×96: khuôn mặt vẫn chỉ là các chấm

- **Bản phẳng:** nhận ra ngay con bạch tuộc. Nhưng mỗi chi tiết khuôn mặt chỉ còn 1 hạt (khoảng 4,8 px), và miệng gần như hoà vào màu thân.
- **Bản hạt tròn ở 96 px bị vân lưới**, khó đọc hơn hẳn. Thumbnail ở màn chọn tranh nên dùng bản phẳng.
- **Đã thử crop sát mặt, vẫn giữ 20×15** (chỉ trong scratchpad, không thay level):
  - Mặt to hơn và IoU tăng lên 0,886.
  - Nhưng mắt phải thành hình dấu "+", xúc tu ngoài bị cắt mất, cả con bạch tuộc thành một mảng đỏ đầy khung.
  - Tôi **không đề xuất** crop này.

**Đề xuất tiếp theo (cần bạn quyết định trước khi đụng tới lưới):**
1. **Đơn giản hoá ảnh nguồn Easy:**
   - Mắt to khoảng 1,5–2 lần so với đầu, lòng trắng mắt rõ, miệng là một mảng tối đặc.
   - Viền ngoài dày và đều, bớt giác hút và đốm trên đầu, nền phẳng 1–2 sắc xanh.
   - Có thể làm bằng AI (Higgsfield sẽ tốn credit của bạn) hoặc bạn tự chuẩn bị, rồi bạn duyệt trước khi dùng.
2. **Màn chọn tranh dùng ảnh thu nhỏ của tranh gốc** thay vì lưới hạt. Cách này rẻ và bổ trợ được cho phương án 1.

## Mask

Cả hai mask vẫn là **bản nháp chờ bạn duyệt**.
- **Relax:** dùng 2 elip chỉnh tay quanh mắt trái, (611,552,40,58) và (630,512,24,18). Cả hai chỉ thêm pixel không phải nước.
- **Easy:** mask không đổi, tạo lại vẫn khớp từng pixel.

## Kết quả kiểm tra (đã chạy thật)

- **Unit test:** 68/68 pass, kể cả khi coi `ResourceWarning` là lỗi. Có 9 test mới cho `keep_tips`, cho việc bảo toàn chi tiết, cho `preserve_regions` và thứ tự ưu tiên, cùng 5 trường hợp lỗi mới khi đọc palette.
- **Gài lỗi có chủ đích:** 4/4 lỗi gài vào các luật mới đều bị test bắt.
- **Validator `--strict`:** 2/2 level mới hợp lệ, 0 lỗi, 0 cảnh báo, không hạ ngưỡng nào.
- **Level cũ:** vẫn 0/3 hợp lệ, đúng như chưa chạm tới.
- **Chạy lại pipeline:** cả hai file JSON giống hệt từng byte.
- **File bảo vệ:** ảnh nguồn giữ nguyên checksum; 3 level cũ và `web/` không đổi.

## Cần bạn duyệt

1. Mask Relax sau khi chỉnh tay mắt trái, và cả silhouette nói chung.
2. Có giữ `--keep-tips 0.25` (6 ô Relax, 4 ô Easy) không?
3. Các hộp `preserve_regions` quanh mắt (Relax) và miệng (Easy).
4. Hướng đi cho Easy: đơn giản hoá ảnh nguồn và/hoặc dùng ảnh tranh gốc cho thumbnail.
