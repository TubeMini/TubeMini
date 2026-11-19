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

## 7. Cài server trên Ubuntu: Docker hoặc service hệ thống

Một script `install.sh` cài theo một trong hai cách. Hai cách dùng chung cấu hình và dữ liệu ở `/opt/tubemini`, nên đổi cách không
mất kênh theo dõi hay lịch sử.

| | 1) Docker | 2) Service |
| --- | --- | --- |
| Chạy bằng | container (Docker; máy chỉ có Podman thì dùng Podman) | dịch vụ systemd `tubemini` |
| Cần cài thêm | Docker (script hỏi rồi cài `docker.io` nếu chưa có) | công cụ build, Rust, yt-dlp, Deno (script tự cài) |
| Lần đầu | khoảng 4 phút (build image) | 5–10 phút (build từ mã nguồn) |
| Tự khởi động cùng máy | có | có |
| Cập nhật yt-dlp | mỗi lần container chạy + mỗi ngày | mỗi ngày |
| Log | `docker logs -f tubemini` | `journalctl -u tubemini -f` |

Gói cài đặt: trên PC chạy `bash scripts/make-release.sh`, được `dist/tubemini-server-<phiên bản>.tar.gz` (khoảng 140 KB: mã nguồn
server, `install.sh`, `docker-compose.yml`, `HUONG-DAN.txt`). Chép sang máy Ubuntu rồi:

```sh
tar xzf tubemini-server-0.5.4.tar.gz && cd tubemini-server-0.5.4
sudo ./install.sh                     # hỏi: 1) Docker hay 2) Service, cổng (8080), mã truy cập
```

Không hỏi gì: `sudo ./install.sh --docker --yes` hoặc `sudo ./install.sh --service --port 8080 --token <mã> --yes`.
Trong thư mục repo thì chạy `sudo scripts/install.sh` cũng được.

- **Cập nhật:** giải nén bản mới, chạy lại `install.sh` (giữ `config.toml` và dữ liệu). Kiểu Docker tự xoá image cũ sau khi build.
- **Trạng thái:** `./install.sh --status`. **Gỡ:** `sudo ./install.sh --uninstall` (giữ dữ liệu), thêm `--purge` để xoá luôn.
- Cấu hình: `/opt/tubemini/config.toml` (sửa xong thì chạy lại `install.sh`, hoặc `systemctl restart tubemini` /
  `docker restart tubemini`). Dữ liệu: `/opt/tubemini/data/tubemini.db` (SQLite). Muốn giữ thì sao lưu file này.
- Kiểu Docker dùng mạng của máy (`--network host`), nên mDNS chạy được: app tìm thấy máy chủ trong mạng nhà.

**Máy chủ hiện tại (LXC 192.168.1.192)** cài kiểu service. Cập nhật từ PC bằng Git Bash:

```sh
TM_SERVER_HOST=root@192.168.1.192 TM_SERVER_PASS=<mật khẩu root> scripts/deploy-server.sh
```

Script gửi `server/` và `install.sh` sang máy đó, rồi chạy `install.sh --service --yes`.

**Windows / macOS (Docker Desktop):** ở thư mục repo (hoặc thư mục giải nén), chạy `docker compose up -d --build`. Dữ liệu nằm ở
`./tubemini-data`. Trên Windows cũng có thể chạy thẳng `tubemini-server.exe` (mục 1). Trên Windows, file dữ liệu nằm trong thư mục
`data` cạnh `config.toml`.

## 8. Xem ngoài mạng nhà (4G, Wi-Fi khác)

Link googlevideo mà server lấy được **gắn với IP công cộng của nhà** (Giai đoạn 0, D7). Ở ngoài mạng nhà, iPad có IP khác nên có thể
bị từ chối (phép thử 4G anh sẽ làm sau). Có hai cách:

**Cách 1 — VPN về nhà (khuyên dùng).** iPad đi Internet qua mạng nhà, nên link vẫn hợp lệ, không phải sửa gì ở server hay app.

- iOS 6 có sẵn VPN loại **L2TP/IPsec**, **Cisco IPSec** (IKEv1) và PPTP (cũ, không an toàn). Không có WireGuard; ứng dụng OpenVPN
  bây giờ cũng không còn bản cho iOS 6.
- Nhiều router gia đình có sẵn máy chủ L2TP/IPsec (mục VPN Server). Nếu router không có thì cài SoftEther VPN Server (hỗ trợ
  L2TP/IPsec) trên máy LXC, rồi mở cổng UDP 500 và 4500 trên router.
- Trên iPad: Cài đặt → Cài đặt chung → VPN → Thêm cấu hình VPN → L2TP, điền máy chủ (IP công cộng hoặc tên DDNS của nhà), tài
  khoản, mật khẩu, khóa bí mật chung, và bật "Gửi mọi lưu lượng". Bật VPN rồi dùng TubeMini với đúng địa chỉ
  `http://192.168.1.192:8080` như ở nhà.

**Cách 2 — proxy dự phòng của server.** Video đi qua server (tốn băng thông tải lên của mạng nhà: 720p khoảng 2,5 Mbit/s).

1. Trên máy .192, sửa `/opt/tubemini/config.toml`: `proxy_fallback = true`, và **đặt `auth_token`** (một chuỗi dài, ngẫu nhiên),
   rồi `systemctl restart tubemini`.
2. Trên router, chuyển cổng TCP 8080 vào 192.168.1.192:8080. Nên có tên DDNS cho IP nhà.
3. Trên iPad (TubeMini → Cài đặt): địa chỉ `http://<IP công cộng hoặc DDNS>:8080`, nhập mã truy cập, bật **"Phát qua máy chủ"**,
   rồi bấm "Kiểm tra kết nối": phải thấy "Phát qua máy chủ: máy chủ cho phép".

Lưu ý: mã truy cập chỉ bảo vệ `/tm/v1`. Lớp GData (tìm kiếm, trang chủ cho app cũ) vẫn mở, còn `/proxy` chỉ nhận URL có chữ ký do
server sinh. Vì vậy cách 1 an toàn hơn. Nếu phép thử 4G cho thấy link dùng được từ IP khác, thì chỉ cần chuyển cổng, không cần bật
proxy.

## 9. Triển khai lên VPS

VPS chạy Ubuntu thì cài như mục 7, **có mã truy cập**: `sudo ./install.sh --docker --token <mã dài, ngẫu nhiên> --yes`.
VPS khác (hoặc chỉ có Docker): `docker compose up -d --build`, rồi sửa `./tubemini-data/config.toml` và `docker compose restart`.

- Image gồm tubemini-server, yt-dlp (bản chạy độc lập) và Deno, cho CPU x86_64 và ARM64. Mỗi lần container khởi động thì yt-dlp
  tự cập nhật.
- **Bắt buộc đặt `auth_token`** khi server ra Internet.
- Link đi theo quốc gia của server: nên thuê VPS ở Việt Nam để video không bị chặn theo vùng. IP trung tâm dữ liệu cũng dễ bị
  YouTube đòi xác minh "không phải bot" hơn IP nhà, nên yt-dlp có thể lỗi thường xuyên hơn.
- Link gắn với IP của VPS. Nếu phép thử 4G cho thấy link không dùng được từ IP khác, thì phải bật `proxy_fallback = true`, và app
  bật "Phát qua máy chủ" (tốn băng thông VPS).
- **HTTPS và iOS 6:** chứng chỉ Let's Encrypt **không chạy** trên iOS 6, vì máy không có gốc ISRG Root X1 (mới có từ 2015).
  Muốn HTTPS thì cần chứng chỉ nối tới một gốc mà iOS 6 tin (ví dụ GlobalSign Root CA R1, DigiCert Global Root CA). Em chưa thử
  cách này. Cách đơn giản hơn: VPS chạy HTTP + mã truy cập, và iPad vào qua VPN (dựng L2TP/IPsec trên chính VPS).
- Đã thử cả hai cách trên máy thật (D30): service trên máy LXC .192, Docker bằng Podman trên máy build Ubuntu 26.04.

## 10. Phát hành bản mới (app, server, Cydia, OTA)

1. Tăng phiên bản: `server/Cargo.toml`, `ios/TubeMini/control` (`Version:`), `ios/TubeMini/Resources/Info.plist`
   (`CFBundleShortVersionString`, `CFBundleVersion`). Commit, đẩy lên GitHub.
2. Build bản release của app: `TM_BUILD_HOST=<user>@<máy build> scripts/ios-build.sh FINALPACKAGE=1`, được
   `ios/TubeMini/packages/vn.tubemini.io_<phiên bản>_iphoneos-arm.deb` (không có lệnh debug). Chép vào `dist/`.
3. Gói server: `bash scripts/make-release.sh`, được `dist/tubemini-server-<phiên bản>.tar.gz`.
4. GitHub Release: `gh release create v<phiên bản> dist/<file .deb> dist/<file .tar.gz> --repo TubeMini/TubeMini --notes "…"`.
5. Trang + Cydia + OTA: `bash scripts/publish-site.sh dist/<file .deb> --notes "Có gì mới"`. Script chép `site/` sang repo
   `TubeMini/TubeMini.github.io`, thêm gói vào `cydia/debs` (giữ các bản cũ), tạo lại `Packages`, `Release` và `update.json`.
   Vài phút sau, app trên các iPad tự báo có bản mới (mỗi ngày kiểm tra một lần, hoặc bấm Cài đặt → Kiểm tra cập nhật). Bấm
   Cập nhật: app tải `.deb`, kiểm SHA-256, cài bằng `/usr/libexec/tubemini/tmupdate` rồi respring.

Commit lên GitHub phải dùng email ẩn danh `…@users.noreply.github.com` (repo đã cấu hình sẵn; `publish-site.sh` cũng dùng nó).
Đừng tạo commit bằng giao diện web hay `gh repo create --add-readme`: GitHub sẽ ghi tên và email thật của tài khoản.
