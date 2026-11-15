# Dự án TubeMini — Server Rust kiểu TubeRepair + app YouTube mới cho iPad mini 1 (iOS 6)

## 0. Cách làm việc
- Trả lời bằng tiếng Việt. Code, tên biến và commit message viết bằng tiếng Anh; tài liệu trong `docs/` viết bằng tiếng Việt.
- Đọc hết tài liệu này trước. Chưa viết code ngay mà làm theo thứ tự:
  1. Tóm tắt dự án trong tối đa 10 dòng.
  2. Gom mọi điểm chưa rõ hoặc rủi ro thành **một lượt câu hỏi**.
  3. Đề xuất kế hoạch cho Giai đoạn 0.
  4. Chờ anh duyệt.
- Làm theo từng giai đoạn (mục 7). Hết mỗi giai đoạn thì dừng lại và báo cáo: đã làm gì, anh kiểm tra bằng cách nào, còn tồn gì. Anh là người test trên iPad thật vì em không truy cập được thiết bị.
- **Tài liệu tham chiếu chính:** mã nguồn server TubeRepair tại `https://github.com/kevinf100/tuberepair.uptimetrackers.com` (nhánh mặc định `blueprint`, viết bằng Python/Flask). Đọc kỹ các route, template XML và cách xử lý User-Agent trong đó trước khi thiết kế lớp tương thích (mục 4.3).
  - Giấy phép của repo đó là GPL-3.0. Tham khảo định dạng và hành vi thì thoải mái. Nếu chép nguyên template hay code thì phải ghi nguồn, và khi phát hành thì dự án cũng phải theo GPL-3.0. Ghi rõ lựa chọn vào `docs/DECISIONS.md`.
- Những gì liên quan tới YouTube thay đổi liên tục: không dựa vào trí nhớ. Kiểm tra tài liệu và phiên bản mới nhất của yt-dlp, rustypipe trước khi dùng. Không tự bịa endpoint nội bộ của YouTube.
- Sau mỗi thay đổi: `cargo fmt`, `cargo clippy -- -D warnings` và `cargo test` phải sạch. Commit nhỏ, rõ ràng. Cập nhật `docs/PROGRESS.md`.
- `docs/API.md` là hợp đồng giữa server và các app. Đổi API thì phải cập nhật file này trước.
- Ưu tiên cách đơn giản, một người bảo trì được. Không thêm dependency khi không thật cần.

## 1. Bối cảnh và mục tiêu
- **Thiết bị:** iPad mini thế hệ 1, chip Apple A5 (**armv7, không phải armv7s**), RAM 512MB, màn hình 1024×768 không retina, chạy iOS 6.x. Máy đã jailbreak, có Cydia, AppSync Unified, OpenSSH.
- **Vấn đề:** App Store trên iOS 6 đã ngừng hoạt động. App YouTube cũ không chạy nữa vì API cũ của YouTube (GData v2) đã bị tắt.
- **Mô hình tham chiếu là TubeRepair.** TubeRepair gồm một tweak gắn vào app YouTube cũ, chuyển mọi request từ gdata.youtube.com sang một server riêng. Server đó giả lập API GData cũ: lấy dữ liệu từ YouTube hiện nay, trả về XML đúng định dạng cũ. Còn video thì iPad tải thẳng từ máy chủ của Google.
- **Mục tiêu:** tự làm lại cả hai nửa theo đúng mô hình đó, và mở rộng thêm:
  1. **Server Rust "tubemini-server"** tương thích với app YouTube 1.2.1 + tweak TubeRepair, để app cũ dùng được ngay. Server có thêm các API mở rộng cho tính năng mới.
  2. **App mới "TubeMini"** (Objective-C) thay cho app YouTube cũ, có các tính năng app gốc không có:
     - theo dõi kênh mà không cần đăng nhập Google, trang chủ là video mới từ các kênh đã theo dõi;
     - lịch sử xem và xem tiếp từ chỗ đang dừng;
     - chọn chất lượng video;
     - giao diện tiếng Việt;
     - sau này: nghe nền khi tắt màn hình, tải video xem offline.
- Dùng cho cá nhân và gia đình, chủ yếu chạy trong mạng LAN ở nhà.

## 2. Kiến trúc tổng thể
```
App YouTube 1.2.1 + tweak TubeRepair ──┐
                                        ├─(1) XML ──► Server Rust "tubemini-server" ──► YouTube
App TubeMini (mới, Objective-C) ───────┘            (PC Windows ở nhà)
        │                                           rustypipe + yt-dlp/Deno
        └─(2) ảnh + video tải thẳng ──► i.ytimg.com, googlevideo.com (HTTPS)
```
Nguyên tắc cốt lõi:
1. **Server chỉ trả XML và link video, không chuyển tiếp ảnh hay video.** Giống TubeRepair:
   - `/getvideo/{id}` trả **redirect 307** sang link googlevideo (360p);
   - hoặc trả **playlist HLS dạng text** đã lọc (720p), trong đó các segment vẫn trỏ thẳng tới googlevideo.
   - Băng thông video không bao giờ đi qua server.
2. **Hai lớp API trên cùng một server:**
   - **Lớp tương thích GData:** đúng đường dẫn và định dạng XML (Atom + các namespace `media:`, `yt:`, `gd:`, `openSearch:`) mà app YouTube 1.2.1 và tweak TubeRepair đang dùng. Hành vi lấy theo server TubeRepair.
   - **Lớp mở rộng `/tm/v1/...`:** API cho các tính năng riêng của TubeMini, cũng trả XML, dùng namespace riêng `xmlns:tm="urn:tubemini:1"`.
   - App TubeMini **dùng lại lớp GData** cho phần duyệt (tìm kiếm, video, kênh, playlist, bình luận, video liên quan) và dùng lớp mở rộng cho tính năng mới. Một server phục vụ được cả app cũ lẫn app mới.
3. **App càng mỏng càng tốt.** Mọi phần phức tạp (gọi YouTube, giải mã link) nằm ở server. Khi YouTube thay đổi, chỉ sửa server, không phải build lại app.
4. **Link video phải dùng được từ IP khác với server, giống TubeRepair.**
   - Link googlevideo có ghi IP của bên xin link, nhưng YouTube không phải lúc nào cũng bắt khớp IP. Mức độ tùy loại client dùng để xin link, và có thể thay đổi theo thời gian.
   - Server TubeRepair công khai chạy trên VPS, xin link bằng client IOS (HLS) và ANDROID (360p) qua InnerTube, mà người dùng ở mạng nào cũng xem được.
   - Server mình phải chọn cách xin link cho ra link "mang đi được" như vậy, và kiểm chứng ở Giai đoạn 0–1.
   - Server và iPad cùng mạng nhà vẫn là trường hợp an toàn nhất. Gọi YouTube bằng IPv4 để tránh lệch IPv4/IPv6.

## 3. Ràng buộc kỹ thuật bắt buộc

### 3.1 iPad / iOS 6
- **Kiến trúc:** chỉ build `armv7`, deployment target iOS 6.0. Bản armv7s sẽ không chạy trên chip A5. Kiểm tra binary bằng `lipo -info` / `otool -l`: chỉ có slice armv7, phiên bản tối thiểu là 6.0.
- **Video:** chỉ dùng H.264 (avc1) + AAC, đóng trong MP4 hoặc HLS với segment MPEG-TS.
  - Không dùng VP9, AV1, Opus.
  - Không dùng HLS kiểu fMP4, vì iOS 6 không hỗ trợ.
  - Phần cứng giải mã được tới 1080p30. Mục tiêu thực tế: 360p (mặc định) và 720p.
- **Ảnh:** chỉ JPEG hoặc PNG, vì iOS 6 không đọc được WebP.
- **Đọc XML:** dùng NSXMLParser (kiểu SAX, có từ iOS 2). iOS không có parser dạng cây (NSXMLDocument chỉ có trên macOS), nên viết một lớp parser nhỏ dùng chung để chuyển Atom entry thành model. Thiếu thẻ thì model dùng giá trị mặc định, không được crash.
- **Không được dùng** vì iOS 6 không có:
  - NSURLSession, NSURLComponents, `stringByAddingPercentEncodingWithAllowedCharacters:`;
  - UIAlertController, UIStackView;
  - `@available`, Swift, `@import`;
  - storyboard và xib.
- **Dùng thay thế:**
  - NSURLConnection `sendAsynchronousRequest:queue:completionHandler:`;
  - `CFURLCreateStringByAddingPercentEscapes`;
  - UIAlertView, UIActionSheet;
  - frame + autoresizingMask cho bố cục;
  - `respondsToSelector:` để kiểm tra tính năng.
- **Được dùng:** ARC (`-fobjc-arc`), blocks, GCD, NSXMLParser, NSCache, object literals và subscripting, UIRefreshControl, MPMoviePlayerViewController.
- **RAM 512MB:**
  - đặt giới hạn cho NSCache ảnh;
  - xóa cache khi nhận memory warning;
  - tái sử dụng cell;
  - không giữ ảnh kích thước lớn.

### 3.2 Mạng
- **App ↔ server:** HTTP thuần trong LAN, server lắng nghe ở `0.0.0.0:8080`. Tweak TubeRepair nhận địa chỉ HTTP (ví dụ `http://192.168.1.10:8080`) ở mục "Custom URL". Có tùy chọn token dùng chung cho lớp `/tm/v1` (header `X-Auth-Token`), mặc định tắt.
- **App ↔ Google:** iPad tự kết nối HTTPS tới `i.ytimg.com` (ảnh) và `googlevideo.com` (video) bằng TLS của chính iOS 6.
  - Đây là **rủi ro số một** của kiến trúc: kho chứng chỉ và bộ mã hóa của iOS 6 đã cũ, Google có thể ngừng hỗ trợ bất cứ lúc nào.
  - Hiện TubeRepair vẫn cho iOS 5–6 tải video thẳng từ googlevideo nên khả năng cao là chạy được, nhưng phải kiểm chứng ngay ở Giai đoạn 0.
  - Không có kế hoạch B trong bản đầu. Nếu sau này kết nối trực tiếp hỏng, sẽ cân nhắc chế độ proxy dự phòng (Giai đoạn 5).
- **Ngoài mạng nhà:** nếu link "mang đi được" (mục 2) thì iPad ở mạng nào cũng xem được, giống TubeRepair. Nếu YouTube siết lại việc khớp IP thì dùng VPN về nhà hoặc chế độ proxy dự phòng (Giai đoạn 5).
- **Khi mở server ra internet (sau này):** HTTPS bằng Let's Encrypt (iPad phải cài chứng chỉ ISRG Root X1) và bắt buộc có token.

### 3.3 YouTube
- **yt-dlp:** từ bản 2025.11.12, yt-dlp cần một JS runtime bên ngoài (khuyến nghị Deno, bật sẵn mặc định) và thành phần yt-dlp-ejs (đã có sẵn trong bản yt-dlp.exe chính thức).
- **Kiểm tra khi khởi động:** server phải kiểm tra yt-dlp và deno, thiếu cái nào thì báo rõ.
- **Link video có hạn và gắn IP:**
  - link googlevideo hết hạn theo tham số `expire`. Server chỉ cache vài phút, vì mỗi lần bấm phát app đều gọi lại `/getvideo`;
  - link có ghi IP của bên xin link (tham số `ip=`). YouTube có lúc bắt khớp IP, có lúc không, tùy client. Gọi YouTube bằng IPv4 (`--force-ipv4`) để tránh trường hợp server xin bằng IPv6 mà iPad tải bằng IPv4.
  - **Spike bắt buộc:** so sánh các cách xin link, gồm yt-dlp với từng `player_client` khác nhau, và gọi InnerTube trực tiếp bằng client IOS/ANDROID như TubeRepair. Chọn cách cho link phát được trên iPad ở **mạng khác** server. Ghi kết quả vào `docs/DECISIONS.md`.
- **Không cần** API key, không cần đăng nhập Google.

## 4. Server Rust — chi tiết

### 4.1 Stack
- Rust stable mới nhất, edition 2024. Một binary crate chia module là đủ; chỉ tách thành nhiều crate khi thật cần.
- **Thư viện:**
  - axum + tokio;
  - reqwest (dùng rustls) để gọi YouTube và tải playlist HLS về lọc;
  - askama (template kiểu Jinja, kiểm tra lúc biên dịch) để sinh XML cho lớp GData; quick-xml nếu cần đọc XML (RSS kênh). Mọi chuỗi đưa vào XML phải được escape đúng;
  - tracing;
  - rusqlite với feature `bundled` (khỏi phải cài SQLite trên Windows);
  - moka cho cache trong bộ nhớ;
  - thiserror / anyhow;
  - toml cho config, clap cho CLI.
- **Metadata:** đánh giá crate `rustypipe`, một client InnerTube viết bằng Rust, có tìm kiếm phân trang, kênh, video, video liên quan, bình luận, playlist và RSS. Phải kiểm tra bản mới nhất còn chạy được không trước khi chốt.
- **Link video:** gọi `yt-dlp --force-ipv4` như một tiến trình ngoài (`tokio::process::Command`).
  - Trên Windows đặt cờ `CREATE_NO_WINDOW` để không bật cửa sổ console.
  - Giới hạn số tiến trình chạy cùng lúc (semaphore, ví dụ 3).
  - Đặt timeout khoảng 30 giây.
- **Hai trait để dễ thay backend:**
  - `MetadataProvider`: search, video, channel, related, playlist, comments, rss;
  - `StreamResolver`: trả về link progressive và URL manifest HLS. Có thể có hai cách cài đặt: qua yt-dlp, và gọi InnerTube trực tiếp như TubeRepair. Chọn theo kết quả spike ở mục 3.3.
  - Có thêm một implementation dự phòng dùng yt-dlp để lấy metadata, phòng khi rustypipe hỏng.

### 4.2 Cấu hình (`config.toml` đặt cạnh file exe)
```toml
listen = "0.0.0.0:8080"
auth_token = ""              # để rỗng = tắt (chỉ áp dụng cho /tm/v1)
data_dir = "./data"          # sqlite + cache
yt_dlp_path = "yt-dlp"       # hoặc đường dẫn tuyệt đối tới yt-dlp.exe
max_ytdlp_procs = 3
force_ipv4 = true            # bắt buộc, để IP của link khớp với iPad
medium_quality = true        # /getvideo không có tiền tố độ phân giải thì trả 360p
hls_resolution = 720         # độ phân giải mặc định cho HLS
home_feed = "popular"        # trang chủ app cũ: "popular" hoặc "subscriptions"
log_queries = false          # không ghi từ khóa tìm kiếm vào log
region = "VN"
language = "vi"
```

### 4.3 Lớp tương thích GData (cho app YouTube 1.2.1 + tweak TubeRepair)
Bám đúng hành vi của server TubeRepair; đọc mã nguồn của nó để biết chi tiết từng route, tham số và template.
- **Tiền tố độ phân giải:** mọi route đều có thêm biến thể `/{res}/...` (ví dụ `/720/feeds/api/videos`). Người dùng nhập Custom URL kiểu `http://IP:8080/720` để chọn độ phân giải. Mọi link sinh ra trong XML phải giữ đúng tiền tố này.
- **Các route cần có:**
  - `/feeds/api/standardfeeds/{feed}` và `/feeds/api/standardfeeds/{region}/{feed}`: trang chủ / phổ biến. Khi `home_feed = "subscriptions"` thì trả video mới từ các kênh đã theo dõi (tính năng mở rộng dùng được cả trên app cũ).
  - `/feeds/api/videos?q=...`: tìm video. Phải hỗ trợ các tham số `start-index`, `max-results`, `orderby`, `time`, `duration`, `caption`, `continuation`.
  - `/feeds/api/videos/{id}/related`: video liên quan.
  - `/feeds/api/videos/{id}/comments` và `/api/videos/{id}/comments`: bình luận, có phân trang bằng `continuation`.
  - `/feeds/api/channels?q=...`: tìm kênh. `/feeds/api/channels/{id}`: thông tin kênh.
  - `/feeds/api/users/{id}/uploads`: video của kênh.
  - `/feeds/api/users/{id}/playlists`, `/feeds/api/playlists/{id}`, `/feeds/api/playlists/snippets`: playlist.
  - `/schemas/2007/categories.cat`: file danh mục tĩnh.
  - `POST /youtube/accounts/applelogin1`, `applelogin2`, `registerDevice`: trả khóa giả để app bỏ qua bước đăng nhập, giống TubeRepair.
  - `/getvideo/{id}`: xem mục 4.6.
- **Định dạng:** XML Atom giống template của TubeRepair, kể cả namespace `yt:` trỏ về URL server. Phân trang bằng thẻ `<link rel='next'>`.
- **User-Agent:** một số route trả định dạng khác cho app YouTube 1.0.0 và app YouTube "classic". Làm theo đúng cách TubeRepair phân biệt.
- **Ảnh trong XML:** `media:thumbnail` dùng URL tuyệt đối `https://i.ytimg.com/vi/{id}/mqdefault.jpg` (JPEG). Avatar kênh dùng URL JPEG cỡ nhỏ; nếu chỉ có WebP thì đổi sang biến thể JPEG/PNG.
- **Không làm:** đăng nhập thật, thích/không thích, upload.

### 4.4 Lớp mở rộng `/tm/v1` (cho app TubeMini)
- Trả XML với namespace `xmlns:tm="urn:tubemini:1"`. Danh sách video thì **dùng lại đúng định dạng Atom của lớp GData**, để app chỉ cần một bộ parser cho video.
- **Các endpoint:**
  - `GET /tm/v1/ping`: trạng thái và phiên bản của server, yt-dlp, deno.
  - `GET /tm/v1/videos/{id}/streams`: các lựa chọn chất lượng, gọi ngay trước khi phát. Ví dụ:
    ```xml
    <tm:streams xmlns:tm="urn:tubemini:1" video_id="dQw4w9WgXcQ" expire="1763150000">
      <tm:stream quality="360" kind="mp4" url="https://rr3---sn-....googlevideo.com/videoplayback?..."/>
      <tm:stream quality="720" kind="hls" url="http://192.168.1.10:8080/720/getvideo/dQw4w9WgXcQ"/>
    </tm:streams>
    ```
  - `GET` / `POST` / `DELETE /tm/v1/subscriptions`: danh sách kênh theo dõi, lưu bằng SQLite trên server.
  - `GET /tm/v1/feed?continuation=...`: feed Atom các video mới từ những kênh đã theo dõi. Lấy qua RSS từng kênh, gộp lại và sắp theo thời gian.
  - `GET` / `POST /tm/v1/history`: lịch sử xem và vị trí đang xem (`video_id`, `position` tính bằng giây) để xem tiếp.
- **Lỗi:** trả HTTP status phù hợp kèm `<tm:error code="..." message="..."/>`. `message` viết bằng tiếng Việt để app hiện thẳng cho người dùng.
- Ghi đầy đủ định dạng từng endpoint vào `docs/API.md`, kèm ví dụ.

### 4.5 Quy ước XML chung
- UTF-8. Escape đúng mọi chuỗi (tiêu đề và mô tả có ký tự `&`, `<`, emoji, tiếng Việt).
- Thời gian theo ISO 8601 như GData (`published`, `updated`). Thời lượng tính bằng giây (`yt:duration seconds='213'`). Lượt xem là số nguyên.
- Bật gzip: app YouTube cũ và NSURLConnection trên iOS 6 đều tự giải nén.
- Chỉ trả những trường app thật sự dùng để payload gọn.

### 4.6 `/getvideo/{id}` — link phát video (phần dễ sai nhất)
Server **không** chuyển tiếp dữ liệu video. Hành vi giống TubeRepair:
- **Không có tiền tố độ phân giải** (và `medium_quality = true`): trả **307 redirect** sang link 360p progressive trên googlevideo. Chọn định dạng MP4 có sẵn cả hình lẫn tiếng, H.264 + AAC (selector kiểu `b[ext=mp4][vcodec^=avc1][acodec^=mp4a][height<=360]`), lấy URL bằng `yt-dlp --force-ipv4 -J`. Trình phát trên iPad tự gửi request Range tới googlevideo để tua.
  - Nếu video không còn định dạng progressive này thì chuyển sang HLS.
- **Có tiền tố `/{res}/`** (hoặc `medium_quality = false`): trả playlist HLS master đã lọc, `Content-Type: application/vnd.apple.mpegurl`.
  - Lấy URL manifest HLS qua yt-dlp (`--force-ipv4`), tải manifest master (vài KB).
  - Chỉ giữ biến thể avc1 + AAC có độ phân giải ≤ `res`; bỏ VP9/AV1/Opus và phụ đề.
  - Giữ nguyên URL tuyệt đối tới googlevideo của các playlist con. Playlist con và segment iPad tự tải.
  - Phải xác nhận segment là MPEG-TS. Nếu YouTube chỉ còn HLS kiểu fMP4 thì iOS 6 không phát được; khi đó báo lại anh trước khi tính cách khác (không tự thêm ffmpeg hay proxy).
- **Link hết hạn hoặc 403:** mỗi lần bấm phát, app đều gọi lại `/getvideo` nên tự có link mới. App TubeMini thêm tham số `?fresh=1` khi thử lại để server bỏ qua cache.

### 4.7 Khác
- **Cache:** metadata giữ 15–60 phút (moka); link video chỉ giữ vài phút.
- **Log:** dùng tracing; mặc định không ghi từ khóa tìm kiếm.
- **Chạy trên Windows:** chỉ cần một file exe; cũng build được cho Linux.
- **README hướng dẫn:**
  - cài yt-dlp.exe và Deno; cập nhật bằng `yt-dlp -U`;
  - mở cổng trên Windows Firewall;
  - cài app YouTube 1.2.1 + tweak TubeRepair trên iPad và nhập Custom URL `http://<IP PC>:8080` (thêm `/720` nếu muốn HD).
- **Test:**
  - snapshot test cho XML sinh ra (crate `insta`), dùng fixture dữ liệu đã lưu sẵn;
  - so cấu trúc XML (tên thẻ, thuộc tính) với server TubeRepair công khai cho cùng một truy vấn, để bắt lỗi tương thích;
  - test cho phần lọc playlist HLS, dùng manifest mẫu đã lưu sẵn;
  - test gọi YouTube thật thì đánh dấu `#[ignore]`;
  - script `scripts/smoke.ps1` để thử nhanh các endpoint.

## 5. App iOS 6 "TubeMini" — chi tiết

### 5.1 Build
- **Môi trường:** Theos trên WSL2 (Ubuntu), template `application`, bundle id `vn.tubemini.io`.
- **Makefile:**
  - `TARGET = iphone:clang:<SDK cũ còn armv7, ví dụ 9.3>:6.0`
  - `ARCHS = armv7`
  - `TubeMini_CFLAGS = -fobjc-arc`
  - Framework: UIKit, Foundation, CoreGraphics, QuartzCore, MediaPlayer, AVFoundation.
- **Đóng gói:** file `.deb` cài vào `/Applications/TubeMini.app`; script postinst chạy `uicache` nếu máy có.
- **Script deploy:** `scripts/deploy.sh` dùng `scp` + `dpkg -i` qua SSH để cài sang iPad. IP và mật khẩu lấy từ biến môi trường, không hard-code.
- **Info.plist:**
  - `MinimumOSVersion` = 6.0
  - `UIDeviceFamily` = [2] (iPad)
  - `UIRequiredDeviceCapabilities` = armv7
  - icon 72 và 144
  - tên hiển thị "TubeMini"

### 5.2 Cấu trúc code (Objective-C thuần, giao diện viết bằng code)

**Lớp nền**
- `TMAPIClient` (singleton):
  - lấy base URL, độ phân giải và token từ NSUserDefaults;
  - gọi NSURLConnection bất đồng bộ, timeout 20 giây;
  - đổi lỗi thành câu tiếng Việt.
- `TMAtomParser`: dùng NSXMLParser đọc feed Atom kiểu GData thành các model TMVideo, TMChannel, TMPlaylist, TMComment, kèm link trang tiếp theo.
- `TMExtParser`: đọc các phản hồi `tm:` (streams, subscriptions, history, lỗi).
- `TMImageLoader`: tải ảnh thẳng từ `i.ytimg.com` (HTTPS) theo kiểu bất đồng bộ.
  - Cache 2 tầng: NSCache có giới hạn trong RAM và thư mục `Library/Caches` trên đĩa.
  - Chống "nhảy ảnh" khi cell được tái sử dụng.
  - Ảnh tải lỗi thì hiện ảnh giữ chỗ, không làm crash hay treo danh sách.

**Các màn hình** (UITabBarController + UINavigationController, giao diện tiếng Việt)
- **Trang chủ:** feed từ các kênh đã theo dõi (`/tm/v1/feed`), kéo xuống để làm mới. Nếu trống thì gợi ý sang tìm kiếm.
- **Tìm kiếm:** UISearchBar + UITableView, tìm video và kênh, cuộn vô hạn theo link trang tiếp theo.
- **Chi tiết video:**
  - thumbnail, tiêu đề, kênh, lượt xem, mô tả;
  - nút Phát, nút chọn chất lượng, nút theo dõi kênh;
  - danh sách video liên quan, bình luận (chỉ đọc).
- **Kênh:** thông tin kênh, danh sách video, playlist, nút Theo dõi / Bỏ theo dõi.
- **Đã theo dõi:** danh sách các kênh.
- **Lịch sử:** các video đã xem, mở lại thì xem tiếp từ chỗ cũ.
- **Cài đặt:**
  - địa chỉ server (ví dụ `http://192.168.1.10:8080`) và token;
  - chất lượng mặc định 360 hoặc 720;
  - nút "Kiểm tra kết nối" gọi `/tm/v1/ping`.

**Phát video**
- Bấm Phát thì gọi `/tm/v1/videos/{id}/streams` để lấy link mới, rồi đưa thẳng URL googlevideo (360p) hoặc URL playlist HLS (720p) cho MPMoviePlayerViewController.
- Lỗi phát (403, hết hạn): gọi lại với `?fresh=1` một lần. Vẫn lỗi thì hiện UIAlertView đề nghị thử lại ở 360p.
- Định kỳ lưu vị trí xem qua `/tm/v1/history`, lần sau mở lại thì xem tiếp từ chỗ cũ.
- Hỗ trợ cả hai hướng màn hình của iPad.

## 6. Ngoài phạm vi (chưa làm)
Đăng nhập tài khoản Google, thích/không thích, viết bình luận, quảng cáo, chat livestream, giao diện riêng cho Shorts, upload video.

## 7. Lộ trình và tiêu chí nghiệm thu

**Giai đoạn 0 — Dựng khung và kiểm chứng rủi ro** (làm trước)
- Tạo repo theo mục 8; workspace Rust build được trên Windows.
- Viết `docs/SETUP.md` hướng dẫn cài Theos, toolchain và SDK trên WSL2.
- Build app "Hello TubeMini" cho armv7 / iOS 6.
- Hướng dẫn anh **kiểm chứng tải trực tiếp** (rủi ro số một ở mục 3.2):
  - trên PC chạy `yt-dlp --force-ipv4 -g -f 18 <link video>`, chép URL in ra sang Safari trên iPad: video phải phát và tua được;
  - mở `https://i.ytimg.com/vi/<id>/mqdefault.jpg` trên Safari iPad: ảnh phải hiện, không báo lỗi chứng chỉ;
  - lặp lại phép thử video khi iPad bắt Wi-Fi phát từ điện thoại 4G (khác IP với PC). Phép thử này chỉ ghi nhận kết quả, chưa bắt buộc đạt; spike ở mục 3.3 sẽ quyết định.
- Hướng dẫn anh dựng **mốc so sánh**: cài app YouTube 1.2.1 + tweak TubeRepair, trỏ vào server TubeRepair công khai, ghi lại những gì đang chạy được.
- **Nghiệm thu:**
  - anh cài file .deb lên iPad, app mở được và hiện chữ;
  - binary chỉ có slice armv7, phiên bản tối thiểu 6.0;
  - hai phép thử tải trực tiếp đều đạt. Nếu không đạt thì dừng lại, báo anh để tính lại kiến trúc.

**Giai đoạn 1 — Server: lớp GData tối thiểu**
- Làm: categories, các route đăng nhập giả, trang chủ (standardfeeds), tìm video có phân trang, video liên quan, video của kênh, `/getvideo` 360p (redirect 307), trang web debug ở `/`.
- Làm spike và chốt: có dùng rustypipe để lấy metadata được không.
- **Nghiệm thu:** app YouTube 1.2.1 + tweak TubeRepair, Custom URL trỏ về server nhà:
  - trang chủ hiện video, tìm kiếm được, mở video phát 360p và tua được;
  - trong lúc xem, server gần như không có lưu lượng mạng (video không đi qua server);
  - iPad bắt 4G từ điện thoại (khác mạng với server) vẫn xem được. Nếu không đạt thì báo anh trước khi tính tới chế độ proxy.

**Giai đoạn 2 — Server: hoàn thiện lớp GData**
- Làm: HLS 720p qua tiền tố `/{res}/`, tìm kênh, thông tin kênh, playlist, bình luận, phân biệt User-Agent.
- **Nghiệm thu:** mọi màn hình của app YouTube 1.2.1 chạy được với server nhà ít nhất ngang server TubeRepair công khai; Custom URL có `/720` thì phát 720p ổn định.

**Giai đoạn 3 — App TubeMini MVP**
- Làm: Cài đặt server, Tìm kiếm, Chi tiết video, phát 360p/720p; đọc XML lớp GData bằng `TMAtomParser`; endpoint `/tm/v1/ping` và `/tm/v1/videos/{id}/streams`.
- **Nghiệm thu trên iPad mini 1:**
  - tìm → mở → xem → tua đều mượt;
  - không crash;
  - cuộn danh sách không giật.

**Giai đoạn 4 — Tính năng mở rộng**
- Làm: theo dõi kênh, feed trang chủ, lịch sử và xem tiếp, trang Kênh đầy đủ, chọn chất lượng.
- Làm thêm tùy chọn `home_feed = "subscriptions"` để app YouTube cũ cũng thấy feed từ kênh đã theo dõi.

**Giai đoạn 5 — Mở rộng (tùy chọn)**
- Chế độ chỉ âm thanh, nghe khi tắt màn hình (`UIBackgroundModes` audio).
- Tải video về iPad để xem offline.
- App tự tìm server trong LAN: server quảng bá bằng mDNS, app dò bằng NSNetServiceBrowser.
- Xem ngoài mạng nhà: hướng dẫn VPN về nhà, hoặc chế độ proxy dự phòng (`proxy_fallback`, mặc định tắt): chỉ khi bật mới chuyển tiếp video qua server, có hỗ trợ Range.
- Triển khai lên VPS: HTTPS, token, Dockerfile.
  - Nếu link "mang đi được" thì không cần proxy; nếu không thì phải bật proxy dự phòng.
  - Link đi theo quốc gia của server, nên VPS nên đặt ở Việt Nam để tránh video bị chặn theo vùng.
  - IP trung tâm dữ liệu dễ bị YouTube chặn hơn IP nhà.

## 8. Cấu trúc repo đề xuất
```
tubemini/
├─ server/
│  ├─ src/gdata/            # lớp tương thích GData (route + template askama)
│  ├─ src/ext/              # lớp mở rộng /tm/v1
│  ├─ src/video/            # /getvideo, chọn định dạng, lọc HLS
│  ├─ src/youtube/          # MetadataProvider, StreamResolver (rustypipe, yt-dlp)
│  ├─ src/store/            # SQLite: subscriptions, history
│  ├─ templates/            # template XML
│  ├─ static/categories.cat
│  └─ config.example.toml
├─ ios/TubeMini/            # Theos project: Makefile, control, Resources, *.m
├─ docs/                    # API.md, SETUP.md, PROGRESS.md, DECISIONS.md
└─ scripts/                 # smoke.ps1, deploy.sh
```
Ghi các quyết định kỹ thuật (ví dụ chọn rustypipe hay yt-dlp, cách xử lý giấy phép GPL của TubeRepair) vào `docs/DECISIONS.md`, kèm lý do.

## 9. Việc đầu tiên
Đọc xong thì trả lời anh đúng theo mục 0: tóm tắt, câu hỏi gom một lượt, kế hoạch Giai đoạn 0. Chưa viết code khi anh chưa duyệt.
