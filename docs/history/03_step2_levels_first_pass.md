<!-- Lưu trữ nguyên văn báo cáo từ phiên làm việc. -->

Đã tạo xong `squid_relax_01` và bản Easy thử nghiệm, kèm sheet preview và overlay mask cho từng level. Cả hai qua `--strict` với 0 lỗi, 0 cảnh báo mà không hạ ngưỡng nào. Tôi **chưa commit, chưa push**, và đang dừng lại để chờ bạn duyệt.

**Cả hai mask đều là bản nháp, chưa phải ground truth.** Tôi tạo chúng bằng `tools/draft_mask.py`, tên file có hậu tố `_draft`, và chạy lại script cho ra đúng từng pixel. Mask Relax có một lần chỉnh tay mà bạn cần duyệt:
- **Mắt trái của con mực bị bỏ sót.** Mắt nằm sát mép đầu nên bước lấp lỗ coi nó là nền.
- **Cách sửa:** tôi thêm vào mask những pixel không phải nước xanh trong một elip quanh mắt (tâm 611,550; bán trục 38 và 54).
- **Còn sót:** 2 dải mảnh 3–4px ở mép mí mắt, nhỏ hơn nhiều so với một ô.

## Số liệu

| | `squid_relax_01` | Easy thử nghiệm (`squid_easy_01`) |
|---|---|---|
| Lưới | 32×32 = 1024 ô | 20×15 = 300 ô (crop sát mực, lề 4%) |
| Số màu | 14 (7 chủ thể, 7 nền) | 8 (6 chủ thể, 2 nền) |
| Mask coverage | 30,5% ảnh gốc | 38,4% ảnh gốc, 44,3% vùng crop |
| Ô chủ thể / ô nền do mask loại ra | 310 / 714 | 133 / 167 |
| Ô biên có chủ thể nhưng bị loại (coverage < 0,5) | 115 | 55 |
| Ô biên được nhận vào chủ thể dù có một phần nền | 104 | 57 |
| Silhouette IoU / recall / precision | 0,872 / 0,927 / 0,936 | 0,833 / 0,909 / 0,909 |
| Số mảnh chủ thể rời nhau | 1 | 1 |

**Số ô mỗi màu:**
- **Relax:** water_deep 163, water_bright 149, reef_dark 140, body 127, water 106, body_dark 80, sand 70, reef_brown 47, sucker 40, surface 39, shadow 37, highlight 18, pupil 7, eye_white 1.
- **Easy:** water 91, body 85, water_deep 76, shadow 19, cream 16, deep_red 7, dark 5, eye_white 1.

## Xúc tu bị mất sau khi chuyển sang lưới

**Không mất trọn xúc tu nào**, nhưng có các đầu xúc tu bị cụt (toạ độ tính theo ảnh gốc):

- **Relax:**
  - Khoảng 0,82 ô ở đầu xúc tu dài cong xuống, phía dưới giữa (522–574, 1035–1074).
  - Khoảng 0,31 ô ở đầu xúc tu giữa bên phải (992–1028, 839–855).
  - Khoảng 0,27 ô ở một xúc tu dưới bên phải (858–884, 1087–1107).
  - Khoảng 0,19 ô ở đầu xúc tu cong trên cùng bên trái (222–241, 365–385).
  - Khoảng 0,15 ô ở đầu xúc tu dưới cùng bên phải (989–1002, 1126–1146).
- **Easy:**
  - Khoảng 0,38 ô ở đầu xúc tu phía sau, góc dưới phải (1108–1175, 933–978).
  - Khoảng 0,24 ô ở đầu xúc tu cong bên phải (1282–1321, 569–603).

## Palette: tôi thiết kế bằng tay, cần bạn duyệt

- **Cách chọn:** dựa trên phân cụm màu riêng cho chủ thể và cho nền, cộng với mẫu màu lấy trực tiếp từ mắt, miệng, thân và nước.
- **Không màu nào bị gộp theo số lượng ô.** Chủ thể chỉ được dùng màu chủ thể, nên san hô đỏ không thể mượn màu của mực. Ở Relax, san hô được map sang `reef_brown`.
- **Khoảng cách màu:** cặp gần nhau nhất có ΔE00 = 13,3 (Relax) và 15,0 (Easy).
- **Viền chủ thể/nền:** mọi cặp màu nằm ở viền đều có ΔE00 ≥ 20, nên không có cảnh báo viền yếu.
- **Tương phản sáng thấp, nhưng chỉ giữa các màu cùng phía:** `sucker`/`highlight` 1,20:1 và `sand`/`surface` 1,36:1. Hai cặp này đều nằm cùng phía chủ thể hoặc cùng phía nền, không phải ở viền con mực.
- **Easy có thêm màu `deep_red` (#6e1416)** để giữ được miệng. Nếu không có màu này, khoang miệng bị tính thành `shadow` và mất hẳn. Màu này cũng xuất hiện ở bóng sâu dưới các xúc tu.
- **`min_share`** (ngưỡng để một màu nhỏ như con ngươi được ưu tiên trong ô): `dark` 0,25, `eye_white` 0,3, `deep_red` 0,2. Riêng ở Relax, tôi bỏ `min_share` của `eye_white`: ở bản 28 cột, nó làm lòng trắng mắt rơi nhầm lên vây.

## Nhận định về hình ảnh

- **Relax:** con mực đọc được rõ, có đủ hai con ngươi. Lòng trắng mắt chỉ còn 1 ô (ở mắt phải). Ở 24 và 28 cột thì lòng trắng mắt hoặc mất, hoặc rơi nhầm, nên tôi chọn 32 cột. Đổi lại, 1024 ô trên iPhone **bắt buộc phải có zoom**.
- **Easy:** nhìn ra ngay con bạch tuộc với đầu tròn, xúc tu hai bên, mắt và miệng. Nhưng mắt chỉ còn là 2–3 hạt tối, và lòng trắng chỉ còn ở mắt trái. Ở thumbnail 96px, khuôn mặt chỉ còn là vài chấm. Ở 16 cột thì mất hẳn lòng trắng mắt.

## Kết quả test (đã chạy thật)

- **Unit test:** 59/59 pass (42 test cũ và 17 test mới), kể cả khi coi `ResourceWarning` là lỗi.
- **Gài lỗi có chủ đích:** 4/4 lỗi gài vào các luật mới đều bị test bắt.
- **Chạy lại pipeline:** cả hai file JSON giống hệt từng byte.
- **Level cũ:** vẫn 0/3 hợp lệ, đúng như chưa chạm tới.

## File

**Mới:**
- `tools/draft_mask.py`, `tools/level_review.py`, `tools/tests/test_image_to_beadgrid.py`
- Trong `tools/assets/source/`:
  - `octopus_easy.webp` (bản sao nguyên byte của ảnh bạn gửi)
  - `squid_anime_mask_draft.png`, `octopus_easy_mask_draft.png`
  - `squid_relax_01.palette.json`, `squid_easy_01.palette.json`
- Thư mục `content/`:
  - `levels/squid_relax_01.json`
  - `trials/squid_easy_01.json` (nằm riêng ngoài `levels/`, chưa đưa vào game chính thức)
  - Mỗi level có kèm sheet preview, overlay mask và báo cáo dạng text

**Sửa:** `tools/image_to_beadgrid.py`:
- Xoá hẳn việc gộp màu theo số lượng ô.
- Luồng cũ in cảnh báo khi chạy, `--isolate` có cảnh báo riêng.
- Thêm luồng mask + palette.

**Không đổi:** ảnh nguồn gốc (checksum giữ nguyên), 3 level cũ, `web/`, và không có code Godot nào.

## Cần bạn duyệt

1. **Hai mask:** có giữ đủ thân, mắt và các xúc tu quan trọng không? Lần chỉnh tay elip ở mắt trái có chấp nhận được không?
2. **Kích thước Relax:** giữ 32 cột (đủ chi tiết, phải zoom), hay chấp nhận mất lòng trắng mắt để xuống 28 cột?
3. **Palette và màu `deep_red`** cho miệng ở bản Easy.
4. **Khuôn mặt bản Easy ở 20 cột** có đủ dễ nhận ra để chơi không?
