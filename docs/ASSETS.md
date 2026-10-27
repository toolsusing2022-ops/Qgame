# Asset dùng trong game và nguồn asset miễn phí đề xuất

Cập nhật: 2026-10-27.

## Đang dùng trong repo

| Asset | Vị trí | Nguồn | Giấy phép |
|---|---|---|---|
| Âm thanh giao diện: đặt hạt (`glass_002/003/005/006`, `drop_001`), chạm sai (`bong_001`), hoàn tác (`back_002`), chọn màu (`select_002`), xong một màu (`confirmation_004`) | `game/audio/<tên>/` | Kenney "Interface Sounds" 1.0, lấy từ bản port WAV [Calinou/kenney-interface-sounds](https://github.com/Calinou/kenney-interface-sounds) | CC0 1.0 (`game/audio/LICENSE_kenney_interface_sounds.txt`); ghi công Kenney là tuỳ chọn |
| Chuông hoàn thành tranh, âm nền biển và mưa | `game/audio/level_complete/chime.wav`, `game/audio/ambient/*.wav` | Tự tạo bằng `tools/gen_ambient_audio.py` (tổng hợp, seed cố định) | Của dự án, không có thành phần bên thứ ba |
| Font Be Vietnam Pro (Regular, SemiBold, Bold) | `game/assets/fonts/` | [google/fonts](https://github.com/google/fonts/tree/main/ofl/bevietnampro) | SIL OFL 1.1 (`game/assets/fonts/OFL.txt`) |
| Icon: search, undo-2, scan, volume-2, volume-x, chevron-left, waves, cloud-rain, bell-off | `game/assets/icons/` | npm `lucide-static` 1.62.0 (nét vẽ đổi sang màu trắng) | ISC (`game/assets/icons/LICENSE_lucide.txt`) |
| Engine web | `build/` (không commit) | Godot 4.4.1-stable, export template `web_nothreads_release` | MIT |

**Cách chọn âm thanh:** tôi không nghe được file. Âm được chọn theo số đo:
- Tiếng đặt hạt: ngắn khoảng 0,13 giây, độ sáng trung bình 2–3 kHz.
- Tiếng chạm sai: trầm (khoảng 260 Hz), đúng tinh thần "tok trầm" ở GS-6.6.
- Tiếng xong một màu: ≤ 1,2 giây.

Cần nghe thử và thay nếu không hợp. Thay chỉ bằng cách đổi file trong `game/audio/<tên>/`, không phải sửa code.

## Nguồn asset miễn phí đề xuất cho các bước sau

| Nhu cầu | Nguồn | Giấy phép | Ghi chú |
|---|---|---|---|
| Âm giao diện, click, hạt | [Kenney Interface Sounds](https://opengameart.org/content/interface-sounds) (bản Godot trên [Godot Asset Library](https://www.godotengine.org/asset-library/asset/793)) | CC0 | Đã dùng; các gói Kenney khác (UI Audio, Impact Sounds) cũng CC0 |
| Âm nền sóng biển thật | OpenGameArt: ["Beach Ocean Waves"](https://opengameart.org/node/11174), ["Sea and river wave sounds"](https://opengameart.org/content/sea-and-river-wave-sounds) | CC0 (theo trang; cần kiểm tra lại trên từng file) | Có thể thay âm nền tự tạo |
| Font tiếng Việt | Be Vietnam Pro (Google Fonts) | OFL 1.1 | Đã dùng |
| Icon | Lucide | ISC | Đã dùng |

**Bị chặn khi tải trong phiên này:** chính sách mạng của môi trường cloud chặn các host `kenney.nl`, `opengameart.org`, `freesound.org`, `pixabay.com`, `zapsplat.com` và `sonniss.com`. Tải được: GitHub (git clone, release, raw) và npm.
