# Quyết định kỹ thuật

Mỗi mục ghi: quyết định, lý do, bằng chứng (nếu có). Mới nhất ở cuối.

## D1. Giấy phép: GPL-3.0 — 15/11/2026

- Toàn dự án phát hành theo **GPL-3.0** (`LICENSE`).
- Lý do: lớp GData phải trả XML khớp gần như từng thẻ với server TubeRepair (GPL-3.0). Theo GPL thì được chép template có ghi
  nguồn, đỡ phải chứng minh là "viết lại sạch". Dự án dùng cá nhân / gia đình nên GPL không gây vướng mắc gì.
- Template hoặc đoạn code nào chép từ TubeRepair (`https://github.com/kevinf100/tuberepair.uptimetrackers.com`, nhánh `blueprint`)
  phải ghi nguồn ngay đầu file.

## D2. Build app trên máy Ubuntu thử nghiệm thay cho WSL2 — 15/11/2026

- Máy Windows chưa cài WSL2. Anh có sẵn máy ảo Ubuntu 26.04 (`~/TestLab`), Theos đã cài từ dự án ConBangTV_Legacy.
- Toolchain: Theos + toolchain iOS cho Linux của L1ghtmann (clang 11, ld64-609) + SDK **iPhoneOS 9.3** (bản cuối còn armv7),
  **đã vá cho iOS 6** bằng `scripts/setup-theos.sh` (chép từ ConBangTV_Legacy). Không vá thì app chết trên iOS 6 với lỗi
  `dyld: Symbol not found` (NSURLConnection nằm trong Foundation trên iOS 6, còn SDK 9.3 ghi là CFNetwork).
- Bắt buộc: ký `ldid -S -Hsha1` (nhân iOS 6 chỉ hiểu SHA-1) và `.deb` nén **gzip** (dpkg của iOS 6 không đọc được xz hay zstd).
- Build từ Windows: `scripts/ios-build.sh` gửi mã nguồn sang máy Ubuntu qua SSH, gọi `make package`, kiểm tra binary rồi kéo
  `.deb` về `ios/TubeMini/packages/`.

## D3. App YouTube cũ dùng làm mốc: bản 1.3.0 — 15/11/2026

- Tài liệu dự án ghi 1.2.1, nhưng trong `ipa tham khao/` chỉ có **YouTube 1.3.0** (iOS 5.0 trở lên, armv7) và **YouTube 10.11**
  (iOS 6.0 trở lên). README của TubeRepair chỉ nêu 1.1.0 và 1.2.1.
- Cả hai binary đều **đã giải mã** (`cryptid = 0`), nên cài được lên máy jailbreak.
- Chọn 1.3.0 làm app cũ để kiểm thử lớp GData. Bản 10.11 dùng InnerTube chứ không dùng GData, nên **để ngoài phạm vi**.
- Còn phải kiểm chứng (Giai đoạn 1): tweak TubeRepair có chạy với 1.3.0 không. Nếu không thì tìm bản 1.2.1.

## D4. Tải trực tiếp từ Google trên iOS 6: ĐẠT — 15/11/2026

Đây là rủi ro số một (mục 3.2 của tài liệu dự án). Thử trên iPad mini 1 (iPad2,7, iOS 6.1.3):

| Phép thử | Kết quả |
| --- | --- |
| `i.ytimg.com` (ảnh JPEG) qua NSURLConnection | HTTP 200 |
| `googlevideo.com` format 18, tải trọn file | HTTP 200, 629 KB, khoảng 1,1 giây |
| MPMoviePlayer phát format 18 (Big Buck Bunny, 10 phút) | phát sau khoảng 1,3 giây, 640×360, không khựng |
| Tua tới giây 300 và giây 420 | mất khoảng 0,2 giây; khung hình giải mã đúng cảnh |

- Chuỗi chứng chỉ Google đang gửi: lá ← WR2/WE2 ← GTS Root R1/R4 ← **GlobalSign Root CA** (chứng chỉ ký chéo). GlobalSign Root
  CA có sẵn trong kho gốc của iOS 6, nên máy iOS 6 nguyên bản cũng sẽ tin được.
- **Mốc rủi ro: chứng chỉ ký chéo GTS Root R1/R4 ← GlobalSign hết hạn ngày 28/01/2028.** Sau ngày đó, máy iOS 6 không có gốc GTS
  sẽ báo lỗi chứng chỉ. iPad thử nghiệm có cài thêm một hồ sơ cấu hình chứa nhiều gốc mới (ngày 14/11/2026). Cần kiểm tra hồ sơ
  đó có GTS Root R1/R4 không, vì đó là cách xử lý cho sau năm 2028.
- Chưa thử: iPad ở mạng khác (4G). Xem D5.

## D5. Cách xin link video — 15/11/2026 (sơ bộ, chốt ở spike Giai đoạn 1)

- `yt-dlp 2026.10.26 --force-ipv4 -g -f 18` cùng Deno 2.9.8 chạy tốt. Mất khoảng 4 giây mỗi link, client là `c=TVHTML5`, link có
  `ip=` là IP công cộng IPv4 của nhà và hạn khoảng 6 giờ.
- **Cách của TubeRepair (gọi InnerTube trực tiếp bằng client IOS/ANDROID) đã hỏng:** phản hồi `player` không còn `streamingData`
  (chạy thử bản cuối của TubeRepair, commit `df7846f`, ngày 15/11/2026). Vì vậy không nên viết lại cách đó. Spike ở Giai đoạn 1 sẽ
  so sánh các `player_client` của yt-dlp, kể cả phép thử "khác IP".
- Gợi ý cho phép thử khác IP: ngoài cách cho iPad bắt 4G, có thể thử qua proxy Shadowsocks của anh (IP khác IP nhà), nếu anh đồng ý.

## D6. HLS của YouTube phát được trên iOS 6 — 15/11/2026 (sơ bộ, làm kỹ ở Giai đoạn 2)

- Manifest master (`manifest.googlevideo.com/api/manifest/hls_variant/...`) gồm các biến thể avc1 + vp09, **tiếng tách riêng**
  (`EXT-X-MEDIA TYPE=AUDIO`, itag 233/234). Không có `#EXT-X-MAP`, tức **không phải fMP4**.
- Segment hình: **MPEG-TS** (byte đồng bộ 0x47 mỗi 188 byte; ffprobe: `mpegts`, h264 1280×720). Segment tiếng: packed AAC có thẻ
  ID3 `com.apple.streaming.transportStreamTimestamp`.
- MPMoviePlayer trên iOS 6.1.3 phát thẳng manifest master chưa lọc: chạy, tua tới giây 420 được, và tự bỏ qua các biến thể VP9.
- Còn phải kiểm ở Giai đoạn 2: có tiếng không (phải nghe thật), 720p **60fps** có mượt trên A5 không, và lọc chỉ giữ avc1 ≤ `res`.

## D7. Không dựa vào Invidious; mốc TubeRepair hiện không dùng được — 15/11/2026

- Đã dựng TubeRepair bản cuối (repo bị archive ngày 21/04/2026) trên máy Ubuntu, `http://192.168.1.101:4000`, chạy bằng
  `systemd-run --user --unit=tuberepair`.
- Kết quả: trang chủ, tìm kiếm, liên quan, kênh, video của kênh, `/getvideo` và `/720/getvideo` đều trả 500. **Chỉ bình luận còn
  chạy.** Nguyên nhân: Invidious mặc định (`inv.nadeko.net`) đã tắt API ("Endpoint disabled", 403), và InnerTube IOS/ANDROID không
  còn trả link (D5).
- Hệ quả: so sánh XML (mục 4.7 của tài liệu dự án) phải dựa vào **template trong mã nguồn** TubeRepair và phản hồi bình luận còn
  chạy, chứ không so được với server công khai.

## D8. Không cần API key của Google — 15/11/2026

- TubeRepair chỉ gắn sẵn **key InnerTube công khai** (key mà trang web YouTube nào cũng gửi), không phải key người dùng tạo trên
  Google Cloud Console. yt-dlp và rustypipe cũng không cần key.
- Không dùng YouTube Data API v3 (có hạn mức, cần key, và không trả link video).

## D9. rustypipe: phải đánh giá kỹ ở Giai đoạn 1 — 15/11/2026

- Bản mới nhất trên crates.io là **0.11.4, ra ngày 23/04/2025**, tức đã khoảng 19 tháng. InnerTube đổi liên tục, nên khả năng
  cao một phần đã hỏng.
- Thứ tự dự phòng: rustypipe (nếu còn chạy) → yt-dlp cho metadata (chậm hơn, bù bằng cache) → tự viết client InnerTube nhỏ dựa
  trên code của yt-dlp (không tự bịa endpoint).

## D10. Kiểm thử tự động trên iPad qua SSH — 15/11/2026

- Bản debug của TubeMini (`make package`, khi không có `FINALPACKAGE=1`) đọc lệnh từ `/var/mobile/Documents/TubeMini-cmd.txt`
  (`play`, `seek`, `status`, `frame`, `shot`, `net`, `wait`, `mark`) và ghi log vào `TubeMini.log`. Nhờ vậy em tự thử được trên
  máy thật mà không cần chạm màn hình.
- Dùng lại các công cụ ConBangTV đã cài trong `/usr/bin` của iPad: `cblaunch` (mở app), `cbsymcheck` (tra ký hiệu thiếu trên
  iOS 6), `cbnettest` (tải bằng NSURLConnection).
- Giới hạn: `UIGetScreenImage` không chụp được lớp video của MPMoviePlayer (ra màn đen), nên lệnh `frame` lấy khung hình qua
  `thumbnailImageAtTime:`. Cách này chạy với MP4 progressive, không chạy với HLS.
