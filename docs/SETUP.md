# Cài đặt môi trường

## 1. Server trên Windows

1. **Rust stable** (rustup). Kiểm tra: `cargo --version`.
2. **yt-dlp**: tải `yt-dlp.exe` ở https://github.com/yt-dlp/yt-dlp/releases. Cập nhật thường xuyên bằng `yt-dlp -U`, vì YouTube
   đổi liên tục.
3. **Deno** (yt-dlp cần để giải mã link YouTube): `winget install DenoLand.Deno`. Sau khi cài thì **mở terminal mới** để PATH
   nhận deno.
4. Build và chạy:
   ```powershell
   cd server
   cargo build --release
   copy config.example.toml target\release\config.toml   # sửa nếu cần
   target\release\tubemini-server.exe
   ```
   Lúc khởi động server ghi phiên bản yt-dlp và deno ra log; thiếu cái nào thì có dòng `ERROR ... NOT available`.
5. **Mở cổng 8080 trên Windows Firewall** (PowerShell chạy bằng quyền Administrator), chỉ cho mạng Private:
   ```powershell
   New-NetFirewallRule -DisplayName "TubeMini server (TCP 8080)" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow -Profile Private
   ```
6. Thử: mở `http://<IP PC>:8080/` trên trình duyệt. Trang thử tải trực tiếp nằm ở `http://<IP PC>:8080/gd0`.

## 2. Máy build app iOS (Linux có Theos)

Dự án dùng máy Ubuntu thử nghiệm (máy ảo, `~/TestLab`); WSL2 Ubuntu cũng làm được y hệt.

1. Gói cần có: `build-essential git curl python3 fakeroot` (thêm `rsync` nếu muốn).
2. Cài Theos + toolchain + SDK 9.3 đã vá cho iOS 6:
   ```sh
   bash scripts/setup-theos.sh        # cài vào ~/theos; chạy lại nhiều lần không sao
   ```
   Script làm ba việc: clone Theos, tải toolchain iOS cho Linux (L1ghtmann, clang 11 / ld64-609), lấy `iPhoneOS9.3.sdk` từ
   theos/sdks rồi vá ba chỗ để chạy được trên iOS 6 (xem chú thích trong script và `docs/DECISIONS.md` mục D2).
3. Build từ Windows (Git Bash), mã nguồn được gửi sang máy Linux qua SSH:
   ```sh
   TM_BUILD_HOST=<user>@<IP máy Ubuntu> TM_BUILD_KEY=~/.ssh/<khóa> scripts/ios-build.sh             # bản debug
   TM_BUILD_HOST=... scripts/ios-build.sh FINALPACKAGE=1                                          # bản phát hành
   ```
   Script in ra kết quả `lipo -info` (phải là **armv7** duy nhất) và `LC_VERSION_MIN_IPHONEOS` (phải là **6.0**), rồi chép `.deb`
   về `ios/TubeMini/packages/`.
   Nếu làm thẳng trên máy Linux: `cd ios/TubeMini && THEOS=~/theos make package`.

## 3. Cài lên iPad (đã jailbreak, có OpenSSH)

```sh
TM_IPAD_HOST=<IP iPad> TM_IPAD_PASS=<mật khẩu root> scripts/deploy.sh --launch
```

- Mật khẩu chỉ truyền qua biến môi trường, **không ghi vào file nào trong repo**.
- OpenSSH trên iOS 6 đã cũ (6.x), nên script tự bật các thuật toán cũ (`ssh-rsa`, `diffie-hellman-group1/14-sha1`, `aes-cbc`) và
  dùng `scp -O`.
- `postinst` của gói tự chạy `uicache` để icon hiện ra. `--launch` mở app nếu iPad có công cụ `cblaunch`.

## 4. Kiểm thử trên iPad qua SSH (bản debug)

Ghi lệnh vào `/var/mobile/Documents/TubeMini-cmd.txt` khi app đang mở; app đọc file mỗi 0,7 giây rồi xóa:

```sh
cat > /var/mobile/Documents/TubeMini-cmd.txt <<'EOF'
mark thu-phat
play https://...googlevideo.com/videoplayback?...
wait 8
status
frame f1
seek 300
wait 6
status
stop
EOF
cat /var/mobile/Documents/TubeMini.log
```

Danh sách lệnh nằm ở đầu `ios/TubeMini/Debug/TMDebug.h`. Ảnh chụp lưu trong `/var/mobile/Documents/TubeMini-shots/`.

Công cụ đã cài sẵn trên iPad thử nghiệm (từ dự án ConBangTV_Legacy): `cblaunch status|wake|launch <bundle id>`,
`cbsymcheck` (đầu vào lấy từ `symlist.py`, kiểm tra binary có dùng ký hiệu nào iOS 6 không có), `cbnettest <url>…`.
