//! The subscription feed: newest videos of every subscribed channel, merged newest first
//! (`/tm/v1/feed`, and the old app's home with `home_feed = "subscriptions"`; docs/API.md, D26).
//!
//! YouTube's channel RSS no longer works, so each channel's Videos tab (first page, about 30
//! videos) is fetched instead. Its dates are relative ("3 hours ago"), so the order across
//! channels is approximate; within a channel it is YouTube's own order.

use std::collections::HashSet;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use tokio::sync::Semaphore;
use tokio::task::JoinSet;

use crate::state::AppState;
use crate::youtube::Video;

/// Videos kept in the merged feed.
pub const FEED_MAX: usize = 300;
/// How long a merged feed is reused (each channel page is cached 30 minutes by the provider).
pub const FEED_TTL: Duration = Duration::from_secs(10 * 60);
/// Channels fetched at the same time.
const PARALLEL: usize = 4;

/// The merged feed (cached). `fresh` refetches every channel. No subscriptions = empty feed.
pub async fn subscription_feed(st: &AppState, fresh: bool) -> Result<Arc<Vec<Video>>> {
    if fresh {
        st.feed.invalidate_all();
    }
    st.feed
        .try_get_with((), build(st, fresh))
        .await
        .map_err(|e| anyhow!("{e:#}"))
}

/// Call after the subscriptions changed.
pub fn invalidate(st: &AppState) {
    st.feed.invalidate_all();
}

async fn build(st: &AppState, fresh: bool) -> Result<Arc<Vec<Video>>> {
    let subs = st.store.subscriptions().await?;
    if subs.is_empty() {
        return Ok(Arc::new(Vec::new()));
    }
    let total = subs.len();
    let gate = Arc::new(Semaphore::new(PARALLEL));
    let mut tasks = JoinSet::new();
    for (index, sub) in subs.into_iter().enumerate() {
        let st = st.clone();
        let gate = gate.clone();
        tasks.spawn(async move {
            let _permit = gate.acquire_owned().await;
            if fresh {
                let _ = st.meta.forget_uploads(&sub.channel_id).await;
            }
            let page = st.meta.channel_uploads(&sub.channel_id, None).await;
            (index, sub.channel_id, page)
        });
    }
    let mut lists = Vec::with_capacity(total);
    while let Some(done) = tasks.join_next().await {
        match done {
            Ok((index, _, Ok(page))) => lists.push((index, page.videos)),
            Ok((_, id, Err(e))) => tracing::warn!("feed: channel {id}: {e:#}"),
            Err(e) => tracing::warn!("feed: task: {e}"),
        }
    }
    if lists.is_empty() {
        bail!("no channel of the {total} subscriptions answered");
    }
    // Same input order every time (subscription order), whatever order the fetches finished in
    lists.sort_by_key(|(index, _)| *index);
    Ok(Arc::new(merge(
        lists.into_iter().map(|(_, videos)| videos),
        FEED_MAX,
    )))
}

/// Newest first by `published` (stable, so ties keep each channel's own order); videos without a
/// date go last; a video listed twice is kept once; at most `max`.
pub fn merge(lists: impl IntoIterator<Item = Vec<Video>>, max: usize) -> Vec<Video> {
    let mut all: Vec<Video> = lists.into_iter().flatten().collect();
    all.sort_by_key(|v| std::cmp::Reverse(v.published));
    let mut seen = HashSet::new();
    all.retain(|v| seen.insert(v.id.clone()));
    all.truncate(max);
    all
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(id: &str, published: i64) -> Video {
        Video {
            id: id.into(),
            published,
            ..Default::default()
        }
    }

    fn ids(videos: &[Video]) -> Vec<&str> {
        videos.iter().map(|v| v.id.as_str()).collect()
    }

    #[test]
    fn merges_newest_first() {
        let a = vec![v("a1", 500), v("a2", 300), v("a3", 100)];
        let b = vec![v("b1", 400), v("b2", 300), v("b3", 0)];
        let merged = merge([a, b], 10);
        // a2 and b2 tie: channel order decides; unknown date (0) last
        assert_eq!(ids(&merged), ["a1", "b1", "a2", "b2", "a3", "b3"]);
    }

    #[test]
    fn same_relative_date_keeps_channel_order() {
        // "1 day ago" twice in one channel: YouTube's order (newest first) must survive
        let a = vec![v("new", 1000), v("old", 1000)];
        assert_eq!(ids(&merge([a], 10)), ["new", "old"]);
    }

    #[test]
    fn drops_duplicates_and_caps() {
        let a = vec![v("x", 3), v("y", 2)];
        let b = vec![v("x", 3), v("z", 1)];
        assert_eq!(ids(&merge([a.clone(), b], 10)), ["x", "y", "z"]);
        assert_eq!(ids(&merge([a], 1)), ["x"]);
    }
}
