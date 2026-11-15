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

Chụp màn hình bất kỳ app nào, kể cả khung hình video: build `ios/tools/tmshot` (`cd ios/tools/tmshot && THEOS=~/theos make`), chép
`.theos/obj/debug/tmshot` vào `/usr/bin/` của iPad, rồi chạy `tmshot /var/root/shot.png`.

Công cụ đã cài sẵn trên iPad thử nghiệm (từ dự án ConBangTV_Legacy): `cblaunch status|wake|launch <bundle id>`,
`cbsymcheck` (đầu vào lấy từ `symlist.py`, kiểm tra binary có dùng ký hiệu nào iOS 6 không có), `cbnettest <url>…`.

## 5. App YouTube cũ + tweak TubeRepair trên iPad (iOS 6)

Các gói, theo thứ tự cài, đều là `.deb` lấy từ repo gốc. Dòng SHA-256 rút gọn là checksum đã đối chiếu với file `Packages` của repo:

| Gói | Bản | Nguồn | SHA-256 |
| --- | --- | --- | --- |
| Cydia Substrate (`mobilesubstrate`) | 0.9.6301 | `https://apt.saurik.com/debs/mobilesubstrate_0.9.6301_iphoneos-arm.deb` | `8dc91a06…` |
| Substrate Safe Mode | 0.9.6001 | `https://apt.saurik.com/debs/com.saurik.substrate.safemode_0.9.6001_iphoneos-arm.deb` | `86515cb9…` |
| PreferenceLoader | 2.2.6 | `http://apt.thebigboss.org/repofiles/cydia/debs2.0/preferenceloader_2.2.6.deb` | `335fff25…` |
| TubeRepair (`bag.xml.tuberepair`) | 1.2-Beta-1 | `https://cydia.skyglow.es/debs/bag.xml.tuberepair_1.2-Beta-1_iphoneos-arm.deb` | `cad60e92…` |
| AppSync Unified | 116.0 | GitHub release `akemin-dayo/AppSync` 116.0 | `0036f28f…` |
| IPA Installer Console (`ipainstaller`) | 3.4.1-1 | `http://apt.thebigboss.org/repofiles/cydia/debs2.0/ipainstallerconsole_3.4.1-1.deb` | `8ab3065a…` |

- Substrate phải dùng **0.9.6301**: bản 0.9.6000–0.9.6300 có lỗi không nạp tweak trên iOS 6 (theo changelog của saurik).
- Các bước:
  1. `dpkg -i` cả 6 gói.
  2. **Khởi động lại máy một lần** (`/sbin/reboot`) để AppSync có hiệu lực.
  3. `ipainstaller YouTube-v1.3.0.5707.ipa`. Lưu ý: **không** thêm `-i`, vì `-i` chỉ để xem thông tin.
- Đặt Custom URL bằng một trong hai cách:
  - trong Cài đặt → TubeRepair → Custom URL;
  - hoặc ghi file `/var/mobile/Library/Preferences/bag.xml.tuberepairpreference.plist`, khóa `URLEndpoint` = `http://<IP PC>:8080`
    (có `http://`, không có `/` ở cuối; thêm `/720` nếu muốn HLS), chủ sở hữu `mobile`.
- Tweak chỉ đọc cài đặt lúc app khởi động, nên đổi xong thì tắt hẳn app (`killall -9 YouTube`).
- Mở app từ SSH: `cblaunch launch com.google.ios.youtube`. Mở một video: `uiopen 'vnd.youtube://<id>'`.

### App classic (iOS 5, app YouTube có sẵn của Apple)

- Cần Substrate 0.9.6301, PreferenceLoader và tweak TubeRepair (cùng các gói ở trên). Không cần AppSync hay IPA.
- Ghi `URLEndpoint` như trên. Tweak tự ghi `ConfiguredServiceHost` (chỉ có host, không có `http://`) vào
  `com.apple.youtubeframework.plist` khi được nạp. Mở app hai lần: lần đầu để tweak ghi khóa, lần sau app đọc khóa.
- Mở app từ SSH: `uiopen youtube://`.

## 6. Server TubeRepair làm mốc so sánh

Chạy trên máy LXC 192.168.1.192, cổng 4000, unit systemd `tuberepair`:

```sh
mkdir -p /opt/tuberepair && cd /opt/tuberepair
git clone https://github.com/kevinf100/tuberepair.uptimetrackers.com.git upstream
python3 -m venv venv && ./venv/bin/pip install -r upstream/requirements.txt
# /etc/systemd/system/tuberepair.service: WorkingDirectory=/opt/tuberepair/upstream/tuberepair,
#   Environment=DEBUG=False SPYING=False PORT=4000, ExecStart=/opt/tuberepair/venv/bin/python main.py
systemctl enable --now tuberepair
```

Hiện chỉ phần bình luận của nó còn chạy (D7).

## 7. Chạy server trên máy Linux (máy LXC 192.168.1.192)

Server chính hiện chạy ở `http://192.168.1.192:8080`, không cần bật PC. PC vẫn dùng để phát triển và thử.

Cài một lần trên máy đích (Ubuntu 24.04, chạy bằng root):

```sh
apt-get install -y build-essential pkg-config unzip git curl
curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
curl -L -o /usr/local/bin/yt-dlp https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp && chmod +x /usr/local/bin/yt-dlp
curl -L -o /tmp/deno.zip https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip   && unzip -o /tmp/deno.zip -d /usr/local/bin
```

Deploy (và cả mỗi lần cập nhật) từ PC bằng Git Bash:

```sh
TM_SERVER_HOST=root@192.168.1.192 TM_SERVER_PASS=<mật khẩu root> scripts/deploy-server.sh
```

Script làm các việc sau:

- gửi `server/` lên `/opt/tubemini/src` và build trên chính máy đó (binary khớp glibc của máy);
- cài `/opt/tubemini/tubemini-server`, tạo `/opt/tubemini/config.toml` nếu chưa có (sửa tay ở đó, deploy sau không ghi đè);
- tạo user hệ thống `tubemini`, unit systemd `tubemini`, và timer `tubemini-ytdlp-update` chạy `yt-dlp -U` mỗi ngày.

Xem log: `journalctl -u tubemini -f`. Khởi động lại: `systemctl restart tubemini`.
