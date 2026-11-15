# API của tubemini-server

Đây là hợp đồng giữa server và các app. **Đổi API thì sửa file này trước.**

Trạng thái: Giai đoạn 1. Đã có trang debug và lớp GData tối thiểu. Phần GData còn lại thuộc Giai đoạn 2, lớp `/tm/v1` thuộc Giai
đoạn 3–4.

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

Phân trang: còn trang sau thì có `<link rel='next' href='…?start-index=<n>&continuation=<token>'>`. App gọi lại đúng link đó, server
dùng `continuation` để lấy trang tiếp. `openSearch:totalResults` là số giả lớn (cộng thêm 1000) khi còn trang sau.

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

### `GET /getvideo/<id>[?fresh=1]`

Link phát. Server không chuyển tiếp dữ liệu video.

- Không có tiền tố độ phân giải (và `medium_quality = true`): **307** sang link MP4 progressive ≤ 360p (H.264 + AAC, thường là itag
  18) trên googlevideo. Video không có định dạng này thì trả HLS.
- Có tiền tố (`/720/getvideo/<id>`) hoặc `medium_quality = false`: **307** sang manifest HLS master của YouTube.
  - Giai đoạn 1 chưa lọc manifest; iOS 6 tự bỏ qua các biến thể VP9.
  - Giai đoạn 2 sẽ trả playlist đã lọc (avc1 + AAC, ≤ res, ≤ 30fps), `Content-Type: application/vnd.apple.mpegurl`.
- Link lấy bằng `yt-dlp --force-ipv4 -J`, cache 5 phút. `fresh=1` bỏ qua cache (app gọi khi thử lại sau lỗi 403).
- Không lấy được link: `502`. ID sai: `404`.

### Chưa làm (Giai đoạn 2)

`/feeds/api/channels?q=` (tìm kênh), `/feeds/api/channels/<id>` (thông tin kênh, avatar), bình luận (`/api/videos/<id>/comments`),
playlist, lọc HLS, phân biệt User-Agent (app 1.0.0 / classic).

## Lớp mở rộng `/tm/v1` — chưa làm (Giai đoạn 3–4)
