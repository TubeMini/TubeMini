//! Proxy fallback (`proxy_fallback = true`, off by default): googlevideo bytes go through the server,
//! for an iPad outside the home network where links bound to the server's IP are refused
//! (docs/API.md, D28).
//!
//! URLs are `<base>/proxy/<sig>/<base64url(target)>.<ext>`. Only the server makes them: `sig` is a
//! SipHash of the target under a random per-start key, and the target must be on googlevideo, so the
//! route cannot be used as an open proxy. `Range` is forwarded (seeking works); HLS playlists are
//! rewritten so their variants and segments come through here too.

use std::hash::{BuildHasher, Hasher};

use axum::body::Body;
use axum::extract::{Path, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::response::{IntoResponse, Response};
use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;

use super::hls;
use crate::gdata::base_url;
use crate::state::AppState;

/// Signature of a target URL (hex SipHash, keyed per server start).
pub fn sign(st: &AppState, target: &str) -> String {
    let mut h = st.proxy_key.build_hasher();
    h.write(target.as_bytes());
    format!("{:016x}", h.finish())
}

/// File-type hint for the player; the handler goes by the upstream Content-Type.
fn extension(target: &str) -> &'static str {
    let path = target.split('?').next().unwrap_or(target);
    if path.ends_with(".ts") || path.ends_with(".aac") {
        "ts"
    } else if path.ends_with(".m3u8") || target.contains("manifest.googlevideo.com") {
        "m3u8"
    } else if target.contains("mime=video%2Fmp4") || target.contains("itag=18") {
        "mp4"
    } else {
        "ts"
    }
}

/// The proxied form of `target`, under the server address `base` (no resolution prefix).
pub fn url(st: &AppState, base: &str, target: &str) -> String {
    format!(
        "{base}/proxy/{}/{}.{}",
        sign(st, target),
        URL_SAFE_NO_PAD.encode(target),
        extension(target)
    )
}

/// Every URI of a playlist proxied; relative ones are resolved against `playlist_url` first.
pub fn rewrite_playlist(st: &AppState, base: &str, playlist: &str, playlist_url: &str) -> String {
    let parent = reqwest::Url::parse(playlist_url).ok();
    hls::map_uris(playlist, |uri| {
        let absolute = match &parent {
            Some(p) => p
                .join(uri)
                .map(String::from)
                .unwrap_or_else(|_| uri.to_owned()),
            None => uri.to_owned(),
        };
        url(st, base, &absolute)
    })
}

/// https on a googlevideo host only.
fn allowed(target: &str) -> bool {
    reqwest::Url::parse(target).is_ok_and(|u| {
        u.scheme() == "https"
            && u.host_str()
                .is_some_and(|h| h.ends_with(".googlevideo.com"))
    })
}

fn decode(payload: &str) -> Option<String> {
    let b64 = payload.rsplit_once('.').map_or(payload, |(b, _)| b);
    String::from_utf8(URL_SAFE_NO_PAD.decode(b64).ok()?).ok()
}

pub async fn proxy(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path((sig, payload)): Path<(String, String)>,
) -> Response {
    if !st.cfg.proxy_fallback {
        return StatusCode::NOT_FOUND.into_response();
    }
    let Some(target) = decode(&payload).filter(|t| sign(&st, t) == sig && allowed(t)) else {
        return StatusCode::FORBIDDEN.into_response();
    };
    let mut req = st.proxy_http.get(&target);
    if let Some(range) = headers.get(header::RANGE) {
        req = req.header(header::RANGE, range.clone());
    }
    let resp = match req.send().await {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!("proxy: {e:#}");
            return StatusCode::BAD_GATEWAY.into_response();
        }
    };
    let status = resp.status();
    // The upstream type decides (a segment must never be read as text); the hint only without one
    let is_playlist = match resp
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
    {
        Some(t) => t.contains("mpegurl"),
        None => payload.ends_with(".m3u8"),
    };
    if is_playlist && status.is_success() {
        let text = match resp.text().await {
            Ok(t) => t,
            Err(e) => {
                tracing::warn!("proxy playlist: {e:#}");
                return StatusCode::BAD_GATEWAY.into_response();
            }
        };
        let body = rewrite_playlist(&st, &base_url(&headers, None), &text, &target);
        return (
            [
                (header::CONTENT_TYPE, "application/vnd.apple.mpegurl"),
                (header::CACHE_CONTROL, "no-store"),
            ],
            body,
        )
            .into_response();
    }
    let mut out = Response::builder().status(status.as_u16());
    for name in [
        header::CONTENT_TYPE,
        header::CONTENT_LENGTH,
        header::CONTENT_RANGE,
        header::ACCEPT_RANGES,
        header::LAST_MODIFIED,
        header::ETAG,
    ] {
        if let Some(value) = resp.headers().get(&name) {
            out = out.header(name, value.clone());
        }
    }
    out.body(Body::from_stream(resp.bytes_stream()))
        .unwrap_or_else(|_| StatusCode::BAD_GATEWAY.into_response())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state(proxy: bool) -> AppState {
        let cfg = crate::config::Config {
            proxy_fallback: proxy,
            ..Default::default()
        };
        let tools = crate::youtube::ytdlp::ToolStatus {
            yt_dlp: Ok("x".into()),
            deno: Ok("x".into()),
        };
        AppState::with_store(cfg, tools, crate::store::Store::memory().unwrap()).unwrap()
    }

    #[test]
    fn urls_roundtrip_and_are_signed() {
        let st = state(true);
        let target =
            "https://rr3---sn-x.googlevideo.com/videoplayback?expire=1&itag=18&mime=video%2Fmp4";
        let u = url(&st, "http://10.0.0.2:8080", target);
        let rest = u.strip_prefix("http://10.0.0.2:8080/proxy/").unwrap();
        let (sig, payload) = rest.split_once('/').unwrap();
        assert!(payload.ends_with(".mp4"));
        assert_eq!(decode(payload).as_deref(), Some(target));
        assert_eq!(sig, sign(&st, target));
        // Another server start (another key) does not accept it
        assert_ne!(sig, sign(&state(true), target));
        assert!(allowed(target));
        assert!(!allowed("https://example.com/videoplayback"));
        assert!(!allowed("http://rr3---sn-x.googlevideo.com/x"));
        assert!(!allowed("https://googlevideo.com.evil.net/x"));
    }

    #[test]
    fn playlists_are_rewritten_with_relative_uris_resolved() {
        let st = state(true);
        let playlist = "#EXTM3U\n#EXTINF:5,\nhttps://rr1---sn-a.googlevideo.com/videoplayback/sq/1/file/seg.ts\n#EXTINF:5,\nseg2.ts\n";
        let out = rewrite_playlist(
            &st,
            "http://h:8080",
            playlist,
            "https://manifest.googlevideo.com/api/manifest/hls_playlist/x/index.m3u8",
        );
        let uris: Vec<_> = out.lines().filter(|l| !l.starts_with('#')).collect();
        assert_eq!(uris.len(), 2);
        assert!(
            uris.iter()
                .all(|u| u.starts_with("http://h:8080/proxy/") && u.ends_with(".ts"))
        );
        let second = decode(uris[1].rsplit('/').next().unwrap()).unwrap();
        assert_eq!(
            second,
            "https://manifest.googlevideo.com/api/manifest/hls_playlist/x/seg2.ts"
        );
    }

    async fn get(st: AppState, path: &str) -> StatusCode {
        use tower::ServiceExt;
        let app = axum::Router::new()
            .route("/proxy/{sig}/{payload}", axum::routing::get(proxy))
            .with_state(st);
        app.oneshot(axum::http::Request::get(path).body(Body::empty()).unwrap())
            .await
            .unwrap()
            .status()
    }

    #[tokio::test]
    async fn refuses_when_off_or_unsigned() {
        let target = "https://rr3---sn-x.googlevideo.com/videoplayback?itag=18";
        let on = state(true);
        let good = url(&on, "", target);
        assert_eq!(get(state(false), &good).await, StatusCode::NOT_FOUND);
        let forged = good.replace(&sign(&on, target), "0000000000000000");
        assert_eq!(get(on.clone(), &forged).await, StatusCode::FORBIDDEN);
        let elsewhere = url(&on, "", "https://example.com/x");
        assert_eq!(get(on, &elsewhere).await, StatusCode::FORBIDDEN);
    }
}
