//! Shared application state handed to every handler.

use std::ops::Deref;
use std::sync::Arc;

use anyhow::Result;

use crate::config::Config;
use crate::youtube::MetadataProvider;
use crate::youtube::innertube::InnerTube;
use crate::youtube::streams::{StreamResolver, YtDlpResolver};
use crate::youtube::ytdlp::{ToolStatus, YtDlp};

#[derive(Clone)]
pub struct AppState(Arc<Inner>);

pub struct Inner {
    pub cfg: Config,
    pub tools: ToolStatus,
    pub ytdlp: YtDlp,
    pub meta: Box<dyn MetadataProvider>,
    pub streams: Box<dyn StreamResolver>,
    /// Random key returned by the fake login routes (one per server start, like TubeRepair).
    pub device_key: String,
}

impl AppState {
    pub fn new(cfg: Config, tools: ToolStatus) -> Result<Self> {
        let ytdlp = YtDlp::new(&cfg);
        let meta = Box::new(InnerTube::new(&cfg)?);
        let streams = Box::new(YtDlpResolver::new(ytdlp.clone()));
        Ok(Self(Arc::new(Inner {
            cfg,
            tools,
            ytdlp,
            meta,
            streams,
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
