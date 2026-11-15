# API của tubemini-server

Đây là hợp đồng giữa server và các app. **Đổi API thì sửa file này trước.**

Trạng thái: Giai đoạn 3. Lớp GData đã đủ cho app YouTube cũ. Lớp `/tm/v1` mới có `ping` và `streams`; phần còn lại thuộc Giai
đoạn 4.

## Quy ước chung

- HTTP thuần trong LAN, mặc định `0.0.0.0:8080`.
- XML: UTF-8, escape đúng mọi chuỗi, thời gian theo ISO 8601, thời lượng tính bằng giây, lượt xem là số nguyên.
- Video không bao giờ đi qua server: server chỉ trả redirect 307 hoặc playlist HLS đã lọc, các segment vẫn trỏ thẳng tới
  googlevideo.
- Tiền tố độ phân giải `/{res}/...` áp dụng cho mọi route của lớp GData.

## Trang debug (HTML, cho người xem)

### `GET /[?q=<từ khóa>]`

Hiện các thông tin sau:

- phiên bản server, trạng thái yt-dlp / deno (có hay thiếu) và cấu hình chính;
- link tới các XML mẫu;
- ô tìm kiếm: kết quả hiện kèm ảnh, link 360p (`/getvideo`) và HLS (`/720/getvideo`), mở thử được ngay trên Safari iPad.

### `GET /gd0?id=<ID hoặc link YouTube>` (tạm thời, Giai đoạn 0)

Trang thử tải trực tiếp, dùng trên Safari của iPad:

1. Ảnh `https://i.ytimg.com/vi/<id>/mqdefault.jpg`, phải hiện mà không báo lỗi chứng chỉ.
2. Nút "Phát video": link googlevideo format 18 (360p, H.264 + AAC) do `yt-dlp --force-ipv4 -g -f 18` trả về.
3. IP và client dùng để xin link, và số phút link còn hạn.

Không có `id` thì trang chỉ hiện ô nhập và hai video mẫu. ID sai thì báo lỗi; yt-dlp lỗi thì hiện câu lỗi cuối của yt-dlp.

## Lớp tương thích GData (cho app YouTube cũ + tweak TubeRepair)

Hành vi theo server TubeRepair, định dạng XML theo template của nó (D1). Mọi route đều có thêm biến thể với tiền tố độ phân giải:
`/720/feeds/api/videos?...` giống `/feeds/api/videos?...`, chỉ khác là mọi link trong XML đều giữ `/720`, và `/getvideo` trả HLS.

Ghi chú chung:

- **Base URL** trong XML = `http://<Host của request>[/<res>]`, đúng với Custom URL người dùng nhập. Namespace `yt:` cũng trỏ về
  `<base>/schemas/2007`, giống TubeRepair.
- `Content-Type: application/atom+xml; charset=UTF-8`, nén gzip nếu client gửi `Accept-Encoding: gzip`.
- Thời gian theo dạng `2026-11-15T08:03:22.000Z`; app cũ bắt buộc phải có `.000Z`. Ngày chỉ là ước lượng khi YouTube chỉ cho "3 ngày
  trước". Ngày không rõ thì là `1970-01-01T00:00:00.000Z`.
- Escape mọi chuỗi (askama dùng tham chiếu số như `&#38;`).
- Khi YouTube lỗi: trả `502`, nội dung là chữ `upstream error`. ID sai: `404`.

### Feed video (tìm kiếm, liên quan, video của kênh, trang chủ)

Một entry gồm:

- `id` (`tag:youtube.com,2008:video:<id>`), `published` / `updated`, `title`;
- `author` (`name`, `uri`, `yt:userId` = channel id `UC…`);
- `media:group`: `media:content url='<base>/getvideo/<id>'` với `yt:format` 1/2/3/6/8/9, `media:thumbnail` từ
  `https://i.ytimg.com/vi/<id>/{default,mqdefault,hqdefault}.jpg`, `media:title`, `media:description`,
  `yt:duration seconds='<giây>'`, `yt:uploaderId`, `yt:videoid`;
- `yt:statistics viewCount='<số>'`, `gd:comments` trỏ tới `<base>/api/videos/<id>/comments`;
- link `related` trỏ tới `<base>/feeds/api/videos/<id>/related`.

Phân trang: còn trang sau thì có `<link rel='next' href='…'>`, app gọi lại đúng link đó.

- `skip=<n>`: một trang của YouTube dài hơn `max-results` (playlist trả tới 100 video một lần, tab Videos của kênh trả 30) thì được
  chia thành nhiều trang GData. `skip` là số mục của trang YouTube hiện tại đã hiện ở các trang GData trước.
- `continuation=<token>`: hết trang YouTube thì chuyển sang trang YouTube tiếp theo. Token bắt đầu bằng `ytdlp:` là của nhánh dự phòng
  yt-dlp (D19).
- `start-index` chỉ tăng để hiển thị. `openSearch:totalResults` là số giả lớn (cộng thêm 1000) khi còn trang sau.
- Các danh sách khác (kênh, playlist, bình luận) phân trang theo cùng cách.

### `GET /feeds/api/standardfeeds/[<region>/]<feed>`

Trang chủ. `most_popular` trộn các trang chủ đề Âm nhạc, Tin tức, Thể thao của YouTube theo `region` trong config. `most_popular_Music`,
`_News`, `_Sports`, `_Games`, `_Film` là từng danh mục. Không có `rel='next'`. Nhận `max-results` (mặc định 25, tối đa 50). Phần
`<region>` trong đường dẫn được bỏ qua: vùng lấy từ config.

### `GET /feeds/api/videos?q=<từ khóa>`

Tìm video. Tham số:

| Tham số | Giá trị | Ý nghĩa |
| --- | --- | --- |
| `q` | bắt buộc | thiếu thì `404` |
| `orderby` | `relevance` / `published` / `viewCount` / `rating` | sắp xếp |
| `time` | `today` / `this_week` / `this_month` | ngày đăng |
| `duration` | `short` (< 4 phút) / `medium` (4–20) / `long` (> 20) | thời lượng |
| `caption` | `true` | có phụ đề |
| `start-index`, `max-results` | số | chỉ để hiển thị / cắt bớt; trang sau dùng `continuation` |
| `continuation` | token từ `rel='next'` | trang tiếp theo |

Có cả `/feeds/api/videos/` (dấu `/` cuối).

### `GET /feeds/api/videos/<id>` và `GET /feeds/player/videos/<id>`

Một entry đơn (gốc là `<entry>` có khai báo namespace). YouTube 1.3.0 gọi `/feeds/player/videos/<id>` khi mở video theo ID.

### `GET /feeds/api/videos/<id>/related`

Video liên quan (cột bên phải của trang xem), có phân trang.

### `GET /feeds/api/users/<channel id>/uploads`

Video mới nhất của kênh (tab Videos), có phân trang. `<channel id>` phải là `UC…` (24 ký tự), không thì `404`.

### `GET /schemas/2007/categories.cat`

Danh mục tĩnh (Film, Music, Games, News, Sports), `application/atomcat+xml`.

### `POST /youtube/accounts/applelogin1`, `applelogin2`, `registerDevice`

Đăng nhập giả để app bỏ qua bước đăng nhập (giống TubeRepair). Trả text lần lượt là `r2=<k>\nhmackr2=<k>`, `Auth=<k>` và
`DeviceId=<k>\nDeviceKey=<k>`. Khóa `<k>` là chuỗi hex ngẫu nhiên, tạo một lần mỗi khi server khởi động.

### `GET /getvideo/<id>[?fresh=1]` (và `GET /video/sd/<id>`)

Link phát. Server không chuyển tiếp dữ liệu video.

- Không có tiền tố độ phân giải (và `medium_quality = true`): **307** sang link MP4 progressive ≤ 360p (H.264 + AAC, thường là itag
  18) trên googlevideo. Video không có định dạng này, **hoặc MP4 mang tiếng lồng tiếng AI** (D23), thì trả HLS 360p đã lọc như
  bên dưới.
- Có tiền tố (`/720/getvideo/<id>`) hoặc `medium_quality = false`: **200**, `Content-Type: application/vnd.apple.mpegurl`, là
  playlist HLS master của YouTube **đã lọc cho iOS 6**. Cách lọc giống TubeRepair:
  - chỉ giữ biến thể chỉ gồm avc1 + mp4a, tối đa 30fps, cạnh ngắn ≤ `res`;
  - sau đó chỉ giữ mức độ phân giải cao nhất còn lại;
  - rendition tiếng: mỗi nhóm chỉ giữ **một** track, ưu tiên track tiếng gốc ("original"), đặt `DEFAULT=YES`; bỏ các track lồng
    tiếng AI ("dubbed-auto") và bỏ phụ đề.

  Playlist con và segment vẫn là URL googlevideo. Không có biến thể nào dùng được thì trả 307 sang MP4 progressive. `res` không có
  tiền tố thì lấy `hls_resolution` trong config, và luôn được kẹp trong khoảng 144–2160.
- **Chờ quảng cáo (D17):** video có quảng cáo đầu thì googlevideo trả 403 tới mốc `available_at` mà yt-dlp báo. Server giữ request
  tới mốc đó (tối đa 30 giây) rồi mới trả, nên request đầu tiên có thể mất 7–8 giây.
- Link lấy bằng `yt-dlp --force-ipv4 -J`, cache 5 phút. Các request trùng nhau cho cùng một video dùng chung một lần chạy. Server
  lấy link trước khi app mở trang video (`/feeds/player/videos/<id>`, liên quan).
- `fresh=1` bỏ qua cache (app gọi khi thử lại sau lỗi 403).
- Không lấy được link: `502`. ID sai: `404`.
- `/video/sd/<id>` là link `<content src>` trong feed của app classic, xử lý giống `/getvideo/<id>`.

### `GET /feeds/api/channels?q=<từ khóa>`

Tìm kênh, có phân trang. Mỗi entry gồm:

- `id` (`tag:youtube.com,2008:channel:<id>`), `title`, `summary` (mô tả), `author` / `yt:userId`, `yt:channelId`;
- `yt:channelStatistics subscriberCount='<số>'`. Kênh VEVO: YouTube không hiện số người đăng ký nên là 0;
- `gd:feedLink rel='…#channel.content'` trỏ tới `<base>/feeds/api/users/<id>/uploads`, `countHint` là số video;
- `media:thumbnail url='https://yt3…=s88…'`: avatar JPEG cỡ nhỏ.

Thiếu `q` thì `404`.

### `GET /feeds/api/channels/<channel id>` và `GET /feeds/api/users/<channel id>`

Một entry kênh (gốc là `<entry>` có khai báo namespace), cùng trường như trên. App cũ gọi route này cho từng kênh trong danh sách để
lấy avatar, nên được cache 60 phút.

### `GET /feeds/api/users/<channel id>/playlists`

Playlist của kênh, có phân trang. `params` của tab Playlist được đọc từ chính phản hồi trang kênh, vì YouTube đổi giá trị này. Mỗi
entry gồm:

- `title`, `author`, `yt:playlistId`, `yt:countHint` (số video);
- `gd:feedLink rel='…#playlist'` trỏ tới `<base>/feeds/api/playlists/<id>`;
- `media:thumbnail` là ảnh của video đầu playlist.

### `GET /feeds/api/playlists/snippets?q=<từ khóa>`

Tìm playlist, cùng định dạng như trên. Thiếu `q` thì `404`.

### `GET /feeds/api/playlists/<playlist id>`

Video trong playlist (feed video), có phân trang bằng `skip` / `continuation`. `max-results=0` thì `404`, giống TubeRepair.

### `GET /feeds/api/videos/<id>/comments` và `GET /api/videos/<id>/comments`

Bình luận cấp cao nhất, chỉ đọc, có phân trang. Mỗi entry gồm:

- `id` (`tag:youtube.com,2008:video:<id>:comment:<comment id>`), `published` (ước lượng từ "3 năm trước");
- `content` (nội dung), `author` (`name`, `yt:userId`), `yt:channelId`, `yt:replyCount`.

Video tắt bình luận thì trả feed rỗng.

### App "classic" (User-Agent chứa `YouTube v1.0.0` hoặc `youtube/1.0.0`)

App YouTube có sẵn của Apple trên iOS 5 trở về trước. Giống TubeRepair, trang chủ, tìm kiếm và liên quan trả định dạng riêng:

- namespace `yt` chuẩn (`http://gdata.youtube.com/schemas/2007`);
- `<content type='video/mp4' src='<base>/video/sd/<id>'>`;
- trang chủ tối đa 15 video, không có `rel='next'`.

App này đọc địa chỉ server từ khóa `ConfiguredServiceHost` (tweak TubeRepair tự ghi).

### Không làm

Đăng nhập thật, thích / không thích, viết bình luận, upload, `/feeds/api/partners/<id>/branding/default` (banner kênh; app vẫn chạy
khi route này trả 404).

## Lớp mở rộng `/tm/v1` (cho app TubeMini)

App TubeMini dùng **lớp GData ở trên** cho mọi danh sách (tìm kiếm, liên quan, bình luận, video của kênh) và dùng `/tm/v1` cho các
tính năng riêng.

Quy ước:

- XML UTF-8, namespace `xmlns:tm="urn:tubemini:1"`, `Content-Type: application/xml; charset=UTF-8`.
- **Token:** nếu `auth_token` trong config khác rỗng thì mọi route `/tm/v1` (kể cả `ping`) bắt buộc có header
  `X-Auth-Token: <token>`. Thiếu hoặc sai thì trả `401` kèm `tm:error code="unauthorized"`. Lớp GData không bị ảnh hưởng.
- **Lỗi:** trả HTTP status phù hợp kèm một phần tử duy nhất. `message` viết bằng tiếng Việt để app hiện thẳng cho người dùng:
  ```xml
  <tm:error xmlns:tm="urn:tubemini:1" code="no_stream" message="Không lấy được link phát cho video này."/>
  ```

  | `code` | HTTP | Khi nào |
  | --- | --- | --- |
  | `unauthorized` | 401 | Thiếu hoặc sai `X-Auth-Token` |
  | `bad_request` | 400 | ID video sai |
  | `no_stream` | 502 | yt-dlp không lấy được link (video riêng tư, bị chặn vùng, yt-dlp hỏng…) |
  | `not_found` | 404 | Route không tồn tại dưới `/tm/v1` |

### `GET /tm/v1/ping`

Trạng thái server, dùng cho nút "Kiểm tra kết nối" trong Cài đặt.

```xml
<tm:ping xmlns:tm="urn:tubemini:1" server="0.3.0" yt_dlp="2026.10.26" deno="deno 2.9.8 (stable, release, x86_64-pc-windows-msvc)"
         time="1794709999" auth="off"/>
```

- `yt_dlp` / `deno`: phiên bản, hoặc rỗng nếu thiếu (app báo "Máy chủ thiếu yt-dlp" hoặc "thiếu Deno").
- `time`: giờ server (Unix giây). `auth`: `on` hoặc `off`.

### `GET /tm/v1/videos/<id>/streams[?fresh=1]`

Các lựa chọn chất lượng, gọi ngay trước khi phát.

```xml
<tm:streams xmlns:tm="urn:tubemini:1" video_id="dQw4w9WgXcQ" expire="1794730000" available_in="4">
  <tm:stream quality="360" kind="mp4" url="https://rr3---sn-....googlevideo.com/videoplayback?..."/>
  <tm:stream quality="720" kind="hls" url="http://192.168.1.10:8080/720/getvideo/dQw4w9WgXcQ"/>
</tm:streams>
```

- `kind="mp4"`: link MP4 progressive ≤ 360p (H.264 + AAC), tải thẳng từ googlevideo.
  - Nếu tiếng của MP4 là bản lồng tiếng AI chứ không phải tiếng gốc (D23), mục 360 được thay bằng `kind="hls"` trỏ tới
    `<base>/360/getvideo/<id>` (HLS 360p, tiếng gốc). App coi hai kiểu như nhau.
- `kind="hls"`: playlist HLS đã lọc trên server; segment vẫn tải thẳng từ googlevideo.
  - `quality` là độ phân giải thật của biến thể còn lại sau khi lọc, có thể nhỏ hơn 720. Ví dụ video chỉ có 720p60 thì là 480.
  - Không có HLS dùng được thì không có phần tử này.
- `available_in`: **số giây app phải chờ** rồi mới bắt đầu phát (D17: video có quảng cáo đầu bị khóa link tới lúc đó); 0 là phát được
  ngay. App hiện đếm ngược. URL HLS trỏ về `/getvideo` của server nên server cũng tự chờ.
- `expire`: Unix giây lúc link hết hạn. Link được cache 5 phút. Phát lỗi (403 hoặc hết hạn) thì gọi lại với `fresh=1` một lần.
- Thứ tự: 360 trước, HLS sau. App chọn theo chất lượng mặc định trong Cài đặt.

### Chưa làm (Giai đoạn 4)

`/tm/v1/subscriptions`, `/tm/v1/feed`, `/tm/v1/history`.
