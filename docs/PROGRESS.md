# Tiến độ

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
