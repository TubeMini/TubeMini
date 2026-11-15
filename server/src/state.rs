//! Shared application state handed to every handler.

use std::net::{IpAddr, Ipv4Addr};
use std::ops::Deref;
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;

use crate::config::Config;
use crate::youtube::innertube::InnerTube;
use crate::youtube::streams::{StreamResolver, YtDlpResolver};
use crate::youtube::ytdlp::{ToolStatus, YtDlp};
use crate::youtube::{MetadataProvider, VideoId};

#[derive(Clone)]
pub struct AppState(Arc<Inner>);

pub struct Inner {
    pub cfg: Config,
    pub tools: ToolStatus,
    pub ytdlp: YtDlp,
    pub meta: Box<dyn MetadataProvider>,
    pub streams: Box<dyn StreamResolver>,
    /// Plain HTTP client (IPv4 when configured) for small fetches such as HLS master playlists.
    pub http: reqwest::Client,
    /// Filtered HLS master playlists per (video, resolution).
    pub playlists: moka::future::Cache<(VideoId, u32), Arc<String>>,
    /// Random key returned by the fake login routes (one per server start, like TubeRepair).
    pub device_key: String,
}

impl AppState {
    pub fn new(cfg: Config, tools: ToolStatus) -> Result<Self> {
        let ytdlp = YtDlp::new(&cfg);
        let meta = Box::new(InnerTube::new(&cfg)?);
        let streams = Box::new(YtDlpResolver::new(ytdlp.clone()));
        let mut http = reqwest::Client::builder().timeout(Duration::from_secs(15));
        if cfg.force_ipv4 {
            http = http.local_address(IpAddr::V4(Ipv4Addr::UNSPECIFIED));
        }
        Ok(Self(Arc::new(Inner {
            cfg,
            tools,
            ytdlp,
            meta,
            streams,
            http: http.build()?,
            playlists: moka::future::Cache::builder()
                .max_capacity(200)
                .time_to_live(crate::video::PLAYLIST_TTL)
                .build(),
            device_key: random_hex(),
        })))
    }
}

impl Deref for AppState {
    type Target = Inner;
    fn deref(&self) -> &Inner {
        &self.0
    }
}

/// 32 hex chars from the std hasher's random seed + time (no extra dependency needed).
fn random_hex() -> String {
    use std::hash::{BuildHasher, Hasher};
    let mut out = String::new();
    for i in 0..2u64 {
        let mut h = std::collections::hash_map::RandomState::new().build_hasher();
        h.write_u64(i);
        h.write_u128(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0),
        );
        out.push_str(&format!("{:016x}", h.finish()));
    }
    out
}
