//! Runs yt-dlp (and probes deno) as external processes.

use std::process::Stdio;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use tokio::process::Command;
use tokio::sync::Semaphore;

use super::VideoId;
use crate::config::Config;

const RUN_TIMEOUT: Duration = Duration::from_secs(30);
const PROBE_TIMEOUT: Duration = Duration::from_secs(15);

/// Builds a command that never opens a console window on Windows and dies with its handle.
fn command(program: &str) -> Command {
    let mut cmd = Command::new(program);
    cmd.stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    #[cfg(windows)]
    {
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    cmd
}

/// Returns the first line of `<program> --version`, or a human-readable error.
pub async fn probe_version(program: &str) -> Result<String, String> {
    let mut cmd = command(program);
    cmd.arg("--version");
    let out = match tokio::time::timeout(PROBE_TIMEOUT, cmd.output()).await {
        Err(_) => return Err(format!("`{program} --version` timed out")),
        Ok(Err(e)) => return Err(format!("cannot run `{program}`: {e}")),
        Ok(Ok(out)) => out,
    };
    if !out.status.success() {
        return Err(format!("`{program} --version` exited with {}", out.status));
    }
    let text = String::from_utf8_lossy(&out.stdout);
    Ok(text.lines().next().unwrap_or_default().trim().to_owned())
}

/// Versions of the external tools, checked once at startup.
#[derive(Debug, Clone)]
pub struct ToolStatus {
    pub yt_dlp: Result<String, String>,
    pub deno: Result<String, String>,
}

impl ToolStatus {
    pub async fn check(yt_dlp_path: &str) -> Self {
        let (yt_dlp, deno) = tokio::join!(probe_version(yt_dlp_path), probe_version("deno"));
        Self { yt_dlp, deno }
    }

    /// Logs one line per tool; missing tools are errors with an install hint.
    pub fn log(&self) {
        match &self.yt_dlp {
            Ok(v) => tracing::info!("yt-dlp {v}"),
            Err(e) => tracing::error!(
                "yt-dlp NOT available ({e}). Install yt-dlp.exe from https://github.com/yt-dlp/yt-dlp/releases \
                 and set yt_dlp_path in config.toml. Video links will not work."
            ),
        }
        match &self.deno {
            Ok(v) => tracing::info!("{v}"),
            Err(e) => tracing::error!(
                "deno NOT available ({e}). yt-dlp needs Deno for YouTube: `winget install DenoLand.Deno`, \
                 then restart the server from a new terminal so PATH is refreshed."
            ),
        }
    }
}

/// Runs yt-dlp with a concurrency limit and a timeout.
#[derive(Clone)]
pub struct YtDlp {
    path: String,
    force_ipv4: bool,
    permits: Arc<Semaphore>,
}

impl YtDlp {
    pub fn new(cfg: &Config) -> Self {
        Self {
            path: cfg.yt_dlp_path.clone(),
            force_ipv4: cfg.force_ipv4,
            permits: Arc::new(Semaphore::new(cfg.max_ytdlp_procs)),
        }
    }

    /// Runs yt-dlp with `args` (plus `--force-ipv4` when configured) and returns stdout.
    pub async fn run(&self, args: &[&str]) -> Result<String> {
        let _permit = self
            .permits
            .acquire()
            .await
            .context("yt-dlp semaphore closed")?;
        let mut cmd = command(&self.path);
        if self.force_ipv4 {
            cmd.arg("--force-ipv4");
        }
        cmd.args(["--no-warnings", "--no-playlist"]).args(args);
        let out = tokio::time::timeout(RUN_TIMEOUT, cmd.output())
            .await
            .context("yt-dlp timed out after 30 s")?
            .with_context(|| format!("cannot run {}", self.path))?;
        if !out.status.success() {
            let err = String::from_utf8_lossy(&out.stderr);
            let last = err
                .lines()
                .rev()
                .find(|l| !l.trim().is_empty())
                .unwrap_or("");
            bail!("yt-dlp failed ({}): {last}", out.status);
        }
        Ok(String::from_utf8_lossy(&out.stdout).into_owned())
    }

    /// Direct media URL(s) for `format` (e.g. `18`) via `yt-dlp -g`.
    pub async fn media_urls(&self, id: &VideoId, format: &str) -> Result<Vec<String>> {
        let out = self.run(&["-g", "-f", format, &id.watch_url()]).await?;
        let urls: Vec<String> = out
            .lines()
            .map(str::trim)
            .filter(|l| l.starts_with("https://"))
            .map(str::to_owned)
            .collect();
        if urls.is_empty() {
            bail!("yt-dlp returned no URL");
        }
        Ok(urls)
    }
}

/// Reads one query parameter from a googlevideo URL (for display/diagnostics).
pub fn url_param<'a>(url: &'a str, name: &str) -> Option<&'a str> {
    let query = url.split_once('?')?.1;
    query
        .split('&')
        .filter_map(|kv| kv.split_once('='))
        .find(|(k, _)| *k == name)
        .map(|(_, v)| v)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_url_params() {
        let u =
            "https://rr2---sn-x.googlevideo.com/videoplayback?expire=1794725568&ip=1.2.3.4&itag=18";
        assert_eq!(url_param(u, "ip"), Some("1.2.3.4"));
        assert_eq!(url_param(u, "expire"), Some("1794725568"));
        assert_eq!(url_param(u, "nope"), None);
        assert_eq!(url_param("no-query", "ip"), None);
    }

    #[tokio::test]
    async fn probe_reports_missing_program() {
        let r = probe_version("definitely-not-a-real-program-tm").await;
        assert!(r.is_err());
    }
}
