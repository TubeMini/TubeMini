//! `/tm/v1` — extension API for the TubeMini app (docs/API.md). XML with `xmlns:tm="urn:tubemini:1"`;
//! errors are a single `<tm:error code message/>` with a Vietnamese message the app shows as is.
//! Lists (subscriptions, feed, history) reuse the GData Atom formats.

use askama::Template;
use axum::Router;
use axum::extract::{Path, Query, Request, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use axum::routing::{any, get};
use serde::Deserialize;

mod library;

use crate::gdata::base_url;
use crate::state::AppState;
use crate::youtube::{VideoId, parse};

pub fn routes(st: AppState) -> Router<AppState> {
    Router::new()
        .route("/tm/v1/ping", get(ping))
        .route("/tm/v1/videos/{id}/streams", get(streams))
        .route(
            "/tm/v1/subscriptions",
            get(library::subscriptions).post(library::subscribe),
        )
        .route(
            "/tm/v1/subscriptions/{id}",
            axum::routing::delete(library::unsubscribe),
        )
        .route("/tm/v1/feed", get(library::feed))
        .route(
            "/tm/v1/history",
            get(library::history)
                .post(library::save_position)
                .delete(library::clear_history),
        )
        .route(
            "/tm/v1/history/{id}",
            get(library::history_entry).delete(library::forget),
        )
        .route("/tm/v1/{*rest}", any(unknown))
        .route_layer(axum::middleware::from_fn_with_state(st, require_token))
}

const XML: &str = "application/xml; charset=UTF-8";

#[derive(Template)]
#[template(path = "tm/error.xml")]
struct ErrorXml<'a> {
    code: &'a str,
    message: &'a str,
}

/// A `<tm:error>` response.
pub fn tm_error(status: StatusCode, code: &str, message: &str) -> Response {
    let body = ErrorXml { code, message }
        .render()
        .unwrap_or_else(|_| format!("<tm:error code=\"{code}\"/>"));
    (status, [(header::CONTENT_TYPE, XML)], body).into_response()
}

fn xml_ok(rendered: askama::Result<String>) -> Response {
    match rendered {
        Ok(body) => ([(header::CONTENT_TYPE, XML)], body).into_response(),
        Err(e) => {
            tracing::error!("template: {e}");
            tm_error(
                StatusCode::INTERNAL_SERVER_ERROR,
                "internal",
                "Lỗi máy chủ.",
            )
        }
    }
}

/// `X-Auth-Token` must match `auth_token` when one is configured.
async fn require_token(State(st): State<AppState>, req: Request, next: Next) -> Response {
    let expected = st.cfg.auth_token.as_str();
    if !expected.is_empty() {
        let given = req
            .headers()
            .get("x-auth-token")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("");
        if given != expected {
            return tm_error(
                StatusCode::UNAUTHORIZED,
                "unauthorized",
                "Sai hoặc thiếu mã truy cập. Kiểm tra mục Mã truy cập trong Cài đặt.",
            );
        }
    }
    next.run(req).await
}

async fn unknown() -> Response {
    tm_error(
        StatusCode::NOT_FOUND,
        "not_found",
        "Máy chủ không có chức năng này. Có thể máy chủ cũ hơn app.",
    )
}

#[derive(Template)]
#[template(path = "tm/ping.xml")]
struct PingXml<'a> {
    server: &'a str,
    yt_dlp: &'a str,
    deno: &'a str,
    time: i64,
    auth: &'a str,
    proxy: &'a str,
}

async fn ping(State(st): State<AppState>) -> Response {
    xml_ok(
        PingXml {
            server: env!("CARGO_PKG_VERSION"),
            yt_dlp: st.tools.yt_dlp.as_deref().unwrap_or(""),
            deno: st.tools.deno.as_deref().unwrap_or(""),
            time: parse::now(),
            auth: if st.cfg.auth_token.is_empty() {
                "off"
            } else {
                "on"
            },
            proxy: if st.cfg.proxy_fallback { "on" } else { "off" },
        }
        .render(),
    )
}

/// HLS levels offered besides the 360p entry. The iPad mini 1 (A5) decodes H.264 up to 1080p30 (D25).
const HLS_LEVELS: [u32; 2] = [720, 1080];

struct StreamItem {
    quality: u32,
    kind: &'static str,
    url: String,
}

#[derive(Template)]
#[template(path = "tm/streams.xml")]
struct StreamsXml<'a> {
    video_id: &'a str,
    expire: i64,
    available_in: i64,
    proxy: bool,
    streams: &'a [StreamItem],
    /// `/getaudio` link (videos with HLS).
    audio: Option<String>,
    /// Progressive MP4 to download, and whether its audio is an AI dub.
    download: Option<(String, bool)>,
}

#[derive(Deserialize)]
struct FreshQuery {
    fresh: Option<String>,
    proxy: Option<String>,
}

fn flag(value: Option<&str>) -> bool {
    value.is_some_and(|f| f == "1" || f == "true")
}

async fn streams(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Query(q): Query<FreshQuery>,
) -> Response {
    let Some(id) = VideoId::parse(&id) else {
        return tm_error(
            StatusCode::BAD_REQUEST,
            "bad_request",
            "Mã video không hợp lệ.",
        );
    };
    let fresh = flag(q.fresh.as_deref());
    // Everything through the server: only when asked and allowed (`proxy_fallback`)
    let proxy = st.cfg.proxy_fallback && flag(q.proxy.as_deref());
    let base = base_url(&headers, None);
    let suffix = if proxy { "?proxy=1" } else { "" };
    let mp4 = |url: &str| {
        if proxy {
            crate::video::proxy::url(&st, &base, url)
        } else {
            url.to_owned()
        }
    };
    let info = match st.streams.resolve(&id, fresh).await {
        Ok(info) => info,
        Err(e) => {
            tracing::warn!("streams {id}: {e:#}");
            return tm_error(
                StatusCode::BAD_GATEWAY,
                "no_stream",
                "Không lấy được link phát cho video này (video riêng tư, bị chặn hoặc YouTube vừa thay đổi).",
            );
        }
    };

    let mut items: Vec<StreamItem> = Vec::new();
    let hls_item = |res: u32, playlist: &str| StreamItem {
        quality: crate::video::hls::best_height(playlist).unwrap_or(res),
        kind: "hls",
        url: format!("{}/getvideo/{id}{suffix}", base_url(&headers, Some(res))),
    };
    // 360p: the MP4, unless its audio is an AI dub — then 360p HLS with the original audio
    match &info.progressive {
        Some(url) if !info.progressive_dubbed => items.push(StreamItem {
            quality: 360,
            kind: "mp4",
            url: mp4(url),
        }),
        _ if info.hls_manifest.is_some() => {
            match crate::video::hls_playlist(&st, &id, &info, 360, fresh).await {
                Ok(playlist) => items.push(hls_item(360, &playlist)),
                Err(e) => tracing::warn!("streams {id} HLS 360: {e:#}"),
            }
        }
        _ => {}
    }
    if items.is_empty()
        && let Some(url) = &info.progressive
    {
        // Dubbed but nothing better: still playable
        items.push(StreamItem {
            quality: 360,
            kind: "mp4",
            url: mp4(url),
        });
    }
    if info.hls_manifest.is_some() {
        match crate::video::hls_playlists(&st, &id, &info, &HLS_LEVELS, fresh).await {
            Ok(playlists) => {
                for (&res, playlist) in HLS_LEVELS.iter().zip(&playlists) {
                    let item = hls_item(res, playlist);
                    // Nothing above 360p, or no 1080p30: no duplicate entries
                    if !items.iter().any(|i| i.quality == item.quality) {
                        items.push(item);
                    }
                }
            }
            Err(e) => tracing::warn!("streams {id} HLS: {e:#}"),
        }
    }
    items.sort_by_key(|i| i.quality);
    if items.is_empty() {
        return tm_error(
            StatusCode::BAD_GATEWAY,
            "no_stream",
            "Video này không có định dạng iPad phát được.",
        );
    }
    let ready_at = info.progressive_at.max(info.hls_at);
    xml_ok(
        StreamsXml {
            video_id: &id.to_string(),
            expire: info.expire,
            available_in: (ready_at - parse::now()).max(0),
            proxy,
            streams: &items,
            audio: info
                .hls_manifest
                .as_ref()
                .map(|_| format!("{base}/getaudio/{id}{suffix}")),
            download: info
                .progressive
                .as_deref()
                .map(|url| (mp4(url), info.progressive_dubbed)),
        }
        .render(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_xml_is_escaped() {
        let xml = ErrorXml {
            code: "no_stream",
            message: "Lỗi \"lạ\" <x> & y",
        }
        .render()
        .unwrap();
        assert!(xml.contains("code=\"no_stream\""));
        assert!(xml.contains("Lỗi &#34;lạ&#34; &#60;x&#62; &#38; y"));
    }

    fn app(token: &str) -> Router {
        let cfg = crate::config::Config {
            auth_token: token.into(),
            ..Default::default()
        };
        let tools = crate::youtube::ytdlp::ToolStatus {
            yt_dlp: Ok("2026.10.26".into()),
            deno: Err("missing".into()),
        };
        let store = crate::store::Store::memory().unwrap();
        let st = AppState::with_store(cfg, tools, store).unwrap();
        routes(st.clone()).with_state(st)
    }

    /// One request; `body` is sent as a form.
    async fn send(
        app: &Router,
        method: &str,
        path: &str,
        token: Option<&str>,
        body: &str,
    ) -> (StatusCode, String) {
        use tower::ServiceExt;
        let mut req = axum::http::Request::builder().method(method).uri(path);
        if let Some(v) = token {
            req = req.header("X-Auth-Token", v);
        }
        if !body.is_empty() {
            req = req.header(header::CONTENT_TYPE, "application/x-www-form-urlencoded");
        }
        let resp = app
            .clone()
            .oneshot(req.body(axum::body::Body::from(body.to_owned())).unwrap())
            .await
            .unwrap();
        let status = resp.status();
        let body = axum::body::to_bytes(resp.into_body(), 1 << 20)
            .await
            .unwrap();
        (status, String::from_utf8_lossy(&body).into_owned())
    }

    async fn call(token: &str, header_value: Option<&str>, path: &str) -> (StatusCode, String) {
        send(&app(token), "GET", path, header_value, "").await
    }

    #[tokio::test]
    async fn token_is_enforced_only_when_configured() {
        let (s, body) = call("", None, "/tm/v1/ping").await;
        assert_eq!(s, StatusCode::OK);
        assert!(
            body.contains("auth=\"off\"")
                && body.contains("yt_dlp=\"2026.10.26\"")
                && body.contains("deno=\"\"")
        );

        let (s, body) = call("bí-mật", None, "/tm/v1/ping").await;
        assert_eq!(s, StatusCode::UNAUTHORIZED);
        assert!(body.contains("code=\"unauthorized\""));
        let (s, _) = call("bí-mật", Some("sai"), "/tm/v1/ping").await;
        assert_eq!(s, StatusCode::UNAUTHORIZED);
        let (s, body) = call("bi-mat", Some("bi-mat"), "/tm/v1/ping").await;
        assert_eq!(s, StatusCode::OK);
        assert!(body.contains("auth=\"on\""));
    }

    #[tokio::test]
    async fn bad_id_and_unknown_route() {
        let (s, body) = call("", None, "/tm/v1/videos/nope/streams").await;
        assert_eq!(s, StatusCode::BAD_REQUEST);
        assert!(body.contains("code=\"bad_request\""));
        let (s, body) = call("", None, "/tm/v1/watch-later").await;
        assert_eq!(s, StatusCode::NOT_FOUND);
        assert!(body.contains("code=\"not_found\""));
        let (s, _) = send(&app(""), "POST", "/tm/v1/nothing", None, "a=1").await;
        assert_eq!(s, StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn history_roundtrip() {
        let app = app("");
        // Never watched: position 0, still 200
        let (s, body) = send(&app, "GET", "/tm/v1/history/dQw4w9WgXcQ", None, "").await;
        assert_eq!(s, StatusCode::OK);
        assert!(
            body.contains("position=\"0\" duration=\"0\" watched=\"\""),
            "{body}"
        );

        // The app sends the title, so no YouTube lookup happens here
        let form = "video_id=dQw4w9WgXcQ&position=754.4&duration=1347&title=B%E1%BA%A3n+tin+%26+%3C60s%3E&author=HTV&author_id=UCabcdefghijklmnopqrstuv";
        let (s, body) = send(&app, "POST", "/tm/v1/history", None, form).await;
        assert_eq!(s, StatusCode::OK, "{body}");
        assert!(body.contains("video_id=\"dQw4w9WgXcQ\" position=\"754\" duration=\"1347\""));
        let (_, body) = send(&app, "GET", "/tm/v1/history/dQw4w9WgXcQ", None, "").await;
        assert!(body.contains("position=\"754\""));

        let (s, feed) = send(&app, "GET", "/tm/v1/history", None, "").await;
        assert_eq!(s, StatusCode::OK);
        assert!(feed.contains("xmlns:tm='urn:tubemini:1'"));
        assert!(
            feed.contains("<title>Bản tin &#38; &#60;60s&#62;</title>"),
            "{feed}"
        );
        assert!(feed.contains("<tm:position seconds='754'/>"));
        assert!(feed.contains("<yt:duration seconds='1347'/>"));
        assert!(feed.contains("<tm:watched>20"));

        let (s, body) = send(&app, "DELETE", "/tm/v1/history/dQw4w9WgXcQ", None, "").await;
        assert_eq!(s, StatusCode::OK);
        assert!(body.contains("<tm:ok"));
        let (_, feed) = send(&app, "GET", "/tm/v1/history", None, "").await;
        assert!(!feed.contains("<entry"));
        let (s, _) = send(&app, "DELETE", "/tm/v1/history", None, "").await;
        assert_eq!(s, StatusCode::OK);
    }

    #[tokio::test]
    async fn history_rejects_bad_input() {
        let app = app("");
        for form in [
            "",
            "video_id=nope&position=1",
            "video_id=dQw4w9WgXcQ",
            "video_id=dQw4w9WgXcQ&position=-5",
            "video_id=dQw4w9WgXcQ&position=abc",
        ] {
            let (s, body) = send(&app, "POST", "/tm/v1/history", None, form).await;
            assert_eq!(s, StatusCode::BAD_REQUEST, "{form}");
            assert!(body.contains("code=\"bad_request\""));
        }
    }

    #[tokio::test]
    async fn subscriptions_without_network() {
        let app = app("");
        let (s, body) = send(&app, "GET", "/tm/v1/subscriptions", None, "").await;
        assert_eq!(s, StatusCode::OK);
        assert!(body.contains("#channel") && !body.contains("<entry"));
        // Nothing subscribed: empty feed, no YouTube call
        let (s, body) = send(&app, "GET", "/tm/v1/feed?fresh=1", None, "").await;
        assert_eq!(s, StatusCode::OK);
        assert!(body.contains("tm:feed") && !body.contains("<entry"));
        let (s, body) = send(&app, "POST", "/tm/v1/subscriptions", None, "channel_id=xyz").await;
        assert_eq!(s, StatusCode::BAD_REQUEST);
        assert!(body.contains("code=\"bad_request\""));
        let (s, body) = send(
            &app,
            "DELETE",
            "/tm/v1/subscriptions/UCabcdefghijklmnopqrstuv",
            None,
            "",
        )
        .await;
        assert_eq!(s, StatusCode::OK);
        assert!(body.contains("<tm:ok"));
        // Token applies to the new routes too
        let (s, _) = send(&self::tests::app("k"), "GET", "/tm/v1/history", None, "").await;
        assert_eq!(s, StatusCode::UNAUTHORIZED);
    }

    #[test]
    fn streams_xml_shape() {
        let items = [
            StreamItem {
                quality: 360,
                kind: "mp4",
                url: "https://rr1.googlevideo.com/videoplayback?a=1&b=2".into(),
            },
            StreamItem {
                quality: 480,
                kind: "hls",
                url: "http://192.168.1.192:8080/720/getvideo/aqz-KE-bpKQ".into(),
            },
        ];
        let xml = StreamsXml {
            video_id: "aqz-KE-bpKQ",
            expire: 1_794_730_000,
            available_in: 4,
            proxy: false,
            streams: &items,
            audio: Some("http://192.168.1.192:8080/getaudio/aqz-KE-bpKQ".into()),
            download: Some((
                "https://rr1.googlevideo.com/videoplayback?a=1&b=2".into(),
                true,
            )),
        }
        .render()
        .unwrap();
        insta::assert_snapshot!(xml);
    }
}
