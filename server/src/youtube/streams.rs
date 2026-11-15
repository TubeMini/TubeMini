//! Playable stream URLs (360p progressive MP4 and the HLS manifest) via `yt-dlp -J`.

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, bail};
use serde_json::Value;

use super::ytdlp::YtDlp;
use super::{BoxFut, VideoId};

/// Links are short-lived and IP-bound: keep them only a few minutes.
const CACHE_TTL: Duration = Duration::from_secs(5 * 60);

/// What the iPad can play for one video.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct StreamInfo {
    /// Progressive MP4 with H.264 + AAC, height ≤ 360 (normally itag 18).
    pub progressive: Option<String>,
    /// Unix seconds from which `progressive` answers (0 = now). YouTube refuses the links with
    /// 403 until a pre-roll ad would have ended or become skippable; yt-dlp reports that moment
    /// as `available_at` (see `_get_available_at_timestamp` in yt-dlp's YouTube extractor).
    pub progressive_at: i64,
    /// The progressive MP4's (muxed) audio is not the original language — YouTube serves an AI dub
    /// (e.g. English over a Vietnamese video). Play the filtered HLS instead, which keeps the original.
    pub progressive_dubbed: bool,
    /// HLS master manifest (googlevideo); filtered by the server before the iPad sees it.
    pub hls_manifest: Option<String>,
    /// Like `progressive_at`, for the HLS formats.
    pub hls_at: i64,
    /// Unix seconds when the links expire (from the `expire` parameter), 0 = unknown.
    pub expire: i64,
}

pub trait StreamResolver: Send + Sync {
    /// `fresh` skips the cache (the app retries with `?fresh=1` after a 403).
    fn resolve<'a>(&'a self, id: &'a VideoId, fresh: bool) -> BoxFut<'a, Arc<StreamInfo>>;
}

pub struct YtDlpResolver {
    ytdlp: YtDlp,
    cache: moka::future::Cache<VideoId, Arc<StreamInfo>>,
}

impl YtDlpResolver {
    pub fn new(ytdlp: YtDlp) -> Self {
        Self {
            ytdlp,
            cache: moka::future::Cache::builder()
                .max_capacity(200)
                .time_to_live(CACHE_TTL)
                .build(),
        }
    }

    async fn fetch(&self, id: &VideoId) -> Result<Arc<StreamInfo>> {
        let json = self.ytdlp.run(&["-J", &id.watch_url()]).await?;
        let info: Value = serde_json::from_str(&json)?;
        let streams = streams_from_info(&info);
        if streams.progressive.is_none() && streams.hls_manifest.is_none() {
            bail!("no H.264 stream for {id}");
        }
        Ok(Arc::new(streams))
    }
}

impl StreamResolver for YtDlpResolver {
    fn resolve<'a>(&'a self, id: &'a VideoId, fresh: bool) -> BoxFut<'a, Arc<StreamInfo>> {
        Box::pin(async move {
            if fresh {
                self.cache.invalidate(id).await;
            }
            // Concurrent requests for the same video (prefetch + /getvideo) share one yt-dlp run
            self.cache
                .try_get_with_by_ref(id, self.fetch(id))
                .await
                .map_err(|e| anyhow::anyhow!("{e:#}"))
        })
    }
}

/// Picks the iPad-compatible streams out of yt-dlp's `-J` output.
pub fn streams_from_info(info: &Value) -> StreamInfo {
    let formats = info
        .get("formats")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    let s = |f: &Value, k: &str| {
        f.get(k)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned()
    };

    let at = |f: &Value| f.get("available_at").and_then(Value::as_i64).unwrap_or(0);

    // Same as the selector b[ext=mp4][vcodec^=avc1][acodec^=mp4a][height<=360], best first
    let progressive_fmt = formats
        .iter()
        .filter(|f| {
            s(f, "ext") == "mp4"
                && s(f, "vcodec").starts_with("avc1")
                && s(f, "acodec").starts_with("mp4a")
                && s(f, "protocol") == "https"
                && f.get("height")
                    .and_then(Value::as_u64)
                    .is_some_and(|h| h <= 360)
        })
        .max_by_key(|f| f.get("height").and_then(Value::as_u64).unwrap_or(0));
    let progressive = progressive_fmt.map(|f| s(f, "url"));

    // Original audio language: the audio format yt-dlp labels "original", else the video's language
    let primary = |l: &str| l.split(['-', '_']).next().unwrap_or("").to_lowercase();
    let lang = |f: &Value| f.get("language").and_then(Value::as_str).map(primary);
    let original = formats
        .iter()
        .find(|f| {
            s(f, "acodec") != "none" && s(f, "format_note").to_lowercase().contains("original")
        })
        .and_then(lang)
        .or_else(|| info.get("language").and_then(Value::as_str).map(primary));
    let progressive_dubbed = match (progressive_fmt.and_then(lang), original) {
        (Some(a), Some(o)) => !a.is_empty() && !o.is_empty() && a != o,
        _ => false,
    };

    let hls_fmt = formats
        .iter()
        .find(|f| s(f, "protocol").starts_with("m3u8") && f.get("manifest_url").is_some());
    let hls_manifest = hls_fmt.map(|f| s(f, "manifest_url"));

    let expire = progressive
        .as_deref()
        .or(hls_manifest.as_deref())
        .and_then(expire_of)
        .unwrap_or(0);
    StreamInfo {
        progressive,
        progressive_at: progressive_fmt.map_or(0, at),
        progressive_dubbed,
        hls_manifest,
        hls_at: hls_fmt.map_or(0, at),
        expire,
    }
}

/// `expire` from a googlevideo URL: query (`?expire=`) or path (`/expire/<n>/`) form.
fn expire_of(url: &str) -> Option<i64> {
    if let Some(v) = super::ytdlp::url_param(url, "expire") {
        return v.parse().ok();
    }
    let rest = url.split("/expire/").nth(1)?;
    rest.split('/').next()?.parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn picks_format_18_and_manifest() {
        let info = json!({ "formats": [
            { "format_id": "233", "protocol": "m3u8_native", "ext": "mp4", "vcodec": "none", "acodec": "mp4a.40.5",
              "url": "https://x/233", "manifest_url": "https://manifest.googlevideo.com/api/manifest/hls_variant/expire/1794726404/ei/x" },
            { "format_id": "160", "protocol": "https", "ext": "mp4", "vcodec": "avc1.4d400c", "acodec": "none", "height": 144, "url": "https://x/160" },
            { "format_id": "18", "protocol": "https", "ext": "mp4", "vcodec": "avc1.42001E", "acodec": "mp4a.40.2", "height": 360, "available_at": 1794709267,
              "url": "https://rr1---sn.googlevideo.com/videoplayback?expire=1794725568&itag=18" },
            { "format_id": "22", "protocol": "https", "ext": "mp4", "vcodec": "avc1.64001F", "acodec": "mp4a.40.2", "height": 720, "url": "https://x/22" },
        ]});
        let s = streams_from_info(&info);
        assert_eq!(
            s.progressive.as_deref(),
            Some("https://rr1---sn.googlevideo.com/videoplayback?expire=1794725568&itag=18")
        );
        assert!(s.hls_manifest.unwrap().contains("hls_variant"));
        assert_eq!(s.expire, 1_794_725_568);
        assert_eq!(s.progressive_at, 1_794_709_267);
        assert_eq!(s.hls_at, 0);
    }

    #[test]
    fn detects_dubbed_progressive_audio() {
        // Vietnamese video, format 18 carries the English AI dub
        let info = json!({ "language": "vi", "formats": [
            { "format_id": "251", "protocol": "https", "acodec": "opus", "vcodec": "none", "language": "vi",
              "format_note": "Vietnamese original (default), medium", "url": "https://x/251" },
            { "format_id": "18", "protocol": "https", "ext": "mp4", "vcodec": "avc1.42001E", "acodec": "mp4a.40.2",
              "height": 360, "language": "en", "url": "https://x/18" },
        ]});
        assert!(streams_from_info(&info).progressive_dubbed);
        // Same language (en-US vs en) is not a dub
        let same = json!({ "language": "en", "formats": [
            { "format_id": "18", "protocol": "https", "ext": "mp4", "vcodec": "avc1", "acodec": "mp4a", "height": 360,
              "language": "en-US", "url": "https://x/18" } ]});
        assert!(!streams_from_info(&same).progressive_dubbed);
        // No language info at all: assume fine
        let none = json!({ "formats": [
            { "format_id": "18", "protocol": "https", "ext": "mp4", "vcodec": "avc1", "acodec": "mp4a", "height": 360, "url": "https://x/18" } ]});
        assert!(!streams_from_info(&none).progressive_dubbed);
    }

    #[test]
    fn manifest_only() {
        let info = json!({ "formats": [
            { "protocol": "m3u8_native", "manifest_url": "https://m/api/manifest/hls_variant/expire/1794726404/ei/x" }
        ]});
        let s = streams_from_info(&info);
        assert!(s.progressive.is_none());
        assert_eq!(s.expire, 1_794_726_404);
    }
}
