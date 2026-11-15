//! User data in SQLite (`<data_dir>/tubemini.db`): subscribed channels and watch history.
//!
//! rusqlite is synchronous, so every call runs on the blocking thread pool behind one mutex. A home
//! server has one or two users; a single connection is plenty.

use std::path::Path;
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
use rusqlite::{Connection, OptionalExtension, Row, params};

/// Videos kept in the history; older ones are dropped.
pub const HISTORY_LIMIT: usize = 500;

#[derive(Debug, Clone, PartialEq)]
pub struct Subscription {
    pub channel_id: String,
    pub name: String,
    pub avatar: String,
    pub subscribers: u64,
    /// Unix seconds.
    pub added_at: i64,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct HistoryEntry {
    pub video_id: String,
    pub title: String,
    pub author: String,
    pub author_id: String,
    /// Seconds; 0 = unknown.
    pub duration: u32,
    /// Seconds into the video.
    pub position: u32,
    /// Unix seconds of the last save.
    pub watched_at: i64,
}

#[derive(Clone)]
pub struct Store(Arc<Mutex<Connection>>);

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS subscriptions (
    channel_id  TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    avatar      TEXT NOT NULL DEFAULT '',
    subscribers INTEGER NOT NULL DEFAULT 0,
    added_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS history (
    video_id   TEXT PRIMARY KEY,
    title      TEXT NOT NULL DEFAULT '',
    author     TEXT NOT NULL DEFAULT '',
    author_id  TEXT NOT NULL DEFAULT '',
    duration   INTEGER NOT NULL DEFAULT 0,
    position   INTEGER NOT NULL DEFAULT 0,
    watched_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS history_watched ON history (watched_at DESC);
";

const HISTORY_COLUMNS: &str = "video_id, title, author, author_id, duration, position, watched_at";

fn history_row(r: &Row<'_>) -> rusqlite::Result<HistoryEntry> {
    Ok(HistoryEntry {
        video_id: r.get(0)?,
        title: r.get(1)?,
        author: r.get(2)?,
        author_id: r.get(3)?,
        duration: r.get(4)?,
        position: r.get(5)?,
        watched_at: r.get(6)?,
    })
}

/// Sort key for names: lowercase with Vietnamese letters folded to plain Latin, so "Âm nhạc" sorts
/// next to "an" instead of after "z".
fn sort_key(name: &str) -> String {
    const GROUPS: [(char, &str); 7] = [
        ('a', "àáảãạăằắẳẵặâầấẩẫậ"),
        ('e', "èéẻẽẹêềếểễệ"),
        ('i', "ìíỉĩị"),
        ('o', "òóỏõọôồốổỗộơờớởỡợ"),
        ('u', "ùúủũụưừứửữự"),
        ('y', "ỳýỷỹỵ"),
        ('d', "đ"),
    ];
    name.to_lowercase()
        .chars()
        .map(|c| {
            GROUPS
                .iter()
                .find(|(_, set)| set.contains(c))
                .map_or(c, |&(base, _)| base)
        })
        .collect()
}

impl Store {
    /// Opens (or creates) `<dir>/tubemini.db`.
    pub fn open(dir: &Path) -> Result<Self> {
        std::fs::create_dir_all(dir).with_context(|| format!("cannot create {}", dir.display()))?;
        let path = dir.join("tubemini.db");
        let conn =
            Connection::open(&path).with_context(|| format!("cannot open {}", path.display()))?;
        Self::init(conn)
    }

    /// Throwaway database for tests.
    #[cfg(test)]
    pub fn memory() -> Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> Result<Self> {
        conn.busy_timeout(std::time::Duration::from_secs(5))?;
        conn.execute_batch(SCHEMA).context("creating tables")?;
        Ok(Self(Arc::new(Mutex::new(conn))))
    }

    /// Runs `f` with the connection on the blocking pool.
    async fn with<T, F>(&self, f: F) -> Result<T>
    where
        T: Send + 'static,
        F: FnOnce(&mut Connection) -> rusqlite::Result<T> + Send + 'static,
    {
        let conn = self.0.clone();
        tokio::task::spawn_blocking(move || {
            // A panic while holding the lock leaves the connection itself intact
            let mut guard = conn.lock().unwrap_or_else(|e| e.into_inner());
            f(&mut guard)
        })
        .await
        .context("store task")?
        .context("sqlite")
    }

    /// Every subscription, sorted by channel name.
    pub async fn subscriptions(&self) -> Result<Vec<Subscription>> {
        let mut subs = self
            .with(|c| {
                let mut stmt = c.prepare(
                    "SELECT channel_id, name, avatar, subscribers, added_at FROM subscriptions",
                )?;
                let rows = stmt.query_map([], |r| {
                    Ok(Subscription {
                        channel_id: r.get(0)?,
                        name: r.get(1)?,
                        avatar: r.get(2)?,
                        subscribers: u64::try_from(r.get::<_, i64>(3)?).unwrap_or(0),
                        added_at: r.get(4)?,
                    })
                })?;
                rows.collect::<rusqlite::Result<Vec<_>>>()
            })
            .await?;
        subs.sort_by_cached_key(|s| sort_key(&s.name));
        Ok(subs)
    }

    /// Adds a channel, or refreshes its name / avatar / subscriber count.
    pub async fn subscribe(&self, s: Subscription) -> Result<()> {
        self.with(move |c| {
            c.execute(
                "INSERT INTO subscriptions (channel_id, name, avatar, subscribers, added_at)
                 VALUES (?1, ?2, ?3, ?4, ?5)
                 ON CONFLICT(channel_id) DO UPDATE SET
                     name = excluded.name, avatar = excluded.avatar, subscribers = excluded.subscribers",
                params![
                    s.channel_id,
                    s.name,
                    s.avatar,
                    i64::try_from(s.subscribers).unwrap_or(i64::MAX),
                    s.added_at
                ],
            )
            .map(drop)
        })
        .await
    }

    /// Removes a channel. `false` when it was not subscribed.
    pub async fn unsubscribe(&self, channel_id: &str) -> Result<bool> {
        let id = channel_id.to_owned();
        self.with(move |c| {
            c.execute("DELETE FROM subscriptions WHERE channel_id = ?1", [id])
                .map(|n| n > 0)
        })
        .await
    }

    /// The whole history, most recently watched first.
    pub async fn history(&self) -> Result<Vec<HistoryEntry>> {
        self.with(|c| {
            let mut stmt = c.prepare(&format!(
                "SELECT {HISTORY_COLUMNS} FROM history ORDER BY watched_at DESC, video_id"
            ))?;
            let rows = stmt.query_map([], history_row)?;
            rows.collect()
        })
        .await
    }

    pub async fn history_entry(&self, video_id: &str) -> Result<Option<HistoryEntry>> {
        let id = video_id.to_owned();
        self.with(move |c| {
            c.query_row(
                &format!("SELECT {HISTORY_COLUMNS} FROM history WHERE video_id = ?1"),
                [id],
                history_row,
            )
            .optional()
        })
        .await
    }

    /// Saves the position of `e.video_id`. Empty text fields and a zero duration keep what is
    /// already stored. Returns the stored row. Drops the oldest rows beyond [`HISTORY_LIMIT`].
    pub async fn save_position(&self, e: HistoryEntry) -> Result<HistoryEntry> {
        self.with(move |c| {
            let tx = c.transaction()?;
            tx.execute(
                "INSERT INTO history (video_id, title, author, author_id, duration, position, watched_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                 ON CONFLICT(video_id) DO UPDATE SET
                     title = CASE WHEN excluded.title <> '' THEN excluded.title ELSE history.title END,
                     author = CASE WHEN excluded.author <> '' THEN excluded.author ELSE history.author END,
                     author_id = CASE WHEN excluded.author_id <> '' THEN excluded.author_id ELSE history.author_id END,
                     duration = CASE WHEN excluded.duration > 0 THEN excluded.duration ELSE history.duration END,
                     position = excluded.position,
                     watched_at = excluded.watched_at",
                params![
                    e.video_id,
                    e.title,
                    e.author,
                    e.author_id,
                    e.duration,
                    e.position,
                    e.watched_at
                ],
            )?;
            tx.execute(
                "DELETE FROM history WHERE video_id NOT IN
                     (SELECT video_id FROM history ORDER BY watched_at DESC, video_id LIMIT ?1)",
                [HISTORY_LIMIT as i64],
            )?;
            let stored = tx.query_row(
                &format!("SELECT {HISTORY_COLUMNS} FROM history WHERE video_id = ?1"),
                [&e.video_id],
                history_row,
            )?;
            tx.commit()?;
            Ok(stored)
        })
        .await
    }

    /// Removes one video from the history, or everything when `video_id` is `None`.
    pub async fn forget(&self, video_id: Option<&str>) -> Result<()> {
        let id = video_id.map(str::to_owned);
        self.with(move |c| {
            match id {
                Some(id) => c.execute("DELETE FROM history WHERE video_id = ?1", [id]),
                None => c.execute("DELETE FROM history", []),
            }
            .map(drop)
        })
        .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sub(id: &str, name: &str) -> Subscription {
        Subscription {
            channel_id: id.into(),
            name: name.into(),
            avatar: format!("https://yt3.ggpht.com/{id}=s88"),
            subscribers: 1_000,
            added_at: 1,
        }
    }

    #[tokio::test]
    async fn subscriptions_roundtrip() {
        let s = Store::memory().unwrap();
        assert!(s.subscriptions().await.unwrap().is_empty());
        s.subscribe(sub("UCb", "bếp nhà")).await.unwrap();
        s.subscribe(sub("UCa", "Âm nhạc")).await.unwrap();
        s.subscribe(sub("UCc", "Café")).await.unwrap();
        // Subscribing again updates instead of duplicating
        s.subscribe(sub("UCc", "Cà phê")).await.unwrap();
        let names: Vec<_> = s
            .subscriptions()
            .await
            .unwrap()
            .into_iter()
            .map(|s| s.name)
            .collect();
        assert_eq!(names, ["Âm nhạc", "bếp nhà", "Cà phê"]);
        assert!(s.unsubscribe("UCa").await.unwrap());
        assert!(!s.unsubscribe("UCa").await.unwrap());
        assert_eq!(s.subscriptions().await.unwrap().len(), 2);
    }

    fn watch(id: &str, position: u32, at: i64) -> HistoryEntry {
        HistoryEntry {
            video_id: id.into(),
            position,
            watched_at: at,
            ..Default::default()
        }
    }

    #[tokio::test]
    async fn history_keeps_known_fields_and_orders_by_time() {
        let s = Store::memory().unwrap();
        let first = HistoryEntry {
            title: "Bản tin 60 giây".into(),
            author: "HTV".into(),
            author_id: "UCh".into(),
            duration: 1347,
            ..watch("aaaaaaaaaaa", 10, 100)
        };
        assert_eq!(s.save_position(first.clone()).await.unwrap(), first);
        // A later save with only the position keeps title / author / duration
        let saved = s
            .save_position(watch("aaaaaaaaaaa", 754, 300))
            .await
            .unwrap();
        assert_eq!(saved.title, "Bản tin 60 giây");
        assert_eq!(
            (saved.position, saved.duration, saved.watched_at),
            (754, 1347, 300)
        );
        s.save_position(watch("bbbbbbbbbbb", 5, 200)).await.unwrap();

        let ids: Vec<_> = s
            .history()
            .await
            .unwrap()
            .into_iter()
            .map(|h| h.video_id)
            .collect();
        assert_eq!(ids, ["aaaaaaaaaaa", "bbbbbbbbbbb"]);
        assert_eq!(
            s.history_entry("bbbbbbbbbbb")
                .await
                .unwrap()
                .map(|h| h.position),
            Some(5)
        );
        assert!(s.history_entry("ccccccccccc").await.unwrap().is_none());

        s.forget(Some("aaaaaaaaaaa")).await.unwrap();
        assert_eq!(s.history().await.unwrap().len(), 1);
        s.forget(None).await.unwrap();
        assert!(s.history().await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn history_is_capped() {
        let s = Store::memory().unwrap();
        for i in 0..HISTORY_LIMIT as i64 + 3 {
            s.save_position(watch(&format!("v{i:010}"), 1, i))
                .await
                .unwrap();
        }
        let all = s.history().await.unwrap();
        assert_eq!(all.len(), HISTORY_LIMIT);
        // The three oldest are gone
        assert!(all.iter().all(|h| h.watched_at >= 3));
    }

    #[tokio::test]
    async fn opens_a_file_in_the_data_dir() {
        let dir = std::env::temp_dir().join(format!("tubemini-store-{}", std::process::id()));
        let s = Store::open(&dir).unwrap();
        s.subscribe(sub("UCx", "X")).await.unwrap();
        drop(s);
        let again = Store::open(&dir).unwrap();
        assert_eq!(again.subscriptions().await.unwrap().len(), 1);
        drop(again);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
