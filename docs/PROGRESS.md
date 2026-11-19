# Tiến độ

## Tình trạng hiện tại (cập nhật 20/11/2026)

Đã xong cả 6 giai đoạn (0–5) của tài liệu dự án, cùng các phần anh yêu cầu thêm. Chi tiết từng giai đoạn ở các mục bên dưới;
lý do kỹ thuật ở `DECISIONS.md` (D1–D38).

**Mới nhất: bản 0.6.0 (20/11/2026):** giao diện kiểu iOS 26 / YouTube (thanh tab kính nổi, nút tìm kiếm tròn tách riêng, thẻ
video lớn, Cài đặt dạng thẻ, hộp thoại tự vẽ) và app chạy từ iOS 5.0 đến iOS 8 (D38). Đã phát hành (GitHub, Cydia, OTA).

**Phiên bản:** app TubeMini và tubemini-server **0.6.0** (code server không đổi từ 0.5.0, chỉ đổi số phiên bản).

**Đã công khai**

| Thứ | Ở đâu |
| --- | --- |
| Mã nguồn (server + app + tài liệu), GPL-3.0 | https://github.com/TubeMini/TubeMini |
| Bản phát hành (`.deb` app + gói server) | v0.5.0 – v0.6.0: https://github.com/TubeMini/TubeMini/releases |
| Trang giới thiệu (Safari iOS 6 đọc được) | https://tubemini.github.io/ (repo `TubeMini/TubeMini.github.io`) |
| Nguồn Cydia | `https://tubemini.github.io/cydia/` |
| File cập nhật OTA cho app | https://tubemini.github.io/update.json |
| Trang tổ chức + `SUPPORT.md` chung | https://github.com/TubeMini (repo `TubeMini/.github`) |
| Nhóm Telegram | https://t.me/tivikit (@tivikit) |

**Đang chạy**

- iPad mini 1 (iOS 6.1.3): bản release 0.5.4 (app sẽ tự báo có bản 0.6.0). Bản release không có lệnh debug; muốn thử qua SSH
  thì cài lại bản debug (`scripts/ios-build.sh` không có `FINALPACKAGE=1`).
- iPhone 5 (iOS 6.1.4): cũng dùng TubeMini, bản 0.5.3 (app sẽ tự báo có bản 0.6.0).
- Máy demo cho giao diện mới: iPad mini 1 iOS 8.4.1 và iPad 1 iOS 5.1.1 chạy bản release 0.6.0 (lên bằng OTA từ bản debug); iPhone 5
  iOS 6.1.4 (máy đen) chạy 0.6.0 cài qua SSH.
- Server chính trong nhà: service systemd trên máy Ubuntu (cài bằng `install.sh`), vẫn là 0.5.0. Chưa cần cập nhật vì code server
  không đổi.

**Kiểm thử gần nhất:**
- `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings` sạch; `cargo test`: 74 đạt, 3 bỏ qua (code server không đổi
  từ đó).
- Phát nền trên iPad (D34, bấm Home giả bằng `cbscreen home`): video 5/5 lần phát tiếp ở nền; "Chỉ nghe" bấm Home ngay ở 4 thời
  điểm khác nhau, cả 4 đều có tiếng (ở nền, hoặc khi mở lại app nếu tiếng chưa kịp chạy).
- Trên iPhone 5 (D35): chụp và soát từng màn (Trang chủ lưới / danh sách, trang video, thanh "Chỉ nghe", Tìm kiếm, kênh,
  Lịch sử, mục "Thêm", Đã tải, Cài đặt) ở màn dọc và ngang, giao diện sáng và tối: app dùng hết màn 4 inch, không còn chữ đè
  hay bị cắt.
- Bản 0.6.0 (D38): chụp và soát mọi màn trên iPhone 5 iOS 6.1.4, iPad mini 1 iOS 8.4.1, iPad 1 iOS 5.1.1 (sáng / tối, dọc /
  ngang). OTA trọn vòng 0.5.4-1+debug → 0.6.0 từ trang đã đăng trên iOS 5 và iOS 8 (`dpkg exit 0`, respring, app chạy).
- Trên iPad: OTA trọn vòng 0.5.3-1+debug → 0.5.4 từ trang đã đăng (tải, kiểm SHA-256, `dpkg exit 0`, respring, app chạy, icon
  mới ở dock).

**Phát hành bản mới:** làm theo `SETUP.md` mục 10. Tóm tắt:
1. tăng phiên bản ở 3 chỗ;
2. `scripts/ios-build.sh FINALPACKAGE=1`;
3. `scripts/make-release.sh`;
4. `gh release create`;
5. `scripts/publish-site.sh <deb> --notes "…"`.

Commit lên GitHub luôn dùng email ẩn danh `…@users.noreply.github.com`.

**Tài liệu giới thiệu cho nhóm Telegram** (ảnh tóm tắt 2560×3160 + 2 tin nhắn): nằm ở `dist/telegram/` trên máy làm việc, không
có trong git.

**Còn mở**

- Phép thử 4G / IP khác (anh tự làm): quyết định có cần chế độ phát qua server khi ở ngoài nhà hay không.
- HTTPS cho iOS 6 chưa thử (Let's Encrypt không chạy được trên iOS 6).
- Không có tài khoản người dùng: mọi máy dùng chung server thì chung kênh theo dõi và lịch sử.
- Thứ tự feed giữa các kênh chỉ gần đúng (YouTube chỉ ghi "3 giờ trước", D26).
- App YouTube cũ chưa tự theo dõi kênh được (nút đăng ký cần đăng nhập Google).
- Trình phát vẫn là MPMoviePlayerViewController toàn màn hình.
- Tìm máy chủ trong mạng (Bonjour) chỉ chạy khi iPad và server cùng dải IP.

## Giai đoạn 0 — Dựng khung và kiểm chứng rủi ro (15/11/2026)

### Đã làm

- [x] Repo theo cấu trúc mục 8 của tài liệu dự án; giấy phép GPL-3.0 (D1).
- [x] Server Rust `tubemini-server` (edition 2024, axum):
  - đọc `config.toml` đặt cạnh exe, thiếu file thì dùng mặc định;
  - kiểm tra yt-dlp và deno lúc khởi động;
  - gọi yt-dlp có giới hạn số tiến trình (semaphore), timeout 30 giây, `CREATE_NO_WINDOW` trên Windows, `--force-ipv4`;
  - trang debug `/` và trang thử `/gd0`.
  - `cargo fmt`, `cargo clippy --all-targets -- -D warnings` và `cargo test` (9 test) đều sạch.
- [x] Cập nhật yt-dlp lên 2026.10.26 và cài Deno 2.9.8 trên PC.
- [x] `docs/SETUP.md`: hướng dẫn Theos, toolchain và SDK trên Linux (dùng máy Ubuntu thử nghiệm thay WSL2, D2).
- [x] App "Hello TubeMini":
  - Theos, `.deb` `vn.tubemini.io` 0.1.0, icon 72/144, `postinst` chạy `uicache`;
  - bản debug có phần nhận lệnh qua file để thử qua SSH (D10).
- [x] Script: `ios-build.sh` (build từ xa), `deploy.sh` (cài qua SSH), `setup-theos.sh`, `symlist.py`, `make-icons.py`.
- [x] Kiểm chứng tải trực tiếp trên iPad mini 1 iOS 6.1.3 (D4), thêm thử HLS (D6).
- [x] Dựng TubeRepair trên máy Ubuntu làm mốc: hiện gần như không chạy (D7).

### Kết quả nghiệm thu

| Tiêu chí | Kết quả |
| --- | --- |
| Cài `.deb` lên iPad, app mở được và hiện chữ | **Đạt.** Đã cài bằng `dpkg -i`, app mở bằng `cblaunch`, ảnh chụp màn hình hiện "Xin chào TubeMini · iOS 6.1.3 · iPad2,7" |
| Binary chỉ có slice armv7, phiên bản tối thiểu 6.0 | **Đạt.** `lipo -info`: armv7; `LC_VERSION_MIN_IPHONEOS`: version 6.0, sdk 9.3; `cbsymcheck`: 76 ký hiệu, thiếu 0 |
| Video format 18 từ googlevideo phát và tua được | **Đạt.** Tự kiểm bằng MPMoviePlayer trong app: phát ngay, tua tới giây 300/420 mất 0,2 giây, khung hình đúng cảnh |
| Ảnh `i.ytimg.com` hiện, không lỗi chứng chỉ | **Đạt.** NSURLConnection trả HTTP 200 (dùng cùng bộ TLS với Safari) |
| Thử khác mạng (4G) | **Chưa thử.** Cần anh làm trên máy thật, hoặc thử qua proxy (D5) |

### Anh kiểm tra bằng cách nào

1. Trên iPad: icon **TubeMini** (nền xanh, tam giác trắng) có trên màn hình chính, mở ra thấy "Xin chào TubeMini".
2. Trên Safari của iPad: vào `http://<IP PC>:8080/gd0` (cần mở cổng Firewall trước, xem SETUP mục 1.5), chọn video mẫu, xem ảnh
   có hiện không rồi bấm "Phát video" và thử tua.
3. Thử 4G: để nguyên trang `/gd0` đã mở, chuyển Wi-Fi iPad sang điểm phát 4G của điện thoại, bấm lại "Phát video", ghi lại
   kết quả.

### Còn tồn

- Cổng 8080 trên Windows Firewall chưa mở. Cần quyền Administrator; lệnh nằm ở SETUP mục 1.5.
- Chưa thử ở mạng 4G (chỉ ghi nhận, chưa bắt buộc đạt).
- Chưa cài app YouTube 1.3.0 và tweak TubeRepair lên iPad. Để sang Giai đoạn 1, vì server TubeRepair hiện không chạy (D7). iPad
  còn chưa có Cydia Substrate và AppSync.
- Mốc rủi ro TLS ngày 28/01/2028 (D4): cần kiểm tra hồ sơ cấu hình trên iPad có gốc GTS không.
- Còn phải xác nhận có tiếng khi phát HLS, và 720p60 có mượt không (D6, Giai đoạn 2).

## Giai đoạn 1 — Server: lớp GData tối thiểu (15/11/2026)

### Đã làm

- [x] Spike rustypipe: một phần đã hỏng với YouTube hiện tại, nên **tự viết client InnerTube nhỏ** (D11).
- [x] Trang chủ "phổ biến" lấy từ các trang chủ đề của YouTube, vì Trending đã bị bỏ (D12).
- [x] Spike xin link: chọn client mặc định của yt-dlp (D14). Phép thử khác IP **chưa làm** (xem phần còn tồn).
- [x] Route GData:
  - `categories.cat`, đăng nhập giả (`applelogin1/2`, `registerDevice`);
  - `standardfeeds` (trang chủ và từng danh mục);
  - tìm video (`orderby`, `time`, `duration`, `caption`, `start-index`, `max-results`, `continuation`);
  - video liên quan, video của kênh;
  - một video (`/feeds/api/videos/{id}`, `/feeds/player/videos/{id}`);
  - `/getvideo` (307 sang 360p; có tiền tố độ phân giải thì sang manifest HLS);
  - tiền tố `/{res}/` cho mọi route; gzip; cache metadata 30 phút, link 5 phút; `?fresh=1`.
- [x] Trang debug `/` có ô tìm kiếm và link tới các XML mẫu.
- [x] Test: 27 unit test (cách đọc chuỗi tiếng Việt/Anh, parser trên fixture thật, mã hóa bộ lọc tìm kiếm, tiền tố, link trang sau,
  snapshot XML bằng `insta` với tiêu đề có `& < > " '` và emoji); 2 test `#[ignore]` gọi YouTube thật; `scripts/smoke.ps1`
  (15 mục, đều qua). `cargo fmt` và `clippy -D warnings` sạch.
- [x] iPad: cài Substrate, PreferenceLoader, TubeRepair, AppSync, `ipainstaller` và YouTube 1.3.0 (SETUP mục 5). Thêm công cụ chụp màn
  hình `tmshot` (D16).

### Kết quả nghiệm thu (app YouTube 1.3.0 + TubeRepair, Custom URL `http://192.168.1.24:8080`)

| Tiêu chí | Kết quả |
| --- | --- |
| Trang chủ hiện video | **Đạt.** Ảnh chụp: 25 video, tiêu đề tiếng Việt, kênh, "4 days ago", lượt xem, ảnh từ i.ytimg.com, thời lượng |
| Mở video, phát 360p | **Đạt.** `/feeds/player/videos` → 200, liên quan → 200, `/getvideo` → 307. Hai ảnh chụp cách nhau 15 giây cho thấy video đang chạy, kèm cột "Suggested" |
| Tua | **Chưa thử trong app** (cần chạm màn hình). Trình phát và googlevideo giống hệt phép thử tua của Giai đoạn 0, khi đó đã đạt |
| Tìm kiếm trong app | **Chưa thử trong app** (cần gõ phím). Endpoint đã kiểm bằng curl và smoke test; XML dùng chung template với trang chủ và liên quan, hai phần app đã hiển thị đúng |
| Server gần như không có lưu lượng khi xem | **Đạt theo thiết kế.** Mỗi lần xem chỉ có một request `/getvideo` trả 307 (vài trăm byte), sau đó iPad tải thẳng từ googlevideo. Server không có đường nào chuyển tiếp dữ liệu video |
| iPad ở mạng 4G vẫn xem được | **Chưa thử.** Cần anh làm, hoặc cho phép em thử qua proxy (D14) |

### Anh kiểm tra bằng cách nào

1. Trên iPad mở app **YouTube** (đã trỏ sẵn về server PC). Xem trang chủ, rồi bấm ô tìm kiếm, gõ thử, ví dụ "nhạc trẻ", và cuộn xuống
   cuối để tải trang sau.
2. Mở một video, chờ phát, kéo thanh thời gian để tua.
3. Thử 4G: cho iPad bắt điểm phát 4G của điện thoại. Lúc đó iPad không vào được server trong LAN, nên mở sẵn một video khi còn ở
   Wi-Fi nhà, rồi chuyển mạng và bấm phát hoặc tua tiếp. Hoặc dùng trang `/gd0` như Giai đoạn 0.
4. Trên PC: `powershell -File scripts\smoke.ps1`.

### Còn tồn

- Tìm kiếm và tua **ngay trong app cũ** cần anh thử bằng tay (em không gõ hoặc chạm trên iPad được).
- Phép thử khác IP / 4G (D14).
- Bản dự phòng lấy metadata bằng yt-dlp (mục 4.1): để sang Giai đoạn 2.
- Route của Giai đoạn 2 mà app đang gọi: `/feeds/api/channels/{id}` (avatar kênh, app gọi mỗi kênh một lần), bình luận.
- RSS của YouTube hỏng (D13), nên Giai đoạn 4 sẽ dùng tab Videos thay cho RSS.

## Giai đoạn 2 — Server: hoàn thiện lớp GData (15/11/2026)

### Đã làm

- [x] **HLS 720p** qua tiền tố `/{res}/`: playlist master lọc cho iOS 6 (D20, API.md).
- [x] **Tìm kênh, thông tin kênh** (avatar JPEG `=s88`, số người đăng ký, số video), `/feeds/api/users/{id}`.
- [x] **Playlist**: playlist của kênh (đọc `params` của tab từ phản hồi), tìm playlist, video trong playlist.
- [x] **Bình luận** (định dạng mới `commentEntityPayload`, có dự phòng định dạng cũ), có phân trang.
- [x] **Phân biệt User-Agent**: app classic `YouTube v1.0.0` nhận feed classic. Thêm route `/video/sd/{id}`.
- [x] Phân trang `skip`: trang YouTube dài (playlist 100 video, kênh 30 video) không còn bị mất mục.
- [x] **Sửa "Playback error"** ở video có quảng cáo đầu: chờ tới mốc `available_at`, lấy link trước, gộp các lần lấy trùng (D17).
- [x] Dự phòng metadata bằng yt-dlp (D19, chuyển từ Giai đoạn 1).
- [x] Log mỗi request có User-Agent rút gọn, để biết app nào đang gọi.
- [x] Đo tốc độ yt-dlp trên PC, máy ảo Ubuntu và máy LXC 192.168.1.192 (D18). Chuyển TubeRepair sang máy LXC (cổng 4000, systemd).
- [x] TubeMini (bản debug): thêm lệnh `avplay` / `avstatus` để kiểm track hình và tiếng của HLS.
- [x] Test: 44 unit test (bộ lọc HLS trên 2 manifest thật, parser kênh / tìm kênh / playlist / bình luận trên fixture thật, phân
  trang `skip`, feed classic, nhánh dự phòng) và 3 test `#[ignore]` gọi YouTube thật đều qua. `smoke.ps1`: 23/23 mục.

### Kết quả nghiệm thu

| Tiêu chí | Kết quả |
| --- | --- |
| Custom URL `/720`, phát 720p ổn định | **Đạt.** App YouTube 1.3.0 phát HLS 720p (ảnh chụp). Trình phát iOS chạy biến thể 1280×720, tua tới giây 1800, không khựng, có track tiếng |
| Video có quảng cáo phát được | **Đạt** (sau khi sửa D17). Despacito và Gangnam Style phát ngay lần đầu, cả trong app YouTube lẫn trình phát iOS |
| Avatar và số người đăng ký của kênh | **Đạt.** Ảnh chụp trang video có avatar kênh và "31.100 subscribers" |
| Bình luận, trang kênh, playlist của kênh, tìm kênh trong app | **Server đạt** (smoke test, XML hợp lệ). Hiển thị trong app cần anh bấm thử, vì em không chạm màn hình được |
| App classic (iPad 1 iOS 5) | **Server đạt:** app gọi tới và nhận feed classic. Phần hiển thị cần anh xem |
| So với server TubeRepair công khai | TubeRepair hiện hỏng gần hết (D7). Server nhà làm được mọi màn hình mà TubeRepair từng hỗ trợ, cộng thêm trang video theo ID (1.3.0), lọc 60fps, chờ quảng cáo |

### Anh kiểm tra bằng cách nào

1. iPad mini: app YouTube đang trỏ về `http://192.168.1.24:8080/720` (HD). Mở vài video (nhất là video nhạc có quảng cáo), bấm tab
   **Comments**, bấm vào tên kênh để xem trang kênh và tab playlist, tìm thử kênh. Muốn về 360p thì sửa Custom URL trong Cài đặt →
   TubeRepair, bỏ `/720`, rồi tắt hẳn app YouTube.
2. iPad 1 (iOS 5): mở app YouTube có sẵn, xem trang chủ có video không và mở thử một video.
3. Trên PC: `powershell -File scripts\smoke.ps1`.

### Còn tồn

- Các màn hình cần chạm (bình luận, trang kênh, playlist, tìm kênh) chưa được em tự kiểm trong app, chỉ kiểm phía server.
- Video có quảng cáo phải chờ khoảng 7–8 giây trước khi phát (giới hạn của YouTube, D17/D18).
- 720p60 bị bỏ (giống TubeRepair). Có thể thử bật sau nếu A5 chạy mượt.
- Phép thử khác IP / 4G: anh làm sau.

## Giai đoạn 3 — App TubeMini MVP (15/11/2026)

### Đã làm

- [x] Server: `/tm/v1/ping`, `/tm/v1/videos/{id}/streams` (có `available_in`), token `X-Auth-Token`, lỗi `tm:error` tiếng Việt
  (API.md). Server lên 0.3.0.
- [x] Server chính chuyển lên máy LXC 192.168.1.192 (systemd, tự cập nhật yt-dlp mỗi ngày, D21). App YouTube cũ trên iPad cũng trỏ về
  đó.
- [x] App TubeMini 0.3.0:
  - `TMAPIClient`, `TMAtomParser`, `TMExtParser`, `TMImageLoader`, `TMPlayer`;
  - các tab Trang chủ (phổ biến), Tìm kiếm (Video / Kênh, cuộn vô hạn), Cài đặt (máy chủ, mã truy cập, chất lượng mặc định, kiểm
    tra kết nối);
  - màn Chi tiết video: ảnh lớn, nút phát, chọn chất lượng, video của kênh, mô tả, video liên quan / bình luận;
  - mở kênh: danh sách video của kênh.
- [x] Debug: lệnh điều khiển giao diện cho thử nghiệm tự động (D22).

### Kết quả nghiệm thu trên iPad mini 1 (iOS 6.1.3)

| Tiêu chí | Kết quả |
| --- | --- |
| Lần đầu mở app | Vào tab Cài đặt kèm lời chào. "Kiểm tra kết nối": "Kết nối tốt — Máy chủ TubeMini 0.3.0, yt-dlp 2026.10.26, Deno: có" |
| Tìm kiếm | "nhạc trẻ" ra 20 video, cuộn tới cuối tải tiếp: 40, rồi 58 (ảnh chụp: ảnh, thời lượng, kênh · lượt xem · ngày) |
| Mở video → phát | Bấm Phát: phát 360p sau khoảng 0,4 giây (link đã có trong cache), toàn màn hình |
| Tua | Tua tới giây 150; video chạy tiếp tới giây 168 (theo log) |
| Phát 720p (HLS) | Phát biến thể 720p (2,49 Mbps), không khựng. Video có quảng cáo: màn chờ "Đang lấy link phát…" khoảng 7–8 giây rồi phát |
| Tìm kênh → trang kênh → video | "vtv" ra 20 kênh; mở VTV24 ra 25 video; mở video được |
| Bình luận | Big Buck Bunny: 20, cuộn tới cuối thành 40; bình luận dài tự xuống dòng |
| Bộ nhớ | 8,9 MB lúc mở; 14,7 MB sau 97 kết quả tìm kiếm; 16,4 MB sau thêm trang video và 50 mục trang chủ (lệnh `mem`) |
| Không crash | Không có báo cáo crash trong `CrashReporter` |
| Cuộn danh sách không giật | Ảnh giải nén ở luồng nền và cache theo cỡ hiển thị. Độ mượt cần anh cảm nhận trực tiếp |

### Anh kiểm tra bằng cách nào

1. Mở **TubeMini** trên iPad. App đã trỏ về `http://192.168.1.192:8080`. Nếu cài mới thì vào Cài đặt nhập địa chỉ và bấm "Kiểm tra
   kết nối".
2. Tìm thử, cuộn nhanh danh sách, mở video, bấm Phát, tua. Đổi "Chất lượng" sang 720p rồi phát lại (video có quảng cáo sẽ hiện đếm
   ngược).
3. Trên màn video: chuyển sang "Bình luận", bấm "Video của kênh". Ở tab Tìm kiếm chọn "Kênh" rồi tìm thử một kênh.
4. Xoay ngang / dọc ở các màn.

### Còn tồn

- Trình phát dùng MPMoviePlayerViewController toàn màn hình, chưa có trình phát nhúng trong trang.
- Chưa có lịch sử / xem tiếp, theo dõi kênh, trang kênh đầy đủ (Giai đoạn 4).
- API iOS 7+ giờ là lỗi build (D24); riêng `UISearchBar.keyboardAppearance` không bị bắt.

### Bổ sung sau Giai đoạn 3 (anh yêu cầu, 15/11/2026)

- [x] **Tiếng gốc thay cho lồng tiếng AI** (D23): video tiếng Việt không còn phát tiếng Anh.
- [x] **Giao diện tối** (Cài đặt → Giao diện: Sáng / Tối), áp cho mọi màn (D24).
- [x] **Trang chủ dạng lưới**: công tắc "Danh sách | Lưới", 3–4 cột, tải thêm khi cuộn (D24).
- [x] Sửa hai lỗi crash do API iOS 7+, và bật cờ biên dịch để chặn loại lỗi này từ lúc build.

Đã kiểm trên iPad (ảnh chụp):
- lưới 4 cột khi ngang, cả sáng lẫn tối;
- giao diện tối ở Trang chủ, Tìm kiếm (video, kênh), trang kênh, Chi tiết video, Cài đặt;
- chuyển qua lại Lưới / Danh sách và Sáng / Tối không crash;
- RAM khoảng 10–12 MB.
- [x] **Thông báo "Đang lấy link phát…" xoay theo màn hình** (anh báo bị ngược khi cầm ngang): HUD gắn vào view của root view
  controller thay vì gắn thẳng vào `UIWindow` (trên iOS 6 view gắn thẳng vào window không xoay). Đã kiểm bằng ảnh chụp khi ngang.
- [x] **Chất lượng 1080p** (D25): Cài đặt và nút "Chất lượng" có 360p / 720p / 1080p; `streams` trả thêm mục HLS 1080.
  Đã kiểm trên iPad: bản tin HTV 1920x1080 (avc1.640028, 25 fps) phát mượt, 0 lần giật, 0 khung bị rớt, RAM 13.6 MB.


## Giai đoạn 4 — Tính năng mở rộng (15/11/2026)

### Đã làm

- [x] Server 0.4.0 (API.md):
  - lưu dữ liệu người dùng bằng SQLite (`rusqlite`, bản `bundled`) trong `<data_dir>/tubemini.db`;
  - `/tm/v1/subscriptions`: xem, theo dõi, bỏ theo dõi kênh;
  - `/tm/v1/feed`: video mới của các kênh đã theo dõi, lấy từ tab Video của từng kênh rồi gộp lại (RSS đã chết, D26);
    `fresh=1` tải lại mọi kênh;
  - `/tm/v1/history`: lịch sử xem và vị trí đang xem, xoá một mục hoặc xoá hết; giữ 500 video gần nhất;
  - `home_feed = "subscriptions"`: trang chủ app YouTube cũ hiện video từ kênh đã theo dõi.
- [x] App TubeMini 0.4.0:
  - **Trang chủ**: công tắc "Đã theo dõi | Phổ biến" (nhớ lựa chọn), dạng danh sách hoặc lưới. Kéo xuống hoặc bấm nút làm mới thì
    server tải lại mọi kênh.
  - **Tab "Đã theo dõi"**: danh sách kênh; chạm để mở trang kênh, vuốt sang trái để bỏ theo dõi.
  - **Tab "Lịch sử"**: video đã xem, kèm "Đã xem 0:38 / 20:28" và thanh tiến độ đỏ; vuốt để xoá một mục, nút "Xoá hết".
  - **Trang kênh đầy đủ**: avatar, số người đăng ký, số video, mô tả (chạm để mở rộng), nút "+ Theo dõi" / "✓ Đã theo dõi",
    tab Video / Playlist; chạm playlist để xem video trong đó.
  - **Trang video**: thêm nút "Kênh" (mở trang kênh) và nút Theo dõi; nút Phát thành "▶ Xem tiếp 12:34" khi đã xem dở.
  - **Xem tiếp**: trình phát lưu vị trí 15 giây một lần, khi đóng và khi app chuyển nền; lần sau phát từ chỗ cũ (từ giây thứ 10
    tới 20 giây trước khi hết; ngoài khoảng đó thì phát từ đầu).
  - Chọn chất lượng 360p / 720p / 1080p (đã làm sau Giai đoạn 3, D25).
- [x] Test: 64 unit test server (lưu trữ SQLite, gộp feed, các route lịch sử / theo dõi chạy không cần mạng). `smoke.ps1` thêm 7
  kiểm tra `/tm/v1`: tổng 30, đều qua.

### Kết quả nghiệm thu trên iPad mini 1 (iOS 6.1.3)

| Tiêu chí | Kết quả |
| --- | --- |
| Theo dõi kênh | Theo dõi HTV Tin Tức, ANTV, VTV24: mỗi kênh khoảng 0,55 giây (server hỏi YouTube tên và avatar) |
| Feed trang chủ | 25 video mới của 3 kênh xen kẽ theo thời gian, có trang sau. Lần đầu 0,36 giây, lần sau 3 ms (cache) |
| Tab "Đã theo dõi" | 3 kênh, kèm avatar và số người đăng ký |
| Trang kênh | Avatar tròn, "413 N người đăng ký · 96 N video", mô tả; tab Playlist ra danh sách playlist kèm ảnh và số video |
| Theo dõi / bỏ theo dõi | Nút đổi "✓ Đã theo dõi" ↔ "+ Theo dõi" (đỏ); trang video và trang kênh cập nhật theo nhau |
| Xem tiếp | Phát 45 giây rồi đóng: nút thành "▶ Xem tiếp 0:38". Bấm: log "xem tiếp từ 38 giây", 15 giây sau ở giây 43,9 (HLS 1080p) |
| Lịch sử | "Đã xem 0:38 / 20:28 · vừa xong" kèm thanh tiến độ; vuốt xoá thì server cũng hết mục đó |
| App cũ, `home_feed = "subscriptions"` | YouTube 1.2.1 và app classic nhận feed "Kênh đã theo dõi"; feed Âm nhạc vẫn là phổ biến (thử trên một server phụ cổng 8099) |
| Giao diện sáng / tối, lưới | Đều đúng màu, kể cả nút Theo dõi |
| Bộ nhớ | 21 MB sau khi phát 1080p và mở nhiều trang có ảnh |
| Không crash | Không có báo cáo crash mới |

### Anh kiểm tra bằng cách nào

1. Mở TubeMini. Trang chủ có công tắc "Đã theo dõi | Phổ biến". Em đã theo dõi sẵn 3 kênh tin tức để thử; anh bỏ theo dõi được ở
   tab "Đã theo dõi" (vuốt sang trái).
2. Tìm một kênh (Tìm kiếm → Kênh), mở ra, bấm "+ Theo dõi", rồi về Trang chủ: video của kênh đó có trong feed. Kéo xuống để làm mới.
3. Mở một video, xem một lúc rồi bấm "Xong". Nút Phát thành "▶ Xem tiếp …". Bấm lại: phát tiếp từ chỗ cũ. Tab "Lịch sử" có video
   đó.
4. App YouTube cũ: muốn trang chủ hiện kênh đã theo dõi thì sửa `/opt/tubemini/config.toml` trên máy .192 thành
   `home_feed = "subscriptions"` rồi chạy `systemctl restart tubemini`. Hiện em để `popular` như cũ.

### Còn tồn

- Thứ tự feed giữa các kênh chỉ gần đúng: tab Video của YouTube chỉ ghi "3 giờ trước", không có giờ chính xác (D26).
- Không có tài khoản: mọi máy dùng chung server thì chung kênh theo dõi và lịch sử.
- App YouTube cũ chưa tự theo dõi kênh được (nút đăng ký của nó cần đăng nhập Google); chỉ xem được feed.
- Trình phát vẫn là MPMoviePlayerViewController toàn màn hình.

### Bổ sung sau Giai đoạn 4 (anh yêu cầu, 15/11/2026)

- [x] **Icon mới** (D27): bánh răng đồng gỉ sét (Rust), màn hình ống đỏ có nút play (một chút YouTube), chất liệu thật và lớp bóng
  kiểu iOS 6. Có đủ các cỡ 72 / 144 (màn hình chính), 50 / 100 (Spotlight), 29 / 58 (Cài đặt). Đã thấy trên màn hình chính iPad
  sau khi respring.
- [x] **Icon nền trong suốt** (anh yêu cầu): bỏ nền tối quanh bánh răng. Trên iPad, sau bánh răng vẫn thấy ô bóng mờ mà SpringBoard
  iOS 6 vẽ dưới mọi icon (D27); anh chọn giữ bản trong suốt.
- [x] **Icon nét hơn ở 72 px** (anh thấy "rỗ"): bỏ vân gỉ lấm tấm và nhiễu hạt, bỏ đinh tán ở cỡ nhỏ, thêm viền tối mảnh (D27).


## Giai đoạn 5 — Mở rộng (15/11/2026)

### Đã làm

- [x] Server 0.5.0 (API.md, D28):
  - `/getaudio/{id}`: HLS chỉ có tiếng (AAC 128k, track gốc);
  - `streams` có thêm `tm:audio` và `tm:download` (MP4 360p, kèm cờ lồng tiếng AI);
  - proxy dự phòng `proxy_fallback` (mặc định tắt): URL có chữ ký, chỉ chuyển tiếp googlevideo, hỗ trợ Range, viết lại playlist HLS;
  - quảng bá mDNS `_tubemini._tcp` (`mdns = true`);
  - `ping` báo proxy bật hay tắt;
  - `server/Dockerfile` để chạy trên VPS.
- [x] App TubeMini 0.5.0:
  - **"♫ Chỉ nghe"**: chỉ tải tiếng, vẫn phát khi khoá màn hình hoặc chuyển app; màn hình khoá có tiêu đề, kênh, ảnh, nút phát /
    dừng; trên màn trình phát hiện ảnh video.
  - **"⬇ Tải về"** và tab **"Đã tải"**: tải MP4 360p, hiện %, tải tiếp khi đứt mạng hoặc mở lại app; xem offline, xem tiếp từ chỗ cũ;
    vuốt để xoá; dòng tổng dung lượng.
  - **Cài đặt**: "Tìm máy chủ trong mạng" (Bonjour), "Phát qua máy chủ".
  - Trang video: 6 nút xếp hai hàng (Phát, Chỉ nghe, Chất lượng / Tải về, Kênh, Theo dõi).
- [x] **Thanh nghe nhạc thu nhỏ** (anh yêu cầu): "Chỉ nghe" phát ngầm, thanh trên thanh tab có tua, ↺15, ❚❚ / ►, 15↻, ✕, hiện ở
  mọi màn hình trong lúc lướt app. ⏮ / ⏭ trên màn hình khoá = lùi / tiến 15 giây (màn hình khoá iOS 6 không có thanh tiến trình).
- [x] Hướng dẫn xem ngoài mạng nhà (VPN L2TP/IPsec, hoặc proxy) và triển khai VPS: SETUP mục 8, 9.
- [x] Test: 73 unit test server (playlist chỉ tiếng, viết lại URL, chữ ký proxy, mDNS); `smoke.ps1` 33 kiểm tra, đều qua.

### Kết quả nghiệm thu trên iPad mini 1 (iOS 6.1.3)

| Tiêu chí | Kết quả |
| --- | --- |
| Chỉ nghe | Bitrate 144 kbit/s, không có hình. Thanh thu nhỏ: tua tới 600 giây có ngay, ↺15 về 584,7, dừng / phát được |
| Nghe khi chuyển app | Mở app Cài đặt của iPad: TubeMini vẫn phát (586,8 → 600,8 giây sau 14 giây); thanh trạng thái có ▶ |
| Màn hình khoá | Có tiêu đề, kênh, thời lượng, ảnh (`nowplaying`). Nút trên màn hình khoá cần anh thử bằng tay |
| Tải về | 95,7 MB trong khoảng 70 giây; nút hiện "⬇ 7%"; tab "Đã tải" ghi "tiếng lồng AI" cho bản tin có lồng tiếng |
| Xem offline | Phát từ file (không qua mạng), 640x360, cả 22 phút |
| Proxy | HLS 720p qua proxy, tua tới giây 300; app bật "Phát qua máy chủ": `serverAddress` là 192.168.1.192 |
| mDNS | PC nhận đủ bản ghi từ server. iPad không thấy vì khác mạng con (192.168.2.x / 192.168.1.x); app báo rõ |
| Không crash | Không có báo cáo crash mới |

### Anh kiểm tra bằng cách nào

1. Mở một video, bấm **"♫ Chỉ nghe"**: thanh thu nhỏ hiện trên thanh tab, quay ra lướt app tiếng vẫn chạy; kéo thanh để tua.
   Khoá màn hình: tiếng vẫn chạy; bấm Home hai lần trên màn hình khoá để dừng / phát, ⏮ / ⏭ để lùi / tiến 15 giây.
2. Bấm **"⬇ Tải về"**, chờ nút thành "✓ Đã tải". Bật chế độ máy bay, vào tab **"Đã tải"**, chạm video để xem offline.
3. Cài đặt → **"Tìm máy chủ trong mạng"**: ở mạng nhà anh sẽ báo không tìm thấy (khác dải IP). Nếu cắm Wi-Fi cùng dải với server
   thì sẽ tìm được.
4. Ở ngoài mạng nhà: làm theo SETUP mục 8 (VPN, hoặc bật proxy + mã truy cập + chuyển cổng).

### Còn tồn

- Phép thử 4G / IP khác (anh làm): quyết định có cần proxy khi ở ngoài nhà hay không.
- HTTPS cho iOS 6 chưa thử (Let's Encrypt không chạy được).
- ~~Chưa build thử Docker image~~, ~~video thường dừng khi app xuống nền~~, ~~bản tải chỉ có 360p~~: đã làm, xem phần bổ sung bên
  dưới.

### Bổ sung sau Giai đoạn 5 (anh yêu cầu, 15/11/2026)

- [x] **Video thường cũng phát tiếng khi app xuống nền / khoá màn hình** (D29). Đã thử: chuyển sang app Cài đặt, video vẫn chạy (giây
  12,8 → 23,6), quay lại thì hình chạy tiếp.
- [x] **Tải về chọn 360p / 720p / 1080p** (D29): bảng chọn ghi dung lượng ước tính. 720p / 1080p tải từng segment HLS, xem offline
  qua máy chủ HTTP nhỏ trong app. Video bị lồng tiếng AI có mục "360p (tiếng gốc)". Đã thử: bản tin 19 phút ở 720p tải trong 43 giây
  (94,5 MB), phát từ trong máy (127.0.0.1), tua tới giây 300 có ngay.
- [x] **Docker image** build thử bằng Podman trên máy build: chạy được; server giờ tắt êm khi nhận SIGTERM (`docker stop` 0,13
  giây thay vì 10 giây).
- [x] **Bản 0.5.1, nhóm Telegram** (D33): nhóm https://t.me/tivikit có trên README, trang giới thiệu (nút + ô có mã QR), trang
  mô tả trong Cydia, ghi chú phát hành, và trang tổ chức https://github.com/TubeMini (repo `TubeMini/.github`). App 0.5.1 có
  mục **Nhóm Telegram** trong Cài đặt (mã QR + @tivikit). Đã thử OTA trọn vòng 0.5.0 → 0.5.1 trên iPad (cài xong, respring,
  app chạy).
- [x] **Bản 0.5.2, sửa phát nền** (D34): xem video rồi bấm Home thỉnh thoảng mất tiếng trên iPad mini 1, vì iOS treo app trước
  khi lệnh phát lại kịp chạy. App giờ xin thêm thời gian chạy nền và phát lại tới khi tiếng chạy hẳn. "Chỉ nghe": iOS 6 không cho
  app ở nền bắt đầu phát, nên tiếng chưa kịp chạy lúc bấm Home thì sẽ phát khi mở lại app (trước đây có lúc im luôn).
- [x] **Bản 0.5.3, chạy đúng trên iPhone** (D35): trên iPhone 5 app chạy ở khung 3,5 inch có viền đen trên dưới, vì thiếu
  ảnh khởi động `Default-568h@2x.png`. Đã thêm ảnh đó, icon iPhone, khai báo app cho cả iPhone; sửa bố cục cho màn 320 điểm
  (thanh trên Trang chủ, nút trang video, thanh "Chỉ nghe", ảnh trong danh sách, chú thích trong Cài đặt) và mục "Thêm" theo
  giao diện tối. iPad không đổi (đã chụp lại các màn trên iPad để so).
- [x] **Spike chạy không server: giải mã link trên iPad** (D36): QuickJS build cho iOS 6 chạy đúng script giải mã của yt-dlp
  trên iPad mini 1. Xử lý player mới mất 90 giây (một lần mỗi phiên bản player); nạp lại từ bytecode đã lưu 0,45 giây; mỗi video
  21 ms. Anh quyết định không làm chế độ không server (không bền bằng dùng server).
- [x] **Bản 0.5.4, icon mới theo logo anh gửi** (D37): `scripts/make-icons.py` tạo mọi icon (app, README, trang web, Cydia)
  từ `art/TubeMini-logo.png`, nền quanh logo thành trong suốt. Đã phát hành (GitHub, Cydia, OTA); iPad lên 0.5.4 bằng OTA,
  icon mới hiện đúng ở dock.
- [x] **Bản 0.6.0, giao diện kiểu iOS 26 và chạy từ iOS 5** (D38): thanh tab kính nổi với nút Tìm kiếm tròn, thẻ video lớn như
  app YouTube, trang video / kênh / Cài đặt làm lại, hộp thoại và bảng chọn tự vẽ. Deployment target 5.0. Sửa lỗi thoát app trên
  iOS 6 (ảnh co giãn kiểu lát). Đã phát hành (GitHub, Cydia, OTA); trang web có ảnh chụp mới.
- [x] **Lên GitHub** (D31, D32): repo công khai https://github.com/TubeMini/TubeMini (lịch sử đã bỏ thông tin cá nhân),
  bundle id `vn.tubemini.io`, bản phát hành v0.5.0, trang https://tubemini.github.io/ (đọc được trên Safari iOS 6), nguồn
  Cydia `https://tubemini.github.io/cydia/`, cập nhật OTA trong app (tải, kiểm SHA-256, cài, respring). Đã thử OTA trọn vòng
  0.4.9 → 0.5.0 trên iPad.
- [x] **Cài trên Ubuntu bằng một script** (D30): `install.sh` cho chọn 1) Docker (Docker / Podman) hoặc 2) service systemd, tự khởi
  động cùng máy, tự cập nhật yt-dlp; cập nhật bằng cách chạy lại, có `--status`, `--uninstall [--purge]`. Gói phát hành
  `scripts/make-release.sh` (khoảng 140 KB), `docker-compose.yml` cho Windows / macOS. Đã thử service trên máy .192 (giữ nguyên
  cấu hình và dữ liệu), Docker bằng Podman trên máy build (cài, khởi động lại, cập nhật, gỡ sạch).
