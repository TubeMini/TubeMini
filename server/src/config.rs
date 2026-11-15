//! Server configuration loaded from `config.toml` (next to the executable by default).

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::Deserialize;

/// Runtime configuration. Every field has a default so a missing file or key still works.
#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    /// Address to listen on, e.g. `0.0.0.0:8080`.
    pub listen: String,
    /// Shared token for `/tm/v1` (header `X-Auth-Token`). Empty = disabled.
    pub auth_token: String,
    /// Directory for SQLite and cache files (relative paths resolve against the config file).
    pub data_dir: PathBuf,
    /// `yt-dlp` command name or absolute path.
    pub yt_dlp_path: String,
    /// Maximum concurrent yt-dlp processes.
    pub max_ytdlp_procs: usize,
    /// Ask YouTube over IPv4 so the IP baked into links matches the iPad.
    pub force_ipv4: bool,
    /// `/getvideo` without a resolution prefix returns 360p progressive.
    pub medium_quality: bool,
    /// Default HLS resolution.
    pub hls_resolution: u32,
    /// Home feed of the old app: `popular` or `subscriptions`.
    pub home_feed: HomeFeed,
    /// Log search queries (off by default for privacy).
    pub log_queries: bool,
    pub region: String,
    pub language: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum HomeFeed {
    Popular,
    Subscriptions,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            listen: "0.0.0.0:8080".into(),
            auth_token: String::new(),
            data_dir: PathBuf::from("./data"),
            yt_dlp_path: "yt-dlp".into(),
            max_ytdlp_procs: 3,
            force_ipv4: true,
            medium_quality: true,
            hls_resolution: 720,
            home_feed: HomeFeed::Popular,
            log_queries: false,
            region: "VN".into(),
            language: "vi".into(),
        }
    }
}

impl Config {
    /// Parses a TOML string.
    pub fn from_toml(text: &str) -> Result<Self> {
        let mut cfg: Config = toml::from_str(text)?;
        if cfg.max_ytdlp_procs == 0 {
            cfg.max_ytdlp_procs = 1;
        }
        Ok(cfg)
    }

    /// Loads `path`. Returns defaults (and `false`) when the file does not exist.
    pub fn load(path: &Path) -> Result<(Self, bool)> {
        if !path.exists() {
            return Ok((Self::default(), false));
        }
        let text = std::fs::read_to_string(path)
            .with_context(|| format!("cannot read {}", path.display()))?;
        let mut cfg =
            Self::from_toml(&text).with_context(|| format!("invalid config {}", path.display()))?;
        if cfg.data_dir.is_relative() {
            let base = path.parent().unwrap_or_else(|| Path::new("."));
            cfg.data_dir = base.join(&cfg.data_dir);
        }
        Ok((cfg, true))
    }
}

/// Default config location: `config.toml` beside the executable.
pub fn default_path() -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join("config.toml")))
        .unwrap_or_else(|| PathBuf::from("config.toml"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn example_config_matches_defaults() {
        let example = include_str!("../config.example.toml");
        let cfg = Config::from_toml(example).expect("example config must parse");
        let def = Config::default();
        assert_eq!(cfg.listen, def.listen);
        assert_eq!(cfg.max_ytdlp_procs, def.max_ytdlp_procs);
        assert_eq!(cfg.home_feed, HomeFeed::Popular);
        assert!(cfg.force_ipv4);
    }

    #[test]
    fn empty_config_uses_defaults() {
        let cfg = Config::from_toml("").unwrap();
        assert_eq!(cfg.hls_resolution, 720);
        assert!(cfg.auth_token.is_empty());
    }

    #[test]
    fn unknown_key_is_rejected() {
        assert!(Config::from_toml("listne = \"x\"").is_err());
    }

    #[test]
    fn zero_procs_is_clamped() {
        let cfg = Config::from_toml("max_ytdlp_procs = 0").unwrap();
        assert_eq!(cfg.max_ytdlp_procs, 1);
    }
}
