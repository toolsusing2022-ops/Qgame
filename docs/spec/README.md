# Đặc tả gameplay MVP: cách đọc

Các file trong thư mục này là bản lưu nguyên văn từng phiên bản đặc tả, theo thứ tự đã soạn và rà soát.

| File | Loại | Ghi chú |
|---|---|---|
| `gameplay_mvp_v0.1.md` | Bản đầy đủ | Bản nháp đầu |
| `gameplay_mvp_v0.2.md` | Bản đầy đủ | Undo, kiểm tra `remaining`, hash, lưu |
| `gameplay_mvp_v0.3.md` | **Bản đầy đủ, làm nền** | Quyết định D-1…D-10, đánh số `GS-<mục>.<số>` / `TC-<mục>.<số>`, hash tham chiếu |
| `gameplay_mvp_v0.4.md` | Các phần thay thế cho v0.3 | Outbox, catalog, khôi phục A–D, phân loại sự kiện |
| `gameplay_mvp_v0.4.1.md` … `gameplay_mvp_v0.4.9.md` | Bản sửa tăng dần | Mỗi bản chỉ ghi các mục thay đổi so với bản liền trước |

**Đọc trạng thái hiện hành:** lấy v0.3 làm nền, áp v0.4, rồi lần lượt áp v0.4.1 → v0.4.9. Khi hai bản nói khác nhau về cùng một mục, bản mới hơn thắng.

**Trạng thái duyệt:** v0.4.9 là bản mới nhất, **chưa được duyệt**. Bản này có thêm Phần B, hướng dẫn đi từ đặc tả tới chạy test và kiểm chứng.

**Các quyết định đã chốt (KT):**
- KT-1: dùng `content/catalog.json`.
- KT-2: schema level v1.
- KT-3: không khôi phục tiến độ khi thiếu metadata màu.
- KT-4: thông báo khi `source = bak`, không thêm bộ đếm commit.
- KT-5: giao diện `StorageBackend`; chỉ dùng native khi có nguyên nhân N4 và đủ bằng chứng.
- KT-6: chỉ tuyên bố độ bền ở mức đã kiểm chứng.
- KT-7: `save_blocked` không chặn gameplay, có banner cố định.

**Lưu ý:** các đoạn "Trạng thái repo" ở cuối mỗi bản ghi lại trạng thái tại thời điểm soạn, không phải trạng thái hiện tại. Chưa có quy tắc nào được kiểm chứng trên thiết bị, và chưa có code Godot.
