# API của tubemini-server

Đây là hợp đồng giữa server và các app. **Đổi API thì sửa file này trước.**

Trạng thái: Giai đoạn 0, mới có các trang debug. Lớp GData (Giai đoạn 1–2) và lớp `/tm/v1` (Giai đoạn 3–4) sẽ được ghi vào đây khi
làm.

## Quy ước chung

- HTTP thuần trong LAN, mặc định `0.0.0.0:8080`.
- XML: UTF-8, escape đúng mọi chuỗi, thời gian theo ISO 8601, thời lượng tính bằng giây, lượt xem là số nguyên.
- Video không bao giờ đi qua server: server chỉ trả redirect 307 hoặc playlist HLS đã lọc, các segment vẫn trỏ thẳng tới
  googlevideo.
- Tiền tố độ phân giải `/{res}/...` áp dụng cho mọi route của lớp GData.

## Trang debug (HTML, cho người xem)

### `GET /`

Phiên bản server, trạng thái yt-dlp / deno (có hay thiếu) và cấu hình chính.

### `GET /gd0?id=<ID hoặc link YouTube>` (tạm thời, Giai đoạn 0)

Trang thử tải trực tiếp, dùng trên Safari của iPad:

1. Ảnh `https://i.ytimg.com/vi/<id>/mqdefault.jpg`, phải hiện mà không báo lỗi chứng chỉ.
2. Nút "Phát video": link googlevideo format 18 (360p, H.264 + AAC) do `yt-dlp --force-ipv4 -g -f 18` trả về.
3. IP và client dùng để xin link, và số phút link còn hạn.

Không có `id` thì trang chỉ hiện ô nhập và hai video mẫu. ID sai thì báo lỗi; yt-dlp lỗi thì hiện câu lỗi cuối của yt-dlp.

## Lớp tương thích GData — chưa làm (Giai đoạn 1–2)

## Lớp mở rộng `/tm/v1` — chưa làm (Giai đoạn 3–4)
