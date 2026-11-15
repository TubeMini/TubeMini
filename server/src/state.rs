//! Shared application state handed to every handler.

use std::ops::Deref;
use std::sync::Arc;

use crate::config::Config;
use crate::youtube::ytdlp::{ToolStatus, YtDlp};

#[derive(Clone)]
pub struct AppState(Arc<Inner>);

pub struct Inner {
    pub cfg: Config,
    pub tools: ToolStatus,
    pub ytdlp: YtDlp,
}

impl AppState {
    pub fn new(cfg: Config, tools: ToolStatus) -> Self {
        let ytdlp = YtDlp::new(&cfg);
        Self(Arc::new(Inner { cfg, tools, ytdlp }))
    }
}

impl Deref for AppState {
    type Target = Inner;
    fn deref(&self) -> &Inner {
        &self.0
    }
}
