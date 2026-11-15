//! `/tm/v1` — extension API for the TubeMini app (docs/API.md). XML with `xmlns:tm="urn:tubemini:1"`;
//! errors are a single `<tm:error code message/>` with a Vietnamese message the app shows as is.
//! Video lists still come from the GData layer.

use askama::Template;
use axum::Router;
use axum::extract::{Path, Query, Request, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use serde::Deserialize;

use crate::gdata::base_url;
use crate::state::AppState;
use crate::youtube::{VideoId, parse};

pub fn routes(st: AppState) -> Router<AppState> {
    Router::new()
        .route("/tm/v1/ping", get(ping))
        .route("/tm/v1/videos/{id}/streams", get(streams))
        .route("/tm/v1/{*rest}", get(unknown))
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
        }
        .render(),
    )
}

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
    streams: &'a [StreamItem],
}

#[derive(Deserialize)]
struct FreshQuery {
    fresh: Option<String>,
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
    let fresh = q.fresh.as_deref().is_some_and(|f| f == "1" || f == "true");
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
        url: format!("{}/getvideo/{id}", base_url(&headers, Some(res))),
    };
    // 360p: the MP4, unless its audio is an AI dub — then 360p HLS with the original audio
    match &info.progressive {
        Some(url) if !info.progressive_dubbed => items.push(StreamItem {
            quality: 360,
            kind: "mp4",
            url: url.clone(),
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
            url: url.clone(),
        });
    }
    let res = st.cfg.hls_resolution.clamp(144, 2160);
    if info.hls_manifest.is_some() {
        match crate::video::hls_playlist(&st, &id, &info, res, fresh).await {
            Ok(playlist) => {
                let item = hls_item(res, &playlist);
                // Videos without anything above 360p: no second identical entry
                if !items
                    .iter()
                    .any(|i| i.kind == "hls" && i.quality == item.quality)
                {
                    items.push(item);
                }
            }
            Err(e) => tracing::warn!("streams {id} HLS: {e:#}"),
        }
    }
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
            streams: &items,
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

    async fn call(token: &str, header_value: Option<&str>, path: &str) -> (StatusCode, String) {
        use tower::ServiceExt;
        let cfg = crate::config::Config {
            auth_token: token.into(),
            ..Default::default()
        };
        let tools = crate::youtube::ytdlp::ToolStatus {
            yt_dlp: Ok("2026.10.26".into()),
            deno: Err("missing".into()),
        };
        let st = AppState::new(cfg, tools).unwrap();
        let app = routes(st.clone()).with_state(st);
        let mut req = axum::http::Request::get(path);
        if let Some(v) = header_value {
            req = req.header("X-Auth-Token", v);
        }
        let resp = app
            .oneshot(req.body(axum::body::Body::empty()).unwrap())
            .await
            .unwrap();
        let status = resp.status();
        let body = axum::body::to_bytes(resp.into_body(), 1 << 16)
            .await
            .unwrap();
        (status, String::from_utf8_lossy(&body).into_owned())
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
        let (s, body) = call("", None, "/tm/v1/subscriptions").await;
        assert_eq!(s, StatusCode::NOT_FOUND);
        assert!(body.contains("code=\"not_found\""));
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
            streams: &items,
        }
        .render()
        .unwrap();
        insta::assert_snapshot!(xml);
    }
}
