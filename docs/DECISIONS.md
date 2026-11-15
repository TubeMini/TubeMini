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

- Đã dựng TubeRepair bản cuối (repo bị archive ngày 21/04/2026). Ban đầu chạy trên máy Ubuntu 192.168.1.101. Từ 15/11/2026, theo yêu cầu
  của anh, chuyển sang máy LXC `http://192.168.1.192:4000`, chạy bằng unit systemd `tuberepair` (`/opt/tuberepair`).
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

## D11. Metadata: tự viết client InnerTube nhỏ, bỏ rustypipe — 15/11/2026

Spike rustypipe 0.11.4 (chạy thật, vùng VN):

| Chức năng | Kết quả |
| --- | --- |
| Tìm kiếm + trang 2, chi tiết video, bình luận, tìm kênh, `channel_info` | chạy |
| Video liên quan, tab Videos của kênh | **chỉ có ID và tiêu đề**, mất thời lượng, lượt xem, ngày (YouTube chuyển sang `lockupViewModel`, rustypipe chưa đọc) |
| Số người đăng ký khi đặt `lang = vi` | sai (1.500 thay vì 1,26 triệu) |
| `trending` | hỏng (YouTube đã bỏ trang Trending; `FEtrending` trả 400) |
| `channel_rss`, `channel_playlists` | hỏng (RSS 404, playlist trả rỗng) |

- rustypipe gần như ngừng bảo trì: bản cuối ra 23/04/2025, sau đó chỉ có vài commit nhỏ.
- **Quyết định:** tự viết `src/youtube/innertube.rs`, khoảng 300 dòng, dùng client WEB.
  - Endpoint `search`, `next`, `browse`, `player`.
  - Phiên bản client `2.20260708.00.00` lấy từ yt-dlp 2026.10.26.
  - `params` của tab Videos và cách mã hóa bộ lọc tìm kiếm chép từ rustypipe.
  - Không tự bịa endpoint hay tham số nào.
- Cách đọc: dò sâu (deep scan) tìm `videoRenderer` / `lockupViewModel` ở bất kỳ đâu trong JSON, nên ít vỡ khi YouTube xếp lại bố cục.
- Ngôn ngữ: đọc được chuỗi tiếng Việt ("164.638 lượt xem", "6,9 Tr", "4 ngày trước") và tiếng Anh.
- Khi YouTube đổi: sửa `parse.rs`. Fixture trong `server/tests/fixtures/` là phản hồi thật đã rút gọn; test `#[ignore]` gọi YouTube thật.
- Bản dự phòng lấy metadata bằng yt-dlp (mục 4.1 của tài liệu dự án): **chưa làm**, để sang Giai đoạn 2.

## D12. Trang chủ "phổ biến" lấy từ các trang chủ đề của YouTube — 15/11/2026

- YouTube đã bỏ Trending. Thay vào đó dùng các kênh chủ đề ("Explore") với `gl=VN`: Âm nhạc (`UC-9-kyTW8ZkZNDHQJ6FgpwQ`), Tin tức
  (`UCYfdidRxbB8Qhf0Nx7ioOYw`), Thể thao (`UCEgdi0XIXXZ-qJOFPf4JSKw`), Trò chơi (`UCOpNcN46UbXVtpKMrmU4Abg`).
- `most_popular` trộn xen kẽ Âm nhạc, Tin tức, Thể thao (khoảng 25 video). Các feed `most_popular_<Danh mục>` lấy đúng trang chủ đề
  tương ứng.
- Nếu trang chủ đề trống (Trò chơi ở VN đang trống, Phim không có trang riêng) thì tìm kiếm "phổ biến trong tuần" theo từ khóa.
- `categories.cat` thêm News và Sports so với bản của TubeRepair.

## D13. RSS kênh của YouTube đang hỏng (404) — 15/11/2026

- `https://www.youtube.com/feeds/videos.xml?channel_id=...` trả 404 (đã thử nhiều lần, nhiều kênh).
- Giai đoạn 4 (feed kênh đã theo dõi) **không dựa vào RSS được** như tài liệu dự án dự tính. Thay bằng tab Videos qua InnerTube (đã có:
  `channel_uploads`), có cache.

## D14. Spike xin link (cùng IP) — 15/11/2026

`yt-dlp --force-ipv4 -J --extractor-args youtube:player_client=<X>`, thử với 2 video:

| player_client | format 18 | HLS | Thời gian |
| --- | --- | --- | --- |
| mặc định (link ghi `c=TVHTML5`) | có | có | khoảng 4 giây |
| `web_embedded` | có | có | khoảng 4 giây |
| `android_vr`, `mweb`, `tv_simply` | có | không | 2,5–4 giây |
| `web`, `web_safari`, `ios` | không có định dạng nào (cần PO token) | — | — |
| `tv` (một mình) | lỗi "The page needs to be reloaded" | — | — |

- **Chọn mặc định của yt-dlp:** có cả 360p lẫn HLS, và yt-dlp tự cập nhật thứ tự client khi YouTube đổi.
- **Chưa thử khác IP.** PC không có IPv6 để thử theo cách IPv4/IPv6. Thử qua proxy Shadowsocks bị hệ thống chặn, cần anh cho phép rõ
  ràng. Còn lại là phép thử 4G trên iPad.

## D15. App YouTube 1.3.0 chạy được với tweak TubeRepair và server của mình — 15/11/2026

- Đã cài trên iPad: Cydia Substrate 0.9.6301 + Safe Mode, PreferenceLoader 2.2.6, TubeRepair 1.2-Beta-1 (repo cydia.skyglow.es),
  AppSync Unified 116.0, IPA Installer Console 3.4.1, rồi YouTube 1.3.0 (nguồn và checksum ở `docs/SETUP.md` mục 5).
- Hướng dẫn chính thức của TubeRepair chỉ hỗ trợ 1.0.0–1.2.1, nhưng 1.3.0 vẫn chạy với server này:
  - trang chủ, trang video, danh sách liên quan, phát 360p đều chạy (có ảnh chụp);
  - lý do: 1.3.0 gọi thêm `/feeds/player/videos/{id}` khi mở video, route mà TubeRepair không có.
- iPhone 5 (iOS 6.1.4) đang có YouTube **1.4.0**, không phải 1.2.1.
- App gọi `/feeds/api/channels/{id}` cho từng kênh (để lấy avatar) và `/api/videos/{id}/comments`. Hai route này thuộc Giai đoạn 2.

## D16. Công cụ chụp màn hình qua SSH: `tmshot` — 15/11/2026

- `ios/tools/tmshot` (cài vào `/usr/bin` của iPad) gọi `CARenderServerRenderDisplay` + IOSurface, tra bằng `dlsym`. Cách này chụp
  được mọi app đang ở trước, **kể cả khung hình video**, không như `UIGetScreenImage` trong app (D10).

## D17. Video có quảng cáo đầu: phải chờ YouTube mở link — 15/11/2026

- Triệu chứng: app YouTube cũ báo "Playback error" với nhiều video nhạc. Riêng Big Buck Bunny thì chạy.
- Nguyên nhân: video có quảng cáo đầu (pre-roll) thì googlevideo trả **403** cho tới khi quảng cáo lẽ ra đã hết, hoặc tới lúc được bấm
  "bỏ qua". yt-dlp tính thời điểm đó từ `adPlacements` / `adSlots` trong phản hồi player (`_get_available_at_timestamp` trong
  `yt_dlp/extractor/youtube/_video.py`) và ghi vào trường `available_at` của từng định dạng. yt-dlp tự chờ khi tải về, nhưng `-J` hay
  `-g` thì không chờ.
- Đo được: với video có quảng cáo, link format 18 hợp lệ từ khoảng **8 giây** sau lúc bắt đầu chạy yt-dlp. Video không có quảng cáo thì
  dùng được ngay.
- Cách sửa:
  - `/getvideo` giữ request tới đúng `available_at` (cộng 0,3 giây, tối đa 30 giây) rồi mới trả 307 hoặc playlist;
  - server lấy link trước ở chế độ chạy nền khi app mở trang video (`/feeds/player/videos/{id}`, liên quan);
  - các lần lấy link trùng nhau cho cùng một video dùng chung một lần chạy yt-dlp.
- Đã kiểm chứng trên iPad: cả trình phát iOS lẫn app YouTube 1.3.0 đều phát được video có quảng cáo ngay lần đầu.
- `/tm/v1/videos/{id}/streams` (Giai đoạn 3) phải trả cả `available_at` để app TubeMini tự chờ.

## D18. Tốc độ yt-dlp: đổi máy không giúp được — 15/11/2026

| Máy | Khởi động `yt-dlp --version` | Lấy link một video |
| --- | --- | --- |
| PC Windows (yt-dlp.exe) | 1,17 s | 3,9–4,4 s |
| Máy ảo Ubuntu 192.168.1.101 (CPU ảo, không AVX) | 0,74 s | 4,2–4,9 s |
| LXC 192.168.1.192 (Xeon E-2176M, 2 nhân) | 0,66 s | 4,5–5,0 s |

Thời gian một lần lấy link (đo trên LXC, tổng 4,5 giây):

| Bước | Thời gian |
| --- | --- |
| Khởi động Python | 1,06 s |
| Trang xem video | 0,8 s |
| Gọi API player (2 client) | 0,6 s |
| Tải lại file JS của player | 0,37 s |
| Deno giải JS challenge | 1,17 s |
| Thông tin m3u8 | 0,4 s |

- Phần lớn là các lượt gọi mạng tới YouTube và Deno, nên đổi máy không nhanh hơn.
- Với video có quảng cáo, mốc mở link tính từ lúc gọi API player (D17). Vì vậy dù yt-dlp nhanh hơn thì tổng thời gian chờ vẫn khoảng 7–8
  giây.
- Hướng có thể làm sau nếu cần: bỏ bước m3u8 khi chỉ cần 360p (`youtube:skip=hls`), hoặc giữ một tiến trình yt-dlp chạy sẵn để bỏ khâu
  khởi động.

## D19. Dự phòng metadata bằng yt-dlp — 15/11/2026

- `src/youtube/fallback.rs`: dùng InnerTube trước; nếu lỗi **hoặc trang đầu trả về rỗng** thì chuyển sang
  `yt-dlp --flat-playlist -J`. Trang rỗng là dấu hiệu thường gặp khi YouTube đổi bố cục làm bộ đọc không còn tìm thấy gì.
- Phủ được: tìm kiếm (`ytsearchN:`), một video (`-J`), video của kênh (tab `/videos`), playlist. Mỗi trang 20 mục, token trang sau
  dạng `ytdlp:<start>`. Không có ngày đăng, bỏ qua bộ lọc tìm kiếm, và chậm hơn (vài giây mỗi lần).
- Không phủ (vẫn chỉ dùng InnerTube): video liên quan, trang chủ, kênh, playlist của kênh, bình luận.

## D20. HLS cho iOS 6 và app classic — 15/11/2026

- `/{res}/getvideo` trả playlist đã lọc (D6, API.md). Đã kiểm trên iPad:
  - trình phát iOS chạy biến thể 1280×720 avc1 24fps, tua tới giây 1800 được, không khựng;
  - AVPlayer báo có cả track hình lẫn track tiếng;
  - app YouTube 1.3.0 với Custom URL `…/720` phát HLS 720p.
- Bỏ biến thể trên 30fps như TubeRepair, nên video chỉ có 720p60 (Big Buck Bunny) sẽ xuống 480p30. Chưa thử 720p60 trên A5.
- App classic (iPad 1, iOS 5.1.1, `Apple iPad v5.1.1 YouTube v1.0.0.9B206`): đã cài tweak TubeRepair. App gọi đăng nhập giả rồi
  `/feeds/api/standardfeeds/US/recently_featured`, server trả feed định dạng classic (200). `tmshot` không chạy trên iOS 5 (build iOS
  6 dùng `LC_MAIN`), nên phần hiển thị cần anh xem trực tiếp.

## D21. Server chính chuyển lên máy LXC 192.168.1.192 — 15/11/2026

- Theo yêu cầu của anh, server chạy 24/7 trên máy LXC (Ubuntu 24.04) bằng systemd, nên không cần bật PC.
- Build ngay trên máy đích (`scripts/deploy-server.sh`) thay vì build chéo: tránh lệch glibc (máy ảo build là Ubuntu 26.04) và tránh
  phải dựng toolchain musl.
- Tốc độ yt-dlp trên máy này ngang PC (D18).
- App YouTube cũ trên iPad mini (Custom URL `http://192.168.1.192:8080/720`) đã phát được video có quảng cáo ở 720p qua máy này.
- Server TubeRepair làm mốc cũng ở máy này (cổng 4000, D7).

## D22. App TubeMini (Giai đoạn 3): cách làm chính — 15/11/2026

- **Dùng lại lớp GData:** mọi danh sách (phổ biến, tìm video, tìm kênh, liên quan, bình luận, video của kênh) đọc XML GData của
  server bằng một bộ đọc duy nhất `TMAtomParser`, kiểu SAX trên NSXMLParser. Loại entry nhận theo `category` kind. Thẻ nào thiếu thì
  giữ giá trị mặc định; XML hỏng giữa chừng thì trả các entry đã đọc được.
- **Phát:** gọi `/tm/v1/videos/{id}/streams` ngay trước khi phát.
  - `available_in` > 0 thì hiện đếm ngược "Video có quảng cáo: YouTube cho phát sau N giây…" (chạm để huỷ).
  - Lỗi phát lần đầu thì gọi lại với `fresh=1` ngay trong trình phát đang mở. Lỗi lần nữa thì hỏi "Thử 360p?".
  - App tự xử lý sự kiện kết thúc: bỏ observer mặc định của MPMoviePlayerViewController, vốn tự đóng trình phát cả khi lỗi.
- **Ảnh:** NSCache 150 ảnh / 8 MB (xoá khi máy báo thiếu bộ nhớ) cùng cache đĩa `Library/Caches/TMImages`, dọn ảnh quá 7 ngày. Ảnh
  được giải nén ở luồng nền theo đúng cỡ hiển thị. URL gắn vào từng image view để cell tái sử dụng không bị nhảy ảnh.
- **Bẫy iOS 6 đã gặp:** `keyboardDismissMode` chỉ có từ iOS 7; kiểu lỗi này qua được bước link (`cbsymcheck`) nhưng crash khi chạy.
  Trước mỗi lần build phải grep danh sách API iOS 7+ (xem PROGRESS).
- **Tự thử trên máy thật:** bản debug nhận lệnh điều khiển giao diện qua `Documents/TubeMini-cmd.txt` (`server`, `search`, `open`,
  `playbtn`, `section`, `scrollend`, `pingtest`, `ui`… — xem `TMDebug.h`). Kết hợp với `tmshot` để chụp màn hình, em tự đi được luồng
  tìm → mở → phát → tua.

## D23. Lồng tiếng AI của YouTube: luôn phát tiếng gốc — 15/11/2026

- Anh phát hiện khi thử: video tiếng Việt (bản tin VTV) lại phát ra **tiếng Anh**.
- Nguyên nhân: YouTube tự lồng tiếng AI cho nhiều video ("American English - dubbed-auto").
  - Trong HLS, track lồng tiếng đứng đầu nhóm; cả hai track đều `DEFAULT=NO, AUTOSELECT=YES`, nên iPad tự chọn tiếng Anh.
  - MP4 360p (format 18) trộn sẵn **tiếng Anh** (`language: en`, trong khi video là `vi`): yt-dlp xin link với `hl=en`, nên YouTube
    chọn bản lồng tiếng.
- Cách sửa, chỉ phía server:
  - bộ lọc HLS giữ một track tiếng mỗi nhóm, ưu tiên track gốc (NAME chứa "original"), rồi tới track không phải lồng tiếng, rồi
    `DEFAULT=YES`, rồi track đầu. Track được giữ bị ép `DEFAULT=YES, AUTOSELECT=YES`;
  - nếu ngôn ngữ tiếng của MP4 khác ngôn ngữ track gốc (định dạng yt-dlp ghi "original", nếu không có thì lấy `language` của video),
    thì 360p chuyển sang HLS 360p tiếng gốc: cả `/getvideo` không tiền tố (app cũ) lẫn `streams` (TubeMini).
- Đã kiểm trên iPad: playlist 360p / 720p của bản tin chỉ còn "Tiếng Việt - original"; AVPlayer báo có track tiếng.
- Video không có bản lồng tiếng vẫn dùng MP4 360p như trước.

## D24. Giao diện tối, Trang chủ dạng lưới, chặn API iOS 7+ ngay lúc build — 15/11/2026

- **Giao diện tối** (anh yêu cầu): iOS 6 không có dark mode của hệ thống, nên app tự quản một bộ màu sáng / tối (`TMTheme`),
  chọn trong Cài đặt → Giao diện.
  - Màu áp qua appearance proxy (thanh điều hướng, thanh tab, ô tìm kiếm, công tắc phân mục) và tô lại các thanh đang hiện.
  - Đổi giao diện thì phát `TMThemeDidChangeNotification`; mọi màn tô lại và reloadData ngay, không cần mở lại app.
  - Bàn phím tối (`UIKeyboardAppearanceAlert`). Nút dùng kiểu tự vẽ, vì nút rounded-rect của iOS 6 luôn trắng. Công tắc phân mục
    phải là kiểu `Bar` mới nhận màu.
- **Trang chủ dạng lưới** (anh yêu cầu): `UICollectionView` (có từ iOS 6), 3 cột khi dọc, 4 cột khi ngang; công tắc
  "Danh sách | Lưới" trên thanh điều hướng, app nhớ lựa chọn; nút làm mới.
  - iOS 6 không có `willDisplayCell` cho collection view, nên tải thêm dựa vào `scrollViewDidScroll`.
- **Ba lỗi crash do API iOS 7+** trong một ngày (`keyboardDismissMode`, `UICollectionViewController.collectionViewLayout`,
  `UISearchBar.keyboardAppearance`):
  - Hai lỗi sau làm app crash khi mở (đã bật chế độ lưới) và khi tìm kiếm ở giao diện tối. Anh gặp đúng lỗi này ("App bị bug").
  - Đọc báo cáo crash trong `/var/mobile/Library/Logs/CrashReporter/` rồi dịch địa chỉ bằng `llvm-symbolizer` với file dSYM của
    Theos (`.theos/obj/debug/armv7/TubeMini.app/TubeMini.dSYM`). Địa chỉ trong file = địa chỉ khi crash − base nạp + `0x4000`.
  - **Từ nay build với `-Werror=unguarded-availability -Werror=partial-availability`:** header SDK 9.3 có ghi chú phiên bản, nên
    dùng API mới hơn iOS 6.0 là build lỗi luôn. Đã thử: bắt được `collectionViewLayout`, `keyboardDismissMode`, `containsString`.
    **Không bắt được** `UISearchBar.keyboardAppearance` (SDK không ghi chú), nên vẫn phải nhớ thủ công.

## D25. Thêm chất lượng 1080p — 15/11/2026

- Anh yêu cầu. Theo thông số của Apple, iPad mini 1 (chip A5) giải mã được H.264 tới 1080p 30 fps, High Profile level 4.1.
  Biến thể 1080p avc1 của YouTube là `avc1.640028` (High 4.0), nằm trong giới hạn đó.
  - Bản 1080p60 là `avc1.64002A` (level 4.2, quá sức A5), đã bị bộ lọc ≤ 30 fps loại sẵn.
- `streams` trả hai mức HLS: 720 và 1080. Hai mục cùng độ phân giải thật thì chỉ giữ một, sắp xếp tăng dần.
  - Video chỉ có 1080p60 thì không có mục 1080.
  - Server tải master playlist của YouTube một lần rồi lọc cho từng mức.
- App chọn mục cao nhất không vượt mức người dùng chọn; không có mục nào như vậy thì lấy mục thấp nhất.
  - Cách chọn này cũng sửa một lỗi cũ: video bị lồng tiếng AI (360p là HLS) mà chọn 720p thì app lại lấy mục HLS 360 đầu tiên.
- Màn hình iPad mini chỉ 1024x768, nên 1080p nhìn chỉ nét hơn 720p một chút, mà tốn khoảng 4–5 Mbit/s. Vì vậy mặc định vẫn là 360p.
- Với HLS, `naturalSize` của MPMoviePlayerController trên iOS 6 luôn báo 853x480 (cả với biến thể 360p lẫn 720p). Muốn biết đang
  phát biến thể nào thì xem `indicatedBitrate` trong access log rồi so với BANDWIDTH của playlist.
- App YouTube cũ: tiền tố `/1080/...` đã chạy được từ trước (`res` được kẹp trong 144–2160).

## D26. Theo dõi kênh, feed, lịch sử: lưu trên server, feed lấy từ tab Video — 15/11/2026

- **Lưu trữ:** SQLite (`rusqlite` bản `bundled`, đúng brief) trong `<data_dir>/tubemini.db`, hai bảng `subscriptions` và
  `history`. Không có tài khoản: server trong nhà, một hai người dùng.
  - rusqlite chạy đồng bộ, nên mọi lệnh chạy trong `spawn_blocking`, sau một mutex.
  - Lịch sử giữ 500 video gần nhất.
  - Danh sách kênh sắp theo tên đã bỏ dấu tiếng Việt, để "Âm nhạc" đứng cạnh chữ "a".
- **Feed:** brief định dùng RSS của từng kênh, nhưng RSS của YouTube đã ngừng chạy (thử ở Giai đoạn 2). Thay vào đó:
  - lấy trang đầu tab Video của từng kênh (khoảng 30 video, không gồm Shorts và livestream), 4 kênh cùng lúc;
  - gộp lại, sắp mới nhất trước, giữ tối đa 300 video;
  - tab Video chỉ có thời gian tương đối ("3 giờ trước"), nên thứ tự giữa các kênh chỉ gần đúng. Phép sắp xếp ổn định (stable
    sort), nên trong cùng một kênh vẫn giữ đúng thứ tự của YouTube.
  - Cache: mỗi kênh 30 phút (cache có sẵn của InnerTube), cả feed đã gộp 10 phút. Theo dõi / bỏ theo dõi thì feed gộp được dựng lại.
  - `fresh=1` bỏ cache của mọi kênh. Thêm hàm `forget_uploads` vào trait `MetadataProvider`, mặc định không làm gì.
  - Link "trang sau" bỏ tham số `fresh`, để cuộn tiếp không tải lại mọi kênh.
- **Lịch sử:** app gửi kèm tiêu đề, kênh và thời lượng. Nếu thiếu tiêu đề thì server tự hỏi YouTube một lần, lúc video mới vào lịch
  sử.
- **Xem tiếp:**
  - trình phát lưu vị trí lúc bắt đầu phát, 15 giây một lần, khi đóng (nút "Xong") và khi app chuyển nền;
  - xem hết thì lưu bằng thời lượng, nên lần sau phát từ đầu;
  - xem tiếp khi vị trí từ 10 giây tới 20 giây trước khi hết;
  - `MPMoviePlayerController.initialPlaybackTime` chạy được với HLS trên iOS 6: thử từ giây 38, phát tiếp đúng chỗ;
  - khi thử lại sau lỗi phát hoặc chuyển sang 360p, cũng phát tiếp từ vị trí cuối.
- **App:** `TMLibrary` nhớ ID các kênh đã theo dõi trong NSUserDefaults, để nút Theo dõi hiện đúng ngay, và đồng bộ với server lúc
  mở app và lúc mở tab "Đã theo dõi".
  - Hai thông báo `TMSubscriptionsDidChangeNotification` và `TMHistoryDidChangeNotification` giúp các màn tự cập nhật: trang video
    đổi "Xem tiếp" ngay khi đóng trình phát, không cần hỏi lại server.
- **App YouTube cũ:** `home_feed = "subscriptions"` áp cho các feed không có hậu tố danh mục (`most_popular`, `recently_featured`…).
  Chưa theo dõi kênh nào hoặc feed lỗi thì vẫn trả feed phổ biến.

## D27. Icon app: bánh răng gỉ sét + màn hình ống đỏ, phong cách iOS 6 — 15/11/2026

- Anh yêu cầu icon hợp tên TubeMini, mang phong cách iOS 6, phong cách Rust và một chút YouTube:
  - **Rust:** bánh răng 12 răng bằng đồng, có vân gỉ (mảng xỉn và vảy cam) và 4 đinh tán;
  - **YouTube:** màn hình đỏ bo góc với nút play trắng. Chỉ gợi nhớ, không chép logo YouTube hay Rust;
  - **iOS 6:** chất liệu thật, kim loại tiện tròn có ánh phản chiếu, viền vát sáng ở trên trái và tối ở dưới phải, đổ bóng, phản
    chiếu trên mặt kính CRT, lớp bóng cong cổ điển trên cả icon;
  - "Tube" + "Mini": một chiếc TV ống nhỏ.
- `scripts/make-icons.py` vẽ bằng Python thuần (không Pillow, không trình render SVG; cài thêm công cụ trên PC bị chặn). Mọi hình là
  signed distance field, nên viền mịn và mỗi cỡ được vẽ trực tiếp, không bị mờ do thu nhỏ. Vẽ hết các cỡ mất khoảng 15 giây.
- **Nền trong suốt** (anh yêu cầu bỏ viền tối): chỉ còn bánh răng và bóng đổ mềm, thu nhỏ 6% để bóng không bị cắt. Màu ghép trên nền
  đen (ra màu premultiplied) rồi chia cho alpha. `UIPrerenderedIcon = true` giữ nguyên, để iOS không phủ thêm lớp bóng của nó.
  - SpringBoard iOS 6 luôn vẽ một ô bóng tối mờ (bo góc) dưới mọi icon app. Icon đặc che nó, icon trong suốt thì lộ ra. Không tắt
    được nếu không có theme / tweak. Em đưa anh ba phương án (trong suốt, nhôm xước sáng, xanh trời); anh chọn giữ trong suốt.
    Hai nền kia vẫn vẽ được: `python scripts/make-icons.py --background silver` (hoặc `sky`).
  - Bản trước có nền xanh thép và góc bo vẽ sẵn: SpringBoard để icon cũ của app này (cài bằng `.deb`) vuông góc.
- **Làm sạch cho cỡ 72 px** (anh thấy icon "rỗ", không nét): iPad mini 1 hiển thị icon đúng 72×72, nên các chi tiết nhỏ hơn 2–3 px
  thành hạt lấm tấm. Đã bỏ nhiễu hạt từng điểm ảnh và vảy gỉ nhỏ, chỉ giữ vài mảng xỉn lớn và nhạt; bỏ đinh tán ở cỡ nhỏ hơn 100 px;
  thêm viền tối mảnh 1 px quanh bánh răng để mép sắc trên mọi hình nền; giảm ánh phản chiếu để đồng không bị chói.
- Đổi icon xong, `uicache` chưa đủ: SpringBoard giữ icon trong bộ nhớ, phải respring (`killall SpringBoard`).

## D28. Giai đoạn 5: chỉ nghe, tải về, proxy dự phòng, mDNS, VPS — 15/11/2026

- **Chỉ nghe:** playlist HLS có một biến thể chỉ tiếng, trỏ tới rendition tiếng của YouTube: AAC-LC 128k (itag 234), track gốc.
  - Segment là AAC đóng gói có thẻ ID3 ("packed audio"), đúng định dạng Apple dùng cho HLS chỉ có tiếng, nên iOS 6 phát được.
  - Không dùng itag 140 (m4a): đó là MP4 phân mảnh kiểu DASH, chưa chắc iOS 6 phát được.
  - App: phiên âm thanh `AVAudioSessionCategoryPlayback` + `UIBackgroundModes = audio`, nên vẫn phát khi khoá màn hình hoặc chuyển
    app. Màn hình khoá hiện tiêu đề, kênh, ảnh (`MPNowPlayingInfoCenter`); nút phát / dừng ở màn hình khoá và tai nghe chuyển tới
    trình phát.
  - Chế độ video thì vẫn tạm dừng khi app xuống nền (MPMoviePlayerController làm vậy với video). Muốn nghe nền thì dùng "Chỉ nghe".
  - **Thanh nghe nhạc thu nhỏ** (anh hỏi cách tua / dừng khi rời trình phát): "Chỉ nghe" giờ dùng AVPlayer chạy ngầm
    (`TMAudioPlayer`), không mở trình phát toàn màn hình. Thanh nằm trên thanh tab ở mọi màn hình, có:
    - thanh tua kéo được, ảnh, tên bài, thời gian;
    - nút ↺15, ❚❚ / ►, 15↻, ✕;
    - chạm tên bài để mở trang video.

    Thanh gắn vào view của tab bar controller (view xoay theo màn hình trên iOS 6). Các danh sách được chừa khoảng trống phía dưới
    để hàng cuối không bị che.
  - **Màn hình khoá iOS 6 không có thanh tiến trình** (anh đã thử: không thấy). Thanh này chỉ có từ iOS 7; kéo để tua trên màn
    hình khoá phải iOS 9.1 (`MPRemoteCommandCenter`). Trên iOS 6, màn hình khoá và thanh đa nhiệm có ⏮ / ▶ / ⏭: app gán ⏮ / ⏭
    thành lùi / tiến 15 giây.
  - Ký tự "▶" bị iOS 6 đổi thành emoji ô vuông xanh, nên nút trên thanh thu nhỏ dùng "►".
- **Tải về:** chỉ MP4 360p (progressive). HLS không lưu để xem offline được trên iOS 6 nếu không có máy chủ HTTP nội bộ trong app.
  - Tải từng video một bằng NSURLConnection, ghi thẳng ra file. Đứt mạng thì tải tiếp bằng `Range` (thử lại 3 lần). googlevideo
    trả 403/410 thì xin link mới (`streams?fresh=1`).
  - App xuống nền thì tải tiếp trong thời gian iOS cho (khoảng 10 phút); hết giờ thì tạm dừng, mở app lại thì tải tiếp.
  - File nằm trong `Documents/TubeMini-Downloads`, có đánh dấu không sao lưu lên iCloud / iTunes.
  - Khi MP4 mang tiếng lồng AI (D23), bản tải ghi rõ "tiếng lồng AI", vì không thể ghép tiếng gốc khi không có ffmpeg.
  - Mỗi bản tải nhớ vị trí xem riêng, nên xem tiếp được cả khi không có mạng.
- **Proxy dự phòng** (`proxy_fallback`, mặc định tắt):
  - URL `/proxy/<chữ ký>/<base64url>.<đuôi>`. Chữ ký là SipHash với khóa ngẫu nhiên mỗi lần server khởi động (lấy từ
    `RandomState` có sẵn trong thư viện chuẩn, không cần thêm crate). Chỉ nhận đích `https://*.googlevideo.com`.
  - Chuyển tiếp `Range`, trả `206`. Playlist con được viết lại để segment cũng qua proxy.
  - Server quyết định "có phải playlist không" theo `Content-Type` của Google, để không bao giờ đọc một segment nhị phân như văn
    bản. Test bắt được đúng lỗi này: segment có đường dẫn tương đối nằm trên host `manifest.`.
  - Lớp nén gzip bỏ qua `video/*`, `audio/*` và `application/octet-stream` (googlevideo ghi segment HLS là octet-stream).
  - Client proxy không có timeout tổng (video dài), chỉ có timeout kết nối và timeout đọc.
  - Đã kiểm trên iPad: HLS 720p qua proxy, tua tới giây 300; app bật "Phát qua máy chủ" thì phát được với `serverAddress` là
    server.
- **mDNS:** tự viết bộ trả lời tối giản (khoảng 250 dòng, đọc / ghi bản ghi DNS, có xử lý nén tên) thay vì dùng crate
  `mdns-sd` (kéo theo vài crate nữa). Chỉ cần thêm `socket2` (tokio vốn đã dùng) để mở cổng 5353 dùng chung với dịch vụ mDNS của
  hệ điều hành.
  - Kiểm từ PC: nhận đủ PTR, SRV, TXT, A.
  - **Mạng nhà anh:** iPad ở `192.168.2.x`, còn server và PC ở `192.168.1.x/24`, khác mạng con. Router không chuyển tiếp mDNS, nên
    iPad không tự tìm thấy server; app báo rõ lý do. Mạng nhà chỉ có một dải IP thì sẽ tìm được.
- **VPS:** có `server/Dockerfile`. Chứng chỉ Let's Encrypt không chạy trên iOS 6 (thiếu gốc ISRG Root X1), nên khuyên dùng VPN.

## D29. Video phát tiếp khi xuống nền; tải về 720p / 1080p bằng HLS — 15/11/2026

- **Video ở nền:** iOS dừng MPMoviePlayerController có hình khi app rời màn hình. App đã có phiên âm thanh "playback" và
  `UIBackgroundModes = audio`, nên chỉ cần ghi lại "đang phát" ở `willResignActive`, rồi gọi `play` lại sau khoảng 0,3 giây
  (ở `didEnterBackground`, hoặc khi trình phát bị dừng trong vòng 1,5 giây sau khi app mất focus, trường hợp khoá màn hình). Tiếng
  chạy tiếp, hình không vẽ; quay lại app thì hình chạy tiếp. Lần tạm dừng do người dùng về sau không bị đè.
- **Tải 720p / 1080p:** YouTube không còn MP4 liền mạch trên 360p, chỉ có HLS (segment MPEG-TS hình + AAC tiếng tách riêng).
  Không dùng ffmpeg, và video vẫn không đi qua server:
  - app lấy playlist master đã lọc của server cho mức đó, rồi playlist hình / tiếng trên googlevideo;
  - tải hết segment (3 cái cùng lúc, ghi file tạm rồi đổi tên, nên không có segment dở dang), viết `master.m3u8`, `video.m3u8` và
    `audio.m3u8` trỏ tới file trong máy;
  - link hết hạn (403) thì xin playlist mới: cùng segment, cùng thứ tự, tải tiếp đúng chỗ; mở lại app thì bỏ qua segment đã có.
  - iOS 6 không phát HLS từ `file://`, nên app có **máy chủ HTTP nhỏ** (`TMLocalServer`, socket BSD + GCD, chỉ `127.0.0.1`, chỉ
    file trong thư mục tải về, có Range). Trình phát đọc qua đó y như từ googlevideo.
  - Dung lượng ước tính = BANDWIDTH × thời lượng × 0,55 (BANDWIDTH là đỉnh; đo thực tế: 720p ước 190 MB, thật 94,5 MB). App kiểm
    chỗ trống trước khi tải, chừa 300 MB.
  - Video có MP4 lồng tiếng AI thì 360p tải bằng HLS để có tiếng gốc.
  - Lỗi bắt được khi thử: playlist tiếng đánh số segment tiếp theo playlist hình (`a/00205.ts`) trong khi file là `a/00000.ts`.
- **Docker:** build thử bằng Podman trên máy build: image 247 MB, chạy được. Lỗi tìm ra: server làm PID 1 trong container chỉ xử lý
  Ctrl+C, nên `docker stop` phải đợi 10 giây rồi giết; nay xử lý cả SIGTERM. Đã xoá image thử, giữ nguyên image của dự án khác.
- Một lần em sửa template bằng script Python mở file ở chế độ ghi trước khi đọc, làm `streams.xml` rỗng; `INSTA_UPDATE=always` còn
  ghi snapshot rỗng theo. Clippy (trường không dùng) phát hiện, đã khôi phục từ git. Từ nay đọc xong mới ghi.

## D30. Cài server trên Ubuntu bằng một script: Docker hoặc service — 15/11/2026

- Anh muốn người dùng chọn một trong hai cách và cài nhanh bằng một script trên Ubuntu. Có `scripts/install.sh`:
  - menu chọn 1) Docker / 2) Service, hỏi cổng và mã truy cập; có cờ để cài không cần hỏi, `--status`, `--uninstall [--purge]`;
  - chạy lại là cập nhật, giữ `config.toml` và dữ liệu. Hai cách dùng chung `/opt/tubemini`; cài cách này thì tắt cách kia để
    trả cổng.
  - **Docker:** dùng Docker nếu có; máy chỉ có Podman thì dùng Podman với một unit systemd riêng (`tubemini-container`); không có gì
    thì hỏi rồi cài `docker.io` từ kho Ubuntu. Container dùng mạng của máy (`--network host`): không cần ánh xạ cổng, và mDNS tới
    được mạng nhà. Hẹn giờ hằng ngày chạy `yt-dlp -U` trong container. Dockerfile chọn bản yt-dlp / Deno theo CPU (x86_64, ARM64).
  - **Service:** cài những gì thiếu (công cụ build, Rust, yt-dlp, Deno), build trong `/opt/tubemini/src` (giữ cache build giữa
    các lần cập nhật), unit `tubemini` + hẹn giờ cập nhật yt-dlp. `deploy-server.sh` giờ chỉ gửi mã nguồn rồi gọi
    `install.sh --service`, nên chỉ còn một nơi định nghĩa cách cài.
  - `scripts/make-release.sh` đóng gói `dist/tubemini-server-<phiên bản>.tar.gz` (khoảng 140 KB). Repo không có remote, nên chưa có
    lệnh `curl … | bash` hay image trên Docker Hub (đẩy lên mạng là việc anh quyết).
  - `docker-compose.yml` cho Windows / macOS (Docker Desktop).
- **Đã thử:**
  - Service: cập nhật máy chủ thật .192 qua `deploy-server.sh` mới; `config.toml` không đổi (cùng md5), dữ liệu còn đủ (3 kênh,
    13 mục lịch sử), service và hẹn giờ chạy.
  - Docker (Podman) trên máy build Ubuntu 26.04, từ gói phát hành, thư mục `/opt/tubemini-test`, cổng 18080:
    - cài mới khoảng 3 phút 40 giây; `--status` đúng;
    - khởi động lại unit vẫn chạy; hẹn giờ `yt-dlp -U` chạy thành công;
    - máy PC truy cập được, và thấy cùng lúc hai máy chủ qua mDNS;
    - gỡ với `--purge` xoá sạch unit, thư mục, container, image.
  - Lỗi tìm ra khi thử: mỗi lần build để lại một image trung gian khoảng 1,6 GB. Nay hai tầng của Dockerfile mang nhãn
    `org.tubemini.image`, và script dọn image cũ mang nhãn đó sau mỗi lần build và khi gỡ.
  - Sau khi thử, đã xoá mọi image Podman của root trên máy build (trước đó trống); image của dự án khác không đụng tới.

## D31. Lên GitHub: repo công khai TubeMini/TubeMini, bỏ thông tin cá nhân, bundle id vn.tubemini.io — 15/11/2026

- Anh tạo tổ chức GitHub `TubeMini`. Một repo chung (server + app + tài liệu), công khai, giấy phép GPL-3.0; trang giới thiệu ở
  repo riêng `TubeMini/TubeMini.github.io`.
- **Trước khi đẩy, viết lại toàn bộ lịch sử** (repo chưa từng đẩy đi đâu) để bỏ thông tin cá nhân:
  - IP công cộng của nhà trong các phản hồi YouTube dùng làm dữ liệu test → `203.0.113.7` (dải dành cho tài liệu);
  - IP mạng nội bộ `10.10.10.x` / `10.10.16.x` → `192.168.1.x` / `192.168.2.x`, cả dạng viết tách số trong test mDNS;
  - tên người dùng máy build, tên máy PC trong test mDNS, dòng Maintainer / Author của gói `.deb` → tên chung.
- Đã quét lại toàn bộ lịch sử mới:
  - không có mật khẩu nào của 4 thiết bị (so trực tiếp, không in ra);
  - không có chuỗi nào trong file thông tin thiết bị ngoài các từ thông dụng;
  - không có email, số điện thoại hay đường dẫn máy tính. Tác giả commit dùng email ẩn danh của GitHub.
- **Bundle id** đổi từ `vn.qmv.tubemini` sang `vn.tubemini.io` (anh chọn). Trên iPad: chép file cài đặt sang tên mới, gỡ gói cũ
  (hai gói cùng cài vào `/Applications/TubeMini.app`), cài gói mới. Bản tải về và lịch sử vẫn còn.
