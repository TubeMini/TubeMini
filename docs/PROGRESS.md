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
