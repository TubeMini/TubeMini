# TubeMini

Xem YouTube trên iPad mini 1 (iOS 6, đã jailbreak), gồm hai phần:

- **`server/` — tubemini-server** (Rust): chạy trên PC Windows trong nhà. Giả lập API GData cũ để app YouTube cũ cùng tweak
  TubeRepair dùng lại được, và có thêm API `/tm/v1` cho app TubeMini. Server chỉ trả XML và link video; video thì iPad tải
  thẳng từ Google.
- **`ios/TubeMini/` — app TubeMini** (Objective-C, Theos, armv7, iOS 6.0): app YouTube mới, giao diện tiếng Việt.

Tài liệu:

| File | Nội dung |
| --- | --- |
| [docs/SETUP.md](docs/SETUP.md) | Cài server, cài bộ build app, cài lên iPad, kiểm thử qua SSH |
| [docs/API.md](docs/API.md) | Hợp đồng API giữa server và app |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Các quyết định kỹ thuật và kết quả kiểm chứng |
| [docs/PROGRESS.md](docs/PROGRESS.md) | Tiến độ từng giai đoạn |
| [tubemini-prompt.md](tubemini-prompt.md) | Mô tả dự án gốc |

## Chạy nhanh server

```powershell
winget install DenoLand.Deno            # yt-dlp cần Deno; mở terminal mới sau khi cài
yt-dlp -U                               # luôn dùng yt-dlp mới nhất
cd server
cargo build --release
target\release\tubemini-server.exe      # đọc config.toml cạnh exe (mẫu: config.example.toml)
```

Mở cổng 8080 trên Windows Firewall (xem SETUP mục 1.5), rồi trên iPad vào `http://<IP PC>:8080/`.

Chạy lâu dài trên máy Linux (systemd, tự cập nhật yt-dlp): `scripts/deploy-server.sh`, xem SETUP mục 7. Server trong nhà hiện
chạy ở `http://192.168.1.192:8080`.

## Giấy phép

GPL-3.0 — xem [LICENSE](LICENSE). Định dạng lớp GData tham khảo từ server TubeRepair
(https://github.com/kevinf100/tuberepair.uptimetrackers.com, GPL-3.0).
