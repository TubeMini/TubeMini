//! Human-facing debug pages (plain HTML, simple enough for Safari on iOS 6).
//!
//! `/gd0` is the Phase 0 direct-download check: it shows a googlevideo link (format 18) and an
//! i.ytimg.com thumbnail so Safari on the iPad fetches both straight from Google.

use std::fmt::Write as _;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::Router;
use axum::extract::{Query, State};
use axum::response::Html;
use axum::routing::get;
use serde::Deserialize;

use crate::state::AppState;
use crate::youtube::VideoId;
use crate::youtube::ytdlp::url_param;

pub fn routes() -> Router<AppState> {
    Router::new().route("/", get(index)).route("/gd0", get(gd0))
}

/// Escapes text for HTML element content and quoted attribute values.
pub fn escape_html(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(c),
        }
    }
    out
}

fn page(title: &str, body: &str) -> Html<String> {
    Html(format!(
        "<!DOCTYPE html><html><head><meta charset=\"utf-8\">\
         <meta name=\"viewport\" content=\"width=device-width\">\
         <title>{t}</title><style>\
         body{{font-family:Helvetica,Arial,sans-serif;margin:16px;line-height:1.4}}\
         code{{background:#eee;padding:1px 4px}} .ok{{color:#070}} .err{{color:#b00}}\
         a.big{{display:inline-block;padding:10px 16px;background:#c00;color:#fff;text-decoration:none;margin:6px 0}}\
         input{{font-size:16px}}</style></head><body><h2>{t}</h2>{body}</body></html>",
        t = escape_html(title)
    ))
}

fn tool_line(name: &str, status: &Result<String, String>) -> String {
    match status {
        Ok(v) => format!("<li>{name}: <span class=ok>{}</span></li>", escape_html(v)),
        Err(e) => format!(
            "<li>{name}: <span class=err>THIẾU — {}</span></li>",
            escape_html(e)
        ),
    }
}

#[derive(Deserialize)]
struct IndexQuery {
    q: Option<String>,
}

async fn index(State(st): State<AppState>, Query(iq): Query<IndexQuery>) -> Html<String> {
    let mut body = String::new();
    let _ = write!(
        body,
        "<p>tubemini-server {}</p><ul>{}{}</ul>\
         <p>Cấu hình: lắng nghe <code>{}</code>, IPv4 <code>{}</code>, vùng <code>{}</code>, \
         ngôn ngữ <code>{}</code>, token /tm/v1 <code>{}</code></p>\
         <p>App YouTube cũ + TubeRepair: Custom URL <code>http://&lt;IP máy này&gt;:8080</code> \
         (thêm <code>/720</code> để xem HLS).</p>\
         <p>XML mẫu: <a href=\"/feeds/api/standardfeeds/VN/most_popular\">trang chủ</a> · \
         <a href=\"/feeds/api/videos?q=nh%E1%BA%A1c+tr%E1%BA%BB\">tìm kiếm</a> · \
         <a href=\"/feeds/api/videos/aqz-KE-bpKQ/related\">liên quan</a> · \
         <a href=\"/feeds/api/users/UCSMOQeBJ2RAnuFungnQOxLg/uploads\">video của kênh</a> · \
         <a href=\"/schemas/2007/categories.cat\">danh mục</a> · \
         <a href=\"/gd0\">thử tải trực tiếp</a></p>\
         <form action=\"/\"><input name=q size=30 placeholder=\"Tìm video\"> \
         <input type=submit value=\"Tìm\"></form>",
        env!("CARGO_PKG_VERSION"),
        tool_line("yt-dlp", &st.tools.yt_dlp),
        tool_line("deno", &st.tools.deno),
        escape_html(&st.cfg.listen),
        st.cfg.force_ipv4,
        escape_html(&st.cfg.region),
        escape_html(&st.cfg.language),
        if st.cfg.auth_token.is_empty() {
            "tắt"
        } else {
            "bật"
        },
    );
    if let Some(q) = iq.q.as_deref().map(str::trim).filter(|q| !q.is_empty()) {
        match st.meta.search(q, Default::default(), None).await {
            Ok(page) => {
                for v in &page.videos {
                    let _ = write!(
                        body,
                        "<p><a href=\"/getvideo/{id}\"><img src=\"https://i.ytimg.com/vi/{id}/mqdefault.jpg\" \
                         width=160 height=90 align=left style=\"margin-right:8px\"></a>\
                         <b>{t}</b><br>{a} · {d}:{s:02} · {views} lượt xem<br>\
                         <a href=\"/getvideo/{id}\">360p</a> · <a href=\"/720/getvideo/{id}\">HLS</a></p>\
                         <br clear=all>",
                        id = escape_html(&v.id),
                        t = escape_html(&v.title),
                        a = escape_html(&v.author),
                        d = v.duration / 60,
                        s = v.duration % 60,
                        views = v.views,
                    );
                }
            }
            Err(e) => {
                let _ = write!(
                    body,
                    "<p class=err>Lỗi tìm kiếm: {}</p>",
                    escape_html(&format!("{e:#}"))
                );
            }
        }
    }
    page("TubeMini server", &body)
}

#[derive(Deserialize)]
struct Gd0Query {
    id: Option<String>,
}

const SAMPLE_IDS: [(&str, &str); 2] = [
    ("jNQXAC9IVRw", "Me at the zoo (19 giây)"),
    ("aqz-KE-bpKQ", "Big Buck Bunny (10 phút, thử tua)"),
];

async fn gd0(State(st): State<AppState>, Query(q): Query<Gd0Query>) -> Html<String> {
    let mut body = String::from(
        "<form action=\"/gd0\"><input name=id size=30 placeholder=\"ID hoặc link YouTube\"> \
         <input type=submit value=\"Lấy link\"></form><p>Video mẫu: ",
    );
    for (id, label) in SAMPLE_IDS {
        let _ = write!(body, "<a href=\"/gd0?id={id}\">{label}</a> · ");
    }
    body.push_str("</p>");

    let Some(input) = q.id.filter(|s| !s.trim().is_empty()) else {
        return page("Thử tải trực tiếp", &body);
    };
    let Some(id) = VideoId::from_input(&input) else {
        let _ = write!(
            body,
            "<p class=err>Không nhận ra ID video: {}</p>",
            escape_html(&input)
        );
        return page("Thử tải trực tiếp", &body);
    };

    let thumb = format!("https://i.ytimg.com/vi/{id}/mqdefault.jpg");
    let _ = write!(
        body,
        "<h3>Video {id}</h3><p>1. Ảnh từ i.ytimg.com (phải hiện, không báo lỗi chứng chỉ):<br>\
         <img src=\"{thumb}\" width=320 height=180 alt=\"(ảnh lỗi)\"><br><a href=\"{thumb}\">Mở riêng ảnh</a></p>"
    );

    match st.ytdlp.media_urls(&id, "18").await {
        Ok(urls) => {
            let url = &urls[0];
            let ip = url_param(url, "ip").unwrap_or("?");
            let client = url_param(url, "c").unwrap_or("?");
            let minutes = url_param(url, "expire")
                .and_then(|e| e.parse::<u64>().ok())
                .map(|exp| {
                    let now = SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .map(|d| d.as_secs())
                        .unwrap_or(0);
                    exp.saturating_sub(now) / 60
                });
            let _ = write!(
                body,
                "<p>2. Video 360p (format 18) tải thẳng từ googlevideo.com — phải phát và tua được:<br>\
                 <a class=big href=\"{u}\">▶ Phát video</a></p>\
                 <p>Link xin bằng IP <code>{ip}</code>, client <code>{client}</code>, còn hạn khoảng \
                 <b>{m}</b> phút.</p>\
                 <p>3. Thử khác mạng: để nguyên trang này, chuyển Wi-Fi iPad sang điểm phát 4G của \
                 điện thoại, rồi bấm lại nút Phát. Ghi lại phát được hay báo lỗi.</p>\
                 <details><summary>Link đầy đủ</summary><p style=\"word-break:break-all\"><code>{u}</code></p></details>",
                u = escape_html(url),
                ip = escape_html(ip),
                client = escape_html(client),
                m = minutes.map_or_else(|| "?".to_owned(), |m| m.to_string()),
            );
        }
        Err(e) => {
            tracing::warn!("gd0 {id}: {e:#}");
            let _ = write!(
                body,
                "<p class=err>Không lấy được link video: {}</p>",
                escape_html(&format!("{e:#}"))
            );
        }
    }
    page("Thử tải trực tiếp", &body)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escapes_html() {
        assert_eq!(
            escape_html(r#"a&b<c>"d"'e Tiếng Việt 🎵"#),
            "a&amp;b&lt;c&gt;&quot;d&quot;&#39;e Tiếng Việt 🎵"
        );
    }
}
