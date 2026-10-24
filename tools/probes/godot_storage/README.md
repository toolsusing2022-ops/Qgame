# Godot storage probes

Các script nhỏ dùng để quan sát hành vi lưu trữ của Godot 4.4.1. Chúng **không** phải test của game. Kết quả trên Linux **không** phải bằng chứng cho iOS (xem GS-12.8 trong `docs/spec/gameplay_mvp_v0.4.9.md` và các bản trước).

## Cách chạy

```bash
G=/path/to/Godot_v4.4.1-stable_linux.x86_64
D=$(mktemp -d)

# Theo dõi syscall của store/flush/close/rename
strace -f -e trace=openat,write,fsync,fdatasync,rename,unlink -o "$D/trace.txt" \
  "$G" --headless --path tools/probes/godot_storage -s probe_flush_rename.gd -- "$D"

# Rename đè lên file đã tồn tại và rename khi thiếu nguồn
"$G" --headless --path tools/probes/godot_storage -s probe_rename_existing.gd -- "$D"

# Mã thoát của quit(code)
"$G" --headless --path tools/probes/godot_storage -s probe_exit_code.gd; echo "exit=$?"
```

## Kết quả đã quan sát (Godot 4.4.1-stable, Linux x86_64, headless, 2026-10-24)

| Quan sát | Kết quả |
|---|---|
| `FileAccess.open(path, WRITE)` | `openat(... O_WRONLY|O_CREAT|O_TRUNC)` |
| `store_string` | Trả về `bool`; chưa gọi `write()` (đệm trong user space) |
| `flush()` | Trả về `void`; gọi `write()`, **không** gọi `fsync`/`fdatasync` |
| `DirAccess.rename_absolute` lên đích đã tồn tại | Một lời gọi `rename(2)`, không `unlink` trước; nội dung đích được thay |
| `rename_absolute` khi thiếu nguồn | Trả về `1` (`ERR_FAILED`), không có errno |
| `SceneTree.quit(3)` trong chế độ `-s` | Mã thoát tiến trình là 3 |
| API sync thư mục | Không tìm thấy |

Chưa có quan sát nào trên macOS hay iOS.
