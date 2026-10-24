<!-- Lưu trữ nguyên văn báo cáo từ phiên làm việc. -->

# Báo cáo nghiên cứu cơ chế gameplay Pixel Bead Art ASMR

**Giới hạn của báo cáo:**
- Tôi **chưa trực tiếp chơi** game nào trong danh sách.
- Mạng của môi trường chặn mở thẳng App Store, Google Play và website (proxy trả về 403). Mọi thông tin "đã xác minh" vì vậy đến từ đoạn trích mô tả cửa hàng, trung tâm trợ giúp và đánh giá người dùng mà công cụ tìm kiếm trả về, chưa đọc toàn văn trang.
- Phần "quan sát" dựa trên các khung hình trích từ video TikTok bạn gửi trước đó, cùng prototype web mà tôi kiểm thử bằng script tự động (không có người chơi thật).

Ký hiệu dùng trong báo cáo:
- **[XM]**: đã xác minh qua nguồn.
- **[QS]**: nhận định dựa trên quan sát.
- **[GT]**: giả thuyết cần thử nghiệm.

---

## 1. Tóm tắt kết luận và khuyến nghị

1. **Không có một cơ chế "chuẩn" cho thể loại này.** Game cùng loại dùng cả bốn kiểu [XM]:
   - Chạm đặt từng hạt: Bead Art: Mosaic Calm, JewelPainter, Mosaic Beads Puzzle.
   - Một chạm tô cả vùng liền: Jewelscapes, Gems Flow.
   - Kéo ngón tay để tô liên tiếp: Color by Number: Pixel Art, RePixel, Fine Artist.
   - Đặt từng hạt làm nền, kèm công cụ tô nhanh: Pixel Art của Easybrain có Magic Wand/Color Splash; Diamond Painting ASMR Coloring có công cụ đặt 3 viên một lượt.
2. **Game gần nhất với định hướng của bạn là Bead Art: Mosaic Calm** [XM]:
   - Gắn số cho mọi ô và mọi hạt, thân thiện với người khó phân biệt màu.
   - Có "gentle aiming guide" (dẫn hướng ngắm nhẹ nhàng), undo, haptic, âm thanh đặt hạt tuỳ chọn.
   - Không dùng thuê bao.
3. **Khuyến nghị cho MVP: phương án D, làm tối giản.**
   - Một chạm đặt một hạt là mặc định, đi kèm ba thứ:
     - Làm nổi nhẹ tất cả ô hợp lệ của màu đang chọn.
     - Chạm "hít" về ô hợp lệ gần nhất, để giảm yêu cầu chạm thật chính xác.
     - Một trợ giúp "tìm ô còn thiếu".
   - Chạm sai: không đặt hạt và không phạt, chỉ phản hồi nhẹ.
   - Kéo liên tiếp và tô theo vùng **chưa đưa vào bản phát hành**, nhưng nên dựng trong bản thử nghiệm để A/B test sớm. Lý do: rủi ro lớn nhất của thể loại là mỏi tay ở tranh từ vài trăm đến hơn 1000 hạt, và bằng chứng cho thấy kéo-tô rất phổ biến nhưng bị phàn nàn là khó chính xác.
4. **Vòng chơi bạn đề xuất đúng về cốt lõi**, nhưng chưa đủ cho tranh lớn:
   - `squid_relax_01` có 1024 ô. Ở mức zoom vừa khung, mỗi ô trên iPhone chỉ khoảng 12pt, trong khi khuyến nghị tối thiểu cho vùng chạm là 44pt [XM].
   - Vì vậy zoom, nút "tìm ô" và cơ chế giảm số lần chạm là bắt buộc, không phải tính năng thêm [QS].
5. **Lệch với prototype web hiện tại:** prototype tự xếp thứ tự màu cho người chơi, trong khi tài liệu MVP và các game tham khảo đều cho người chơi tự chọn màu. Video TikTok bạn gửi thì cho thấy khay tự nạp màu [QS]. Đây là một biến thể đáng đưa vào thử nghiệm, chưa nên loại bỏ.

---

## 2. Bảng so sánh game tham khảo

| Game | Có đúng tên bạn yêu cầu? | Cơ chế đã xác minh [XM] | Nguồn chính |
|---|---|---|---|
| **Bead Art: Mosaic Calm** | Có | Chế độ tô theo số gắn số cho mọi ô và mọi hạt, thân thiện với người khó phân biệt màu. Hạt bóng, có haptic. Nhạc lo-fi và tiếng đặt hạt đều tuỳ chọn. Có "gentle aiming guide", undo, tự lưu, xem trước tranh hoàn chỉnh, 300+ tranh, mua một lần, chơi offline | Trang App Store id6766010170 (qua đoạn trích tìm kiếm) |
| **Pixel Bead ASMR** (`com.gg.bead.asmr`) | Có | **Thể loại khác:** xếp hạt theo màu, nhặt cả chồng hạt cùng màu rồi đặt lên bảng. Tranh pixel lộ dần từng phần, không đếm giờ, có "Smart Sort Assist" gom hạt cùng màu trong khay. Một người đánh giá gọi đây là game nhấp liên tục, không phải giải đố | Trang Google Play và App Store id6773995091 |
| **Diamond Painting ASMR Coloring** (CrazyLabs) | Có | Tô theo số. Tiếng "click" khi viên đá khớp vào ô được nêu như điểm bán hàng. Có thao tác kéo một "máy/bút" đặt đá qua vùng tranh; có thể đặt từng viên hoặc theo cụm; có công cụ đặt 3 viên dọc, ngang hoặc từng viên. Đánh giá: khen âm thanh; có người muốn chạm vào số thay vì phải kéo bút; than phiền nhiều nhất là quảng cáo. Khoảng 4,6/5 từ ~56 nghìn đánh giá trên iOS | Trang App Store và Google Play, Uptodown, bài review của Complete Xbox |
| **PixBead** | **Không tìm thấy** | Không có ứng dụng nào trùng tên. Chỉ có các công cụ tạo mẫu hạt (PixelBead, Pixel Bead Master), không phải game | Kết quả tìm kiếm mwm.ai |
| Bead Art – Coloring Puzzle (BAF) | — | Vị trí đúng của hạt được chỉ bằng đèn nhấp nháy; đặt hết hạt thì dùng bàn là làm chảy để hoàn thành tranh. 4,7/5 từ 420 đánh giá | Trang App Store id1553727086 |
| Mosaic Beads Puzzle (Hama Magic) | — | Chọn màu trong palette rồi đặt hạt lên lưới; quảng bá như liệu pháp giảm căng thẳng | Trang App Store id1451840565 |
| JewelPainter Color by Number | — | "every tap places a shining bead" (mỗi chạm đặt một hạt) | Trang LDPlayer (bên thứ ba) |
| Jewelscapes, Gems Flow | — | Một chạm tô cả vùng liền | Trang Bluestacks |
| Pixel Beads (Kiwi Fun) | — | Xếp hạt 3D vào khay theo màu để làm lộ tranh pixel; dùng khay làm không gian tính toán chiến thuật | Website Kiwi Fun, Google Play |
| Pixel Art (Easybrain), tô theo số | — | Magic Wand: tô các ô kề nhau cùng số. Color Splash: tô các ô kề nhau với mọi số. Smart Magnifier: tìm ô của màu đang chọn | Trung tâm trợ giúp Easybrain, trang cửa hàng |
| Color by Number: Pixel Art (Agile Release) | — | Chạm để tô từng ô, hoặc kéo qua tranh để mọi ô khớp màu dưới ngón tay được tô. Có trợ giúp "Fill" tô phần còn lại của một màu | Google Play |
| RePixel, Pixel Art (JIRAPAS), Fine Artist, Pixx | — | Nhấn giữ rồi kéo để tô nhiều ô. Một người đánh giá app tô màu theo số khác than kéo-tô cần chính xác cao | Trang cửa hàng và đánh giá Google Play |
| **Video TikTok bạn gửi** (@cosy.gameplay) | — | **[QS]** Khay tự nạp lần lượt từng màu; chạm vào ô thì hạt được gắn vào; ba trợ giúp (đũa phép, cọ, nam châm), mỗi loại có huy hiệu đếm 3 lượt | Các khung hình tôi trích từ video ở đầu phiên |

**Nhận định [QS]:** thể loại đang tách thành hai nhánh.
- **Tô theo số:** đặt hạt vào ô đã định trước. Đây là nhánh của dự án này.
- **Xếp và gom hạt:** phần giải đố nằm ở việc quản lý khay. Đánh giá "nhấp liên tục" cho thấy nếu phần giải đố quá nông, người chơi sẽ thấy nhàm.

---

## 3. Phân tích bốn phương án

### A. Đặt từng hạt
- **Ưu:**
  - Mỗi chạm cho ra một tiếng "click" và một hạt. Đây chính là thứ các game nhấn mạnh trong quảng bá ("satisfying click", "every tap places a shining bead") [XM].
  - Người chơi kiểm soát hoàn toàn, không lo đặt nhầm hàng loạt.
  - Dễ làm và dễ test nhất.
- **Nhược:**
  - Tranh 1024 ô nghĩa là ít nhất 1024 lần chạm.
  - Ô nhỏ hơn 44pt buộc phải zoom nhiều và kéo màn hình qua lại liên tục [XM, QS].
  - Hai trăm lần chạm đầu có thể thư giãn, nhưng hàng nghìn lần thì dễ mỏi và nhàm [GT].
- **Giảm rủi ro:**
  - Làm nổi các ô hợp lệ.
  - Chạm "hít" về ô hợp lệ gần nhất.
  - Nút tìm ô còn thiếu.
  - Kích thước tranh tăng dần theo độ khó (Easy khoảng 300 ô).

### B. Tự động đặt theo vùng — hai cách khác nhau
- **B1. Một chạm tô vùng liền cùng màu:** Jewelscapes, Gems Flow [XM].
  - Nhanh hơn rất nhiều với các mảng lớn như nền hay thân.
  - Với tranh có viền và bóng đổ, vùng liền thường to, nên một chạm có thể đặt vài chục hạt. Khi đó cảm giác "tự tay" gần như mất [GT].
- **B2. Một chạm tô toàn bộ ô còn thiếu của màu đó:** Agile Release có trợ giúp "Fill" [XM].
  - Đây thực chất là nút "hoàn thành màu".
  - Hữu ích khi một màu chỉ còn vài ô nằm rải rác.
  - Nếu dùng làm cơ chế chính thì gần như bỏ qua phần chơi.
- **Kết luận:** B phù hợp làm **trợ giúp có giới hạn** (giống Magic Wand của Easybrain), không phù hợp làm cơ chế mặc định.
  - Nếu có B, nên phát âm thanh của từng hạt nối tiếp nhau theo một nhịp đều, không phát cùng lúc. Như vậy vẫn giữ được cảm giác ASMR [GT].

### C. Kéo để đặt liên tiếp
- **Ưu:**
  - Rất phổ biến trong game tô theo số; nhiều app quảng bá đây là cách tô nhanh [XM].
  - Có thể giảm số lần chạm đi nhiều lần [GT].
- **Nhược:**
  - **Xung đột với thao tác kéo để di chuyển tranh.** Các app thường giải quyết bằng "nhấn giữ rồi mới kéo" (RePixel, JIRAPAS) [XM].
  - Bị phàn nàn là cần chính xác cao [XM].
  - Có người không thích phải kéo công cụ thay vì chạm thẳng vào số (Diamond Painting) [XM].
  - Ngón tay che mất ô đang tô.
  - Khi kéo nhanh, ngón tay có thể nhảy qua ô mà không chạm vào; phải nội suy đường đi giữa hai điểm chạm [GT].
- **Hiệu năng trên iPhone [GT]:**
  - Ở 120Hz, mỗi khung hình có thể phải xử lý nhiều ô.
  - Cần giới hạn số âm thanh phát cùng lúc, và chỉ vẽ lại phần thay đổi chứ không vẽ lại cả lưới.
- **Cách tránh đặt nhầm [GT]:**
  - Kéo chỉ đặt vào ô đúng màu, nên không thể "tô sai" mà chỉ có thể bỏ sót.
  - Có trạng thái "đang kéo" hiển thị rõ ràng.
  - Hiện một kính lúp nhỏ phía trên ngón tay.
  - Undo hoàn tác cả một lần kéo.

### D. Cơ chế lai (khuyến nghị)
- **Mặc định:** chạm một ô đặt một hạt, có làm nổi ô hợp lệ và chạm "hít" ô gần nhất.
- **Trợ giúp tô nhanh có giới hạn:**
  - Một là "tô vùng liền" (B1).
  - Hai là "hoàn thành màu" (B2), chỉ bật khi màu còn ≤ N ô.
- **Kéo (C):** chỉ bật bằng nhấn giữ, và chỉ thử trong bản test.
- **Cân bằng:**
  - Mọi cách tô nhanh đều phát âm thanh của từng hạt nối tiếp theo nhịp, để giữ "hạt nối hạt".
  - Zen cho dùng trợ giúp tuỳ ý; Journey giới hạn số lượt.
- **Độ phức tạp cho MVP:** chỉ A và nút tìm ô là bắt buộc. B1/B2 tốn ít công vì đã có sẵn dữ liệu ô và màu. C là phần tốn công nhất do xử lý cử chỉ, nên để sau [QS].

---

## 4. Vòng gameplay MVP đề xuất

1. Mở tranh: hiện toàn cảnh, các ô chưa đính có màu nhạt và mang số màu.
2. **Chọn màu tự động lần đầu:** màu có nhiều ô nhất được chọn sẵn. Người chơi có thể đổi bất kỳ lúc nào trong khay.
3. Khi một màu được chọn:
   - Các ô hợp lệ của màu đó được làm nổi tĩnh, đậm hơn, không nhấp nháy.
   - Số trên ô được làm rõ.
   - Khay hiện số hạt còn lại của màu.
4. Chạm vào một ô:
   - Nếu chạm trúng hoặc gần (trong khoảng ~½ ô) một ô hợp lệ thì hạt được đặt vào ô đó. Kèm theo: hoạt ảnh hạt "nảy", tiếng click ngẫu nhiên trong một nhóm 4–6 mẫu, haptic nhẹ nếu thiết bị hỗ trợ.
   - Nếu không có ô hợp lệ nào gần: xem mục 5.
5. Đặt hết một màu:
   - Phát một tiếng chuông nhẹ.
   - Khay tự chuyển sang màu còn lại gần nhất hoặc nhiều ô nhất, kèm thông báo nhỏ. Đúng như tài liệu MVP yêu cầu: tự chuyển màu hoặc gợi ý rõ ràng.
6. **Trợ giúp:**
   - "Tìm": di chuyển và zoom tới ô còn thiếu của màu đang chọn.
   - "Tô nhanh" (B1/B2): Journey giới hạn lượt, Zen không giới hạn.
7. Tự lưu sau mỗi lần đặt hạt (có thể gộp và ghi trễ một chút).
8. Hoàn thành tranh:
   - Hiện tranh hoàn chỉnh cùng âm thanh kết thúc ngắn.
   - Lưu vào bộ sưu tập, mở khoá tranh tiếp theo (Journey).

---

## 5. UX trên màn hình iPhone (dọc)

- **Vùng tranh:** chiếm khoảng 65–70% chiều cao.
  - Chụm hai ngón để zoom, kéo hai ngón (hoặc một ngón khi đang zoom) để di chuyển.
  - Có nút "toàn cảnh".
  - Số trên ô chỉ hiện khi ô đủ lớn (ví dụ ≥ 18pt) [GT].
  - Đặt hạt khi **nhấc tay**, không phải khi chạm xuống; nếu ngón tay di chuyển quá ngưỡng thì coi như kéo màn hình.
- **Khay màu:** đặt dưới cùng, trong vùng ngón cái dễ với tới.
  - Một hàng swatch cuộn ngang, mỗi swatch có số màu và số hạt còn lại.
  - Swatch đang chọn to hơn và có viền.
  - Màu đã xong thì mờ đi kèm dấu tích.
  - Swatch ≥ 44pt [XM].
- **Các nút:**
  - Hàng nút nhỏ phía trên khay: Tìm, Tô nhanh (có số lượt), Undo, Cài đặt.
  - Không đặt nút đè lên tranh.
  - **Không tự di chuyển camera khi đổi màu:** đã có người đánh giá than phiền về hành vi này [XM]. Thay vào đó dùng nút "Tìm".
- **Khi chạm sai màu:**
  - Không đặt hạt, không mất tiến độ.
  - Phản hồi:
    - Ô vừa chạm hiện số của nó khoảng 0,5 giây.
    - Swatch đúng màu trong khay sáng lên nhẹ.
    - Một tiếng "tok" trầm và nhỏ, khác hẳn tiếng đặt hạt đúng.
    - **Không** dùng haptic báo lỗi mạnh: Apple khuyên haptic phải gắn rõ với nguyên nhân và không lạm dụng [XM].
  - Sau khoảng 3 lần sai liên tiếp mới hiện gợi ý chữ, ví dụ "Ô này cần màu số 5 — chạm để chọn" [GT].
  - Zen có tuỳ chọn tắt cảnh báo, đúng như tài liệu MVP.
- **Trợ năng:**
  - Số trên ô và ký hiệu màu giúp người khó phân biệt màu; Mosaic Calm dùng đúng cách này [XM].
  - Tôn trọng cài đặt Reduce Motion: thay hoạt ảnh nảy bằng hiệu ứng mờ dần [XM].
  - Âm thanh, nhạc nền và haptic bật/tắt riêng từng thứ [XM].

---

## 6. Phân nhóm tính năng

| Nên làm ngay (MVP) | Nên thử nghiệm | Chưa nên làm |
|---|---|---|
| Chạm đặt một hạt; đặt khi nhấc tay; ngưỡng phân biệt chạm với kéo | Chạm "hít" về ô hợp lệ gần nhất (bán kính bao nhiêu) | Kéo-tô làm mặc định |
| Làm nổi tĩnh các ô hợp lệ, có số trên ô | Nhấn giữ rồi kéo để tô (C) | Combo hay điểm số kích thích trong Zen |
| Khay có số hạt còn lại; tự chuyển màu khi hết | Trợ giúp B1 (tô vùng liền) và B2 (hoàn thành màu khi còn ≤ N ô) | Cơ chế xếp và gom hạt kiểu Pixel Beads (thể loại khác) |
| Phản hồi nhẹ khi chạm sai, không phạt | Khay tự nạp màu như video tham khảo, so với người chơi tự chọn | Bước dùng bàn là làm chảy hạt (BAF) |
| Zoom, pan, nút toàn cảnh, nút Tìm | Kính lúp nhỏ khi kéo | Quảng cáo hoặc thuê bao (bị phàn nàn nhiều nhất) |
| Undo, tự lưu | Âm thanh nối tiếp theo nhịp khi tô nhanh; tốc độ nhịp | |
| Âm thanh từ nhiều mẫu ngẫu nhiên, giới hạn số âm phát cùng lúc; haptic nhẹ và tắt được; hỗ trợ Reduce Motion | | |

---

## 7. Giả thuyết và tiêu chí kiểm thử

**Thiết kế thử nghiệm [GT]:**
- **Các bản cần dựng:** prototype có thể đổi cơ chế tuỳ chọn:
  - A thuần.
  - A + chạm "hít".
  - A + B2 (khi còn ≤ 10 ô).
  - A + B1.
  - A + C (nhấn giữ rồi kéo).
  - Khay tự nạp màu.
- **Tranh dùng để test:** `squid_easy_01` (300 ô) và một phần `squid_relax_01`.
- **Người chơi:** mỗi vòng 6–8 người, mỗi người thử 2–3 biến thể theo thứ tự xáo trộn.

**Đo lường:**
- Thời gian hoàn thành và số lần chạm cho mỗi hạt.
- Tỷ lệ chạm sai màu, và tỷ lệ **đặt nhầm do kéo màn hình**.
- Tỷ lệ dùng trợ giúp.
- Điểm thư giãn và mức mỏi tự đánh giá (thang 1–5).
- Có tự bắt đầu tranh thứ hai không. Tài liệu MVP đặt mục tiêu ≥ 60%.

| Giả thuyết | Tiêu chí quyết định (đề xuất) |
|---|---|
| H1: A thuần đủ thư giãn cho tranh ~300 ô | Điểm thư giãn ≥ 4/5, mỏi ≤ 2/5, ≥ 80% người chơi hoàn thành tranh |
| H2: A thuần gây mỏi ở tranh ≥ 1000 ô | Nếu mỏi ≥ 3/5 hoặc bỏ dở > 30% thì bắt buộc phải có cơ chế tô nhanh cho Relax/Challenge |
| H3: chạm "hít" giảm chạm sai mà không gây đặt nhầm | Chạm sai giảm ≥ 50%; đặt nhầm (người chơi phải undo) < 1% |
| H4: kéo-tô tăng tốc mà không giảm thư giãn | Thời gian giảm ≥ 30%, đặt nhầm do pan < 2%, điểm thư giãn không giảm quá 0,5 so với A |
| H5: B1/B2 làm giảm cảm giác "tự tay đặt" | Nếu điểm "cảm giác tự tay" giảm > 1 thì chỉ giữ làm trợ giúp có giới hạn |
| H6: âm thanh nối tiếp theo nhịp khi tô nhanh vẫn tạo cảm giác ASMR | ≥ 70% người chơi chọn bản có nhịp thay vì đặt tức thì |
| H7: khay tự nạp màu dễ vào game hơn | Thời gian tới lần đặt hạt đầu tiên giảm, mà người chơi không phàn nàn mất quyền chọn màu |
| H8: thumbnail phẳng dễ nhận diện hơn bản hạt tròn ở 96px | Đúng trên ≥ 80% lượt nhận diện trong test chọn tranh |

**Quy tắc chọn [GT]:**
- Nếu H1 và H3 đạt: phát hành A + chạm "hít" + nút Tìm.
- Nếu H2 đúng: thêm B2 (và B1 nếu H5 không vi phạm).
- Chỉ đưa C vào khi H4 đạt ở cả hai kích thước tranh.

---

## 8. Nguồn đã dùng

**Mức tin cậy:**
- **Cao:** trang của chính nhà phát triển (mô tả trên cửa hàng, trung tâm trợ giúp, Apple HIG). Lưu ý đây vẫn là lời quảng bá, chưa kiểm chứng độc lập.
- **Trung bình:** trang bên thứ ba và bài review.
- **Thấp:** từng đánh giá lẻ của người dùng.

Tất cả nội dung đều đọc qua đoạn trích của công cụ tìm kiếm, không mở được trang gốc.

| Nguồn | Nội dung dùng | Mức tin cậy |
|---|---|---|
| [Bead Art: Mosaic Calm – App Store](https://apps.apple.com/us/app/bead-art-mosaic-calm/id6766010170) | Số trên ô và hạt, aiming guide, haptic, âm thanh tuỳ chọn, undo, mua một lần | Cao (lời nhà phát triển) |
| [Pixel Bead ASMR – Google Play](https://play.google.com/store/apps/details?id=com.gg.bead.asmr&hl=en_US), [App Store](https://apps.apple.com/jo/app/pixel-bead-asmr/id6773995091) | Xếp hạt, Smart Sort Assist, đánh giá "nhấp liên tục" | Cao (mô tả); thấp (đánh giá) |
| [Diamond Painting ASMR Coloring – App Store](https://apps.apple.com/us/app/diamond-painting-asmr-coloring/id1542336300), [Google Play](https://play.google.com/store/apps/details?id=com.crazylabs.diamond.paint.by.number&hl=en_US), [Uptodown](https://diamond-painting-asmr-coloring.en.uptodown.com/android), [Complete Xbox review](https://completexbox.co.uk/reviews/diamond-painting-asmr-review/), [AppGoblin](https://www.appgoblin.info/apps/1542336300) | Tiếng "click", kéo bút/máy đặt đá, công cụ 3 viên, quảng cáo, điểm đánh giá | Cao / trung bình / thấp tuỳ mục |
| [Bead Art – Coloring Puzzle (BAF)](https://apps.apple.com/us/app/-/id1553727086) | Đèn nhấp nháy chỉ vị trí đúng, bước bàn là | Cao |
| [Mosaic Beads Puzzle](https://apps.apple.com/us/app/-/id1451840565) | Chọn màu trong palette rồi đặt lên lưới | Cao |
| [JewelPainter qua LDPlayer](https://www.ldplayer.net/games/number-color-coloring-jewel-pixel-painter-on-pc.html), [Jewelscapes](https://www.bluestacks.com/campaign/com.jewel.scapes.color.by.number.free.games/en/), [Gems Flow](https://www.bluestacks.com/campaign/com.gems.flow.pixel.color.art.free.games/en/) | Mỗi chạm một hạt; một chạm tô vùng liền | Trung bình |
| [Pixel Beads – Google Play](https://play.google.com/store/apps/details?id=com.kiwifun.game.android.pixel.beads), [Kiwi Fun](https://kiwifungames.com/) | Xếp hạt vào khay theo màu | Cao |
| [Easybrain – How do I color faster](https://pixelartios.easybrain.com/hc/en-us/articles/360001846311-How-do-I-color-faster), [App Store Pixel Art](https://apps.apple.com/us/app/pixel-art-color-by-number/id1274972321) | Magic Wand, Color Splash, Smart Magnifier | Cao |
| [Color by Number: Pixel Art (Agile)](https://play.google.com/store/apps/details?id=uk.co.agilerelease.colorbynumber), [Pixel Art – JIRAPAS](https://apps.apple.com/us/app/pixel-art-coloring-by-number/id1446447659), [Pixx](https://apps.apple.com/us/app/pixx-paint-by-number-game/id1464643592), [Fine Artist](https://fineartist.jmapp.com/en), [Pixel Coloring (đánh giá)](https://play.google.com/store/apps/details?id=puzzle.pixel.art.coloring.drawing.sandbox.free.painting.games.kids.adults.fun&hl=en_US) | Kéo-tô, Fill phần còn lại, đánh giá kéo-tô cần chính xác cao | Cao (mô tả); thấp (đánh giá) |
| [Diamond Art – Paint by Number](https://apps.apple.com/us/app/diamond-art-paint-by-number/id1546086711) và các app diamond khác | Đánh giá: tự nhảy camera khi chọn màu, không zoom được, quảng cáo | Thấp |
| [Apple HIG – Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics), [Apple – Reduced motion criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria), [HIG Motion](https://developer-mdn.apple.com/design/human-interface-guidelines/foundations/motion) | Haptic nhất quán, không lạm dụng, cho phép tắt; Reduce Motion | Cao |
| [Deque – touch target size](https://dequeuniversity.com/rules/attest-ios/1.0/touch-target-size), [Adrian Roselli – Target size](https://adrianroselli.com/2019/06/target-size-and-2-5-5.html) | Tối thiểu 44×44pt (iOS), WCAG 24/44px | Trung bình (nguồn thứ cấp, chưa đọc trực tiếp HIG) |
| [Barratt & Davis 2015, PeerJ](https://peerj.com/preprints/719.html), [Barratt, Spence & Davis 2017](https://pmc.ncbi.nlm.nih.gov/articles/PMC5633022) | Yếu tố kích hoạt ASMR: âm thanh giòn, chuyển động chậm, video nhịp chậm chú trọng chi tiết | Cao (nghiên cứu khảo sát; chưa đánh giá riêng cho game) |

**Giới hạn:**
- Không xác minh được "PixBead".
- Chưa xem trực tiếp video gameplay của các game trên.
- Không xác nhận được Happy Color có booster dạng bomb hay fill hay không (nguồn mâu thuẫn), nên tôi không dùng nó làm căn cứ.

---

## 9. Xác nhận trạng thái

Tôi chỉ đọc repo và chỉ ghi các file ghi chú tạm vào scratchpad (ngoài repo):
- HEAD vẫn là `8feed74`, vẫn trên nhánh `claude/cloud-session-connection-check-hksw4v`, không có stash nào.
- `git status`, hash của phần thay đổi chưa commit và hash của toàn bộ file chưa được theo dõi **trùng khớp hoàn toàn** với lúc bắt đầu.
- Không sửa code, JSON, mask, ảnh hay level; không chạy pipeline; không cài thư viện; không commit, không push.

Nếu muốn, tôi có thể đưa báo cáo này lên một trang Artifact riêng tư để chia sẻ.
