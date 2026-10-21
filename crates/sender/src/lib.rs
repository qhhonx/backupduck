//! Persistent sender decisions shared by Rust and native background executors.
//! References are opaque to this crate; hosts resolve them to exported resources.
use backupduck_core::*;
use fs2::FileExt;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, File, OpenOptions},
    path::Path,
};

mod library;
mod sorting;
mod task_feed;
pub use library::{LibrarySourceState, LibraryTileState};
pub use sorting::JobQuery;

/// Shared supported concurrency range, independent of the native executor.
pub const MAX_CONCURRENT_UPLOADS: u32 = 4;

fn db(e: rusqlite::Error) -> Error {
    Error::Storage(e.to_string())
}
fn processing_name(state: &ProcessingState) -> &'static str {
    match state {
        ProcessingState::NotRequested => "not_requested",
        ProcessingState::Pending => "pending",
        ProcessingState::Complete => "complete",
        ProcessingState::Failed => "failed",
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum JobState {
    Queued,
    Running,
    Waiting,
    Paused,
    Failed,
    Received,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Job {
    pub id: i64,
    pub receiver_id: String,
    pub asset: Asset,
    pub sources: BTreeMap<String, String>,
    pub state: JobState,
    pub generation: i64,
    pub attempts: u32,
    pub next_attempt_at: i64,
    pub confirmed_bytes: u64,
    pub error_code: Option<String>,
    pub native_task_id: Option<String>,
    /// Receiver gallery publication, independent of the verified transfer receipt.
    #[serde(default)]
    pub processing: Option<ProcessingState>,
    #[serde(default)]
    pub processing_error: Option<String>,
    #[serde(default)]
    pub state_changed_at_ms: Option<i64>,
    #[serde(default)]
    pub sort_value: Option<i64>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Attempt {
    pub job_id: i64,
    pub generation: i64,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Failure {
    Network,
    Capacity,
    LowSpace,
    Busy,
    Authentication,
    Integrity,
    SourceUnavailable,
    Unsupported,
}
impl Failure {
    pub fn from_error(error: &Error) -> Self {
        match error {
            Error::Capacity => Self::Capacity,
            Error::LowSpace => Self::LowSpace,
            Error::Integrity => Self::Integrity,
            Error::Unsupported(_) | Error::Invalid(_) => Self::Unsupported,
            Error::Storage(_) | Error::NotFound => Self::SourceUnavailable,
            Error::Conflict(_) => Self::Busy,
            Error::Unauthorized => Self::Authentication,
            _ => Self::Network,
        }
    }
    fn automatic(&self) -> bool {
        matches!(
            self,
            Self::Network | Self::Capacity | Self::LowSpace | Self::Busy
        )
    }
}
impl Job {
    pub fn attempt(&self) -> Attempt {
        Attempt {
            job_id: self.id,
            generation: self.generation,
        }
    }
}

pub struct Sender {
    conn: Connection,
    _lock: File,
}
impl Sender {
    pub fn open(root: impl AsRef<Path>) -> Result<Self> {
        fs::create_dir_all(root.as_ref())?;
        let lock = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(root.as_ref().join("sender.lock"))?;
        lock.try_lock_exclusive()
            .map_err(|_| Error::Conflict("sender already open".into()))?;
        let conn = Connection::open(root.as_ref().join("sender.sqlite3")).map_err(db)?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;
            CREATE TABLE IF NOT EXISTS jobs (
                id INTEGER PRIMARY KEY, receiver_id TEXT NOT NULL, asset_id TEXT NOT NULL,
                manifest TEXT NOT NULL, sources TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'queued',
                generation INTEGER NOT NULL DEFAULT 0, attempts INTEGER NOT NULL DEFAULT 0,
                next_attempt_at INTEGER NOT NULL DEFAULT 0, confirmed_bytes INTEGER NOT NULL DEFAULT 0,
                error_code TEXT, native_task_id TEXT,
                UNIQUE(receiver_id,asset_id));
            CREATE INDEX IF NOT EXISTS jobs_due ON jobs(receiver_id,state,next_attempt_at,id);
            CREATE TABLE IF NOT EXISTS native_checkpoints(job_id INTEGER PRIMARY KEY,status TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS processing_observations(job_id INTEGER PRIMARY KEY,state TEXT,error TEXT,checked_at INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS receiver_features(receiver_id TEXT PRIMARY KEY,bundle_upload INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value INTEGER NOT NULL);
            INSERT OR IGNORE INTO settings VALUES('paused',0);
            INSERT OR IGNORE INTO settings VALUES('concurrent_uploads',4);
            INSERT OR IGNORE INTO settings VALUES('revision',0);
            CREATE TRIGGER IF NOT EXISTS jobs_insert_revision AFTER INSERT ON jobs BEGIN UPDATE settings SET value=value+1 WHERE key='revision'; END;
            CREATE TRIGGER IF NOT EXISTS jobs_update_revision AFTER UPDATE ON jobs BEGIN UPDATE settings SET value=value+1 WHERE key='revision'; END;
            CREATE INDEX IF NOT EXISTS jobs_source_revision ON jobs(receiver_id,json_extract(manifest,'$.source_id'),json_extract(manifest,'$.revision'));").map_err(db)?;
        // Guard before insertion: a writer's outer conflict policy can override
        // a trigger's OR IGNORE and replace the first observed publication time.
        conn.execute_batch("CREATE TABLE IF NOT EXISTS publication_times(job_id INTEGER PRIMARY KEY,observed_ms INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS publication_legacy(job_id INTEGER PRIMARY KEY);
            INSERT OR IGNORE INTO publication_legacy SELECT job_id FROM processing_observations WHERE state='complete' AND job_id NOT IN (SELECT job_id FROM publication_times);
            DROP TRIGGER IF EXISTS publication_insert;
            DROP TRIGGER IF EXISTS publication_update;
            CREATE TRIGGER IF NOT EXISTS publication_insert_once AFTER INSERT ON processing_observations WHEN NEW.state='complete' AND NOT EXISTS(SELECT 1 FROM publication_legacy WHERE job_id=NEW.job_id) AND NOT EXISTS(SELECT 1 FROM publication_times WHERE job_id=NEW.job_id) BEGIN INSERT INTO publication_times VALUES(NEW.job_id,CAST(unixepoch('subsec')*1000 AS INTEGER)); END;
            CREATE TRIGGER IF NOT EXISTS publication_update_once AFTER UPDATE ON processing_observations WHEN NEW.state='complete' AND NOT EXISTS(SELECT 1 FROM publication_legacy WHERE job_id=NEW.job_id) AND NOT EXISTS(SELECT 1 FROM publication_times WHERE job_id=NEW.job_id) BEGIN INSERT INTO publication_times VALUES(NEW.job_id,CAST(unixepoch('subsec')*1000 AS INTEGER)); END;").map_err(db)?;
        sorting::migrate(&conn)?;
        // Rust foreground tasks cannot survive a process exit. OS tasks can and must
        // be reconciled explicitly after the native scheduler has enumerated them.
        conn.execute("UPDATE jobs SET state='queued', generation=generation+1 WHERE state='running' AND native_task_id IS NULL", []).map_err(db)?;
        conn.execute("DELETE FROM native_checkpoints WHERE job_id IN (SELECT id FROM jobs WHERE state!='running' AND state!='queued')", []).map_err(db)?;
        Ok(Self { conn, _lock: lock })
    }
    pub fn enqueue(
        &mut self,
        receiver: &str,
        asset: Asset,
        sources: BTreeMap<String, String>,
    ) -> Result<Job> {
        self.enqueue_prepared(receiver, asset, sources, None)
    }
    /// Presentation identity is stored outside the signed asset manifest: adding
    /// preparation membership must never change the protocol asset hash.
    pub fn enqueue_prepared(
        &mut self,
        receiver: &str,
        asset: Asset,
        sources: BTreeMap<String, String>,
        preparation: Option<&(String, i64, Option<i64>)>,
    ) -> Result<Job> {
        let tx = self.conn.unchecked_transaction().map_err(db)?;
        let job = self.enqueue_job(receiver, asset, sources)?;
        if let Some((request, cursor, added)) = preparation {
            tx.execute("INSERT INTO job_preparations(receiver,request,job_id,cursor,added_at_ms) VALUES(?1,?2,?3,?4,?5) ON CONFLICT(receiver,request) DO NOTHING",params![receiver,request,job.id,cursor,added]).map_err(db)?;
        }
        tx.commit().map_err(db)?;
        Ok(job)
    }
    fn enqueue_job(
        &self,
        receiver: &str,
        asset: Asset,
        sources: BTreeMap<String, String>,
    ) -> Result<Job> {
        let id = asset.id()?;
        if receiver.is_empty()
            || receiver.len() > 256
            || receiver.chars().any(char::is_control)
            || sources.len() != asset.resources.len()
            || asset.resources.iter().any(|r| {
                sources
                    .get(&r.sha256)
                    .is_none_or(|s| s.is_empty() || s.len() > 8192)
            })
        {
            return Err(Error::Invalid("sender input".into()));
        }
        self.conn
            .execute(
                "INSERT INTO jobs(receiver_id,asset_id,manifest,sources) VALUES(?1,?2,?3,?4)
                ON CONFLICT(receiver_id,asset_id) DO UPDATE SET sources=excluded.sources,
                state='queued',error_code=NULL,next_attempt_at=0,generation=jobs.generation+1
                WHERE jobs.state='failed' AND jobs.error_code='source_unavailable' ",
                params![
                    receiver,
                    id,
                    serde_json::to_string(&asset)?,
                    serde_json::to_string(&sources)?
                ],
            )
            .map_err(db)?;
        let job_id = self
            .conn
            .query_row(
                "SELECT id FROM jobs WHERE receiver_id=?1 AND asset_id=?2",
                params![receiver, id],
                |r| r.get(0),
            )
            .map_err(db)?;
        self.job(job_id)
    }
    pub fn source_job_id(
        &self,
        receiver: &str,
        source: &str,
        revision: &str,
    ) -> Result<Option<i64>> {
        self.conn.query_row("SELECT id FROM jobs WHERE receiver_id=?1 AND json_extract(manifest,'$.source_id')=?2 AND json_extract(manifest,'$.revision')=?3 ORDER BY id DESC LIMIT 1",params![receiver,source,revision],|r|r.get(0)).optional().map_err(db)
    }
    pub fn job(&self, id: i64) -> Result<Job> {
        let row = self.conn.query_row("SELECT j.receiver_id,j.manifest,j.sources,j.state,j.generation,j.attempts,j.next_attempt_at,j.confirmed_bytes,j.error_code,j.native_task_id,j.state_changed_at_ms,p.state,p.error FROM jobs j LEFT JOIN processing_observations p ON p.job_id=j.id WHERE j.id=?1", [id], |r| Ok((r.get::<_,String>(0)?,r.get::<_,String>(1)?,r.get::<_,String>(2)?,r.get::<_,String>(3)?,r.get::<_,i64>(4)?,r.get::<_,u32>(5)?,r.get::<_,i64>(6)?,r.get::<_,i64>(7)?,r.get::<_,Option<String>>(8)?,r.get::<_,Option<String>>(9)?,r.get::<_,Option<i64>>(10)?,r.get::<_,Option<String>>(11)?,r.get::<_,Option<String>>(12)?))).optional().map_err(db)?.ok_or(Error::NotFound)?;
        Ok(Job {
            id,
            receiver_id: row.0,
            asset: serde_json::from_str(&row.1)?,
            sources: serde_json::from_str(&row.2)?,
            state: serde_json::from_value(serde_json::Value::String(row.3))?,
            generation: row.4,
            attempts: row.5,
            next_attempt_at: row.6,
            confirmed_bytes: row.7 as u64,
            error_code: row.8,
            native_task_id: row.9,
            processing: row
                .11
                .map(|s| serde_json::from_value(serde_json::Value::String(s)))
                .transpose()?,
            processing_error: row.12,
            state_changed_at_ms: row.10,
            sort_value: None,
        })
    }
    /// Bounded keyset pagination; never materialize the entire library for a UI poll.
    pub fn list(&self, after: i64, limit: u32) -> Result<Vec<Job>> {
        self.list_filtered(after, limit, None, None)
    }
    pub fn list_filtered(
        &self,
        after: i64,
        limit: u32,
        receiver: Option<&str>,
        state: Option<&str>,
    ) -> Result<Vec<Job>> {
        self.list_filtered_ordered(after, limit, receiver, state, false)
    }
    /// Order the complete filtered result before keyset pagination.
    pub fn list_filtered_ordered(
        &self,
        after: i64,
        limit: u32,
        receiver: Option<&str>,
        state: Option<&str>,
        descending: bool,
    ) -> Result<Vec<Job>> {
        let sql = if descending {
            "SELECT id FROM jobs WHERE (?1=0 OR id<?1) AND (?3 IS NULL OR receiver_id=?3) AND (?4 IS NULL OR state=?4) ORDER BY id DESC LIMIT ?2"
        } else {
            "SELECT id FROM jobs WHERE id>?1 AND (?3 IS NULL OR receiver_id=?3) AND (?4 IS NULL OR state=?4) ORDER BY id ASC LIMIT ?2"
        };
        let mut s = self.conn.prepare(sql).map_err(db)?;
        let ids = s
            .query_map(params![after, limit.clamp(1, 500), receiver, state], |r| {
                r.get::<_, i64>(0)
            })
            .map_err(db)?
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(db)?;
        ids.into_iter().map(|id| self.job(id)).collect()
    }
    /// Explicit maintenance only: preserve obsolete jobs and their delivery proof
    /// before removing them from the runnable queue. Never invent an old receipt.
    pub fn archive_delivered_duplicates(
        &mut self,
        previous: &str,
        current: &str,
    ) -> Result<Vec<Job>> {
        if previous.is_empty() || current.is_empty() || previous == current {
            return Err(Error::Invalid("distinct receivers required".into()));
        }
        self.conn
            .execute_batch(
                "CREATE TABLE IF NOT EXISTS retired_cache_jobs(
            archive_id INTEGER PRIMARY KEY AUTOINCREMENT, job_id INTEGER NOT NULL, previous_receiver TEXT NOT NULL,
            current_receiver TEXT NOT NULL, job_json TEXT NOT NULL, proof_json TEXT NOT NULL);",
            )
            .map_err(db)?;
        let ids = self.conn.prepare("SELECT id FROM jobs WHERE receiver_id=?1 AND state IN ('queued','paused','failed','waiting') AND native_task_id IS NULL AND id NOT IN (SELECT job_id FROM native_checkpoints)").map_err(db)?
            .query_map([previous], |r| r.get::<_,i64>(0)).map_err(db)?
            .collect::<std::result::Result<Vec<_>,_>>().map_err(db)?;
        let mut pairs = Vec::new();
        for id in ids {
            let job = self.job(id)?;
            let candidates = self.conn.prepare("SELECT id FROM jobs WHERE receiver_id=?1 AND state='received' AND json_extract(manifest,'$.source_id')=?2 AND json_extract(manifest,'$.revision')=?3").map_err(db)?
                .query_map(params![current, job.asset.source_id, job.asset.revision], |r| r.get::<_,i64>(0)).map_err(db)?
                .collect::<std::result::Result<Vec<_>,_>>().map_err(db)?;
            for candidate in candidates {
                let proof = self.job(candidate)?;
                if job.asset.kind == proof.asset.kind
                    && job.asset.resources == proof.asset.resources
                {
                    pairs.push((job, proof));
                    break;
                }
            }
        }
        let tx = self.conn.transaction().map_err(db)?;
        for (job, proof) in &pairs {
            tx.execute(
                "INSERT INTO retired_cache_jobs(job_id,previous_receiver,current_receiver,job_json,proof_json) VALUES(?1,?2,?3,?4,?5)",
                params![
                    job.id,
                    previous,
                    current,
                    serde_json::to_string(job)?,
                    serde_json::to_string(proof)?
                ],
            )
            .map_err(db)?;
            tx.execute("DELETE FROM jobs WHERE id=?1", [job.id])
                .map_err(db)?;
        }
        if !pairs.is_empty() {
            tx.execute("UPDATE settings SET value=value+1 WHERE key='revision'", [])
                .map_err(db)?;
        }
        tx.commit().map_err(db)?;
        // Include previous successful archives so interrupted file cleanup can resume.
        let values = self.conn.prepare("SELECT job_json FROM retired_cache_jobs WHERE previous_receiver=?1 AND current_receiver=?2").map_err(db)?
            .query_map(params![previous,current], |r| r.get::<_,String>(0)).map_err(db)?
            .collect::<std::result::Result<Vec<_>,_>>().map_err(db)?;
        values
            .into_iter()
            .map(|v| Ok(serde_json::from_str(&v)?))
            .collect()
    }
    pub fn source_in_use(&self, path: &str) -> Result<bool> {
        self.conn.query_row("SELECT EXISTS(SELECT 1 FROM jobs,json_each(jobs.sources) WHERE jobs.state!='received' AND json_each.value=?1)", [path], |r|r.get(0)).map_err(db)
    }
    /// Update fully host-verified locations without changing asset identity or receipts.
    /// A repaired source failure becomes eligible again; explicit pauses survive.
    pub fn rebind_sources(&mut self, id: i64, sources: &BTreeMap<String, String>) -> Result<()> {
        let job = self.job(id)?;
        if !sources.keys().eq(job.sources.keys()) {
            return Err(Error::Invalid("source mapping".into()));
        }
        let transaction = self.conn.transaction().map_err(db)?;
        transaction
            .execute(
                "UPDATE jobs SET sources=?1 WHERE id=?2",
                params![serde_json::to_string(sources)?, id],
            )
            .map_err(db)?;
        transaction.execute("UPDATE jobs SET state='queued',next_attempt_at=0,error_code=NULL,generation=generation+1 WHERE id=?1 AND state='failed' AND error_code='source_unavailable'", [id]).map_err(db)?;
        transaction.commit().map_err(db)?;
        Ok(())
    }
    pub fn revision(&self) -> Result<i64> {
        self.conn
            .query_row("SELECT value FROM settings WHERE key='revision'", [], |r| {
                r.get(0)
            })
            .map_err(db)
    }
    /// Bounded lookup for the visible library window, using an expression index.
    pub fn source_states(
        &self,
        receiver: &str,
        sources: &[(String, String)],
    ) -> Result<BTreeMap<String, String>> {
        if sources.len() > 400 {
            return Err(Error::Invalid("source window".into()));
        }
        let mut stmt = self.conn.prepare("SELECT state FROM jobs WHERE receiver_id=?1 AND json_extract(manifest,'$.source_id')=?2 AND json_extract(manifest,'$.revision')=?3 ORDER BY id DESC LIMIT 1").map_err(db)?;
        let mut states = BTreeMap::new();
        for (id, revision) in sources {
            let value: Option<String> = stmt
                .query_row(params![receiver, id, revision], |r| r.get(0))
                .optional()
                .map_err(db)?;
            if let Some(value) = value {
                states.insert(id.clone(), value);
            }
        }
        Ok(states)
    }
    /// Every source this receiver has received, in any revision. The library's
    /// "Not backed up" view subtracts these from a whole library, which the
    /// bounded window lookup above cannot answer. Receipt only: it says nothing
    /// about the Pixel's Photos or cloud backup.
    pub fn received_sources(&self, receiver: &str) -> Result<Vec<String>> {
        let mut stmt = self
            .conn
            .prepare("SELECT DISTINCT json_extract(manifest,'$.source_id') FROM jobs WHERE receiver_id=?1 AND state='received'")
            .map_err(db)?;
        let rows = stmt
            .query_map(params![receiver], |r| r.get::<_, Option<String>>(0))
            .map_err(db)?;
        let mut sources = Vec::new();
        for row in rows {
            if let Some(source) = row.map_err(db)? {
                sources.push(source);
            }
        }
        Ok(sources)
    }
    /// The latest job for a source in any revision, so a photo's detail can say
    /// what happened to it. Receipt and Photos publication only; never cloud.
    pub fn latest_source_job(&self, receiver: &str, source: &str) -> Result<Option<Job>> {
        let id: Option<i64> = self
            .conn
            .query_row(
                "SELECT id FROM jobs WHERE receiver_id=?1 AND json_extract(manifest,'$.source_id')=?2 ORDER BY id DESC LIMIT 1",
                params![receiver, source],
                |r| r.get(0),
            )
            .optional()
            .map_err(db)?;
        id.map(|id| self.job(id)).transpose()
    }
    /// Gallery-only receipt hint for a source whose current revision has no job.
    /// Preparation and deduplication must continue to use exact source revisions.
    pub fn previous_receipts(
        &self,
        receiver: &str,
        sources: &[(String, String)],
    ) -> Result<BTreeMap<String, String>> {
        if sources.len() > 400 {
            return Err(Error::Invalid("source window".into()));
        }
        let mut stmt = self.conn.prepare("SELECT EXISTS(SELECT 1 FROM jobs WHERE receiver_id=?1 AND json_extract(manifest,'$.source_id')=?2 AND state='received')").map_err(db)?;
        let mut states = BTreeMap::new();
        for (id, _) in sources {
            let received: bool = stmt
                .query_row(params![receiver, id], |r| r.get(0))
                .map_err(db)?;
            if received {
                states.insert(id.clone(), "received_previous".into());
            }
        }
        Ok(states)
    }
    pub fn summary(&self, receiver: &str) -> Result<serde_json::Value> {
        self.summary_source(receiver, None)
    }
    pub fn summary_source(
        &self,
        receiver: &str,
        source: Option<&str>,
    ) -> Result<serde_json::Value> {
        let mut stmt = self.conn.prepare("SELECT state,COUNT(*),SUM(confirmed_bytes) FROM jobs WHERE receiver_id=?1 AND (?2 IS NULL OR COALESCE(json_extract(manifest,'$.metadata.source_ref'),'library')=?2) GROUP BY state").map_err(db)?;
        let rows = stmt
            .query_map(params![receiver, source], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, i64>(1)?,
                    r.get::<_, i64>(2)?,
                ))
            })
            .map_err(db)?;
        let mut result = serde_json::json!({"total":0,"confirmed_bytes":0,"received":0,"waiting":0,"failed":0,"queued":0,"running":0,"paused":0});
        let mut count = 0;
        let mut bytes = 0;
        for row in rows {
            let (state, n, b) = row.map_err(db)?;
            result[&state] = n.into();
            count += n;
            bytes += b;
        }
        result["total"] = count.into();
        result["confirmed_bytes"] = bytes.into();
        let (published, publication_failed): (i64, i64) = self.conn.query_row(
            "SELECT COALESCE(SUM(CASE WHEN p.state='complete' THEN 1 ELSE 0 END),0), COALESCE(SUM(CASE WHEN p.state='failed' THEN 1 ELSE 0 END),0) FROM jobs j LEFT JOIN processing_observations p ON p.job_id=j.id WHERE j.receiver_id=?1 AND j.state='received' AND (?2 IS NULL OR COALESCE(json_extract(j.manifest,'$.metadata.source_ref'),'library')=?2)",
            params![receiver, source], |r| Ok((r.get(0)?, r.get(1)?)),
        ).map_err(db)?;
        result["published"] = published.into();
        result["publication_failed"] = publication_failed.into();
        let waiting: Option<(String,i64)> = self.conn.query_row("SELECT error_code,next_attempt_at FROM jobs WHERE receiver_id=?1 AND state='waiting' AND (?2 IS NULL OR COALESCE(json_extract(manifest,'$.metadata.source_ref'),'library')=?2) ORDER BY next_attempt_at,id LIMIT 1",params![receiver,source],|r|Ok((r.get(0)?,r.get(1)?))).optional().map_err(db)?;
        result["waiting_reason"] = waiting
            .as_ref()
            .map(|r| serde_json::json!(r.0))
            .unwrap_or(serde_json::Value::Null);
        result["next_retry_at"] = waiting
            .map(|r| serde_json::json!(r.1))
            .unwrap_or(serde_json::Value::Null);
        Ok(result)
    }
    pub fn paused(&self) -> Result<bool> {
        self.conn
            .query_row("SELECT value FROM settings WHERE key='paused'", [], |r| {
                r.get(0)
            })
            .map_err(db)
    }
    /// Global pause retains attempt bindings so late completion can be reconciled.
    /// The executor must cancel/suspend active network operations when this returns.
    pub fn set_paused(&mut self, paused: bool) -> Result<()> {
        self.conn
            .execute("UPDATE settings SET value=?1 WHERE key='paused'", [paused])
            .map_err(db)?;
        Ok(())
    }
    pub fn claim(&mut self, receiver: &str, now: i64) -> Result<Option<Job>> {
        if now < 0 {
            return Err(Error::Invalid("time".into()));
        }
        if self.paused()? {
            return Ok(None);
        }
        let tx = self.conn.transaction().map_err(db)?;
        let id: Option<i64> = tx.query_row("SELECT id FROM jobs WHERE receiver_id=?1 AND (state='queued' OR (state='waiting' AND next_attempt_at<=?2)) ORDER BY CAST(json_extract(manifest,'$.metadata.created_at_ms') AS INTEGER) DESC,json_extract(manifest,'$.source_id'),id LIMIT 1",params![receiver,now],|r|r.get(0)).optional().map_err(db)?;
        if let Some(id) = id {
            tx.execute("UPDATE jobs SET state='running',generation=generation+1,attempts=attempts+1,error_code=NULL,native_task_id=NULL WHERE id=?1",[id]).map_err(db)?;
        }
        tx.commit().map_err(db)?;
        id.map(|id| self.job(id)).transpose()
    }
    fn current(&self, a: &Attempt) -> Result<Job> {
        let job = self.job(a.job_id)?;
        if job.generation != a.generation || job.state != JobState::Running {
            return Err(Error::Conflict("superseded attempt".into()));
        }
        Ok(job)
    }
    pub fn bind_native_task(&mut self, a: &Attempt, task_id: &str) -> Result<()> {
        let job = self.current(a)?;
        if self.paused()?
            || job
                .native_task_id
                .as_deref()
                .is_some_and(|id| id != task_id)
        {
            return Err(Error::Conflict("native task binding".into()));
        }
        if task_id.is_empty() || task_id.len() > 512 {
            return Err(Error::Invalid("native task id".into()));
        }
        self.conn
            .execute(
                "UPDATE jobs SET native_task_id=?1 WHERE id=?2",
                params![task_id, a.job_id],
            )
            .map_err(db)?;
        Ok(())
    }
    /// Features are accepted only after an authenticated capability check.
    pub fn set_bundle_upload(&mut self, receiver: &str, enabled: bool) -> Result<()> {
        self.conn.execute("INSERT INTO receiver_features VALUES(?1,?2) ON CONFLICT(receiver_id) DO UPDATE SET bundle_upload=excluded.bundle_upload", params![receiver, enabled]).map_err(db)?;
        Ok(())
    }
    pub fn bundle_upload(&self, receiver: &str) -> Result<bool> {
        Ok(self
            .conn
            .query_row(
                "SELECT bundle_upload FROM receiver_features WHERE receiver_id=?1",
                [receiver],
                |r| r.get(0),
            )
            .optional()
            .map_err(db)?
            .unwrap_or(false))
    }
    /// Queue a bounded window with the OS so later uploads do not need a fresh
    /// application wake-up. Legacy multi-request transfers remain serial.
    pub fn concurrent_uploads(&self) -> Result<u32> {
        self.conn
            .query_row(
                "SELECT value FROM settings WHERE key='concurrent_uploads'",
                [],
                |r| r.get(0),
            )
            .map_err(db)
    }
    pub fn set_concurrent_uploads(&mut self, limit: u32) -> Result<()> {
        if !(1..=MAX_CONCURRENT_UPLOADS).contains(&limit) {
            return Err(Error::Invalid("concurrent uploads".into()));
        }
        self.conn
            .execute(
                "UPDATE settings SET value=?1 WHERE key='concurrent_uploads'",
                [limit],
            )
            .map_err(db)?;
        Ok(())
    }
    /// The shared policy applies to native OS requests and the Rust executor.
    pub fn transfer_window(&self, receiver: &str) -> Result<u32> {
        if self.bundle_upload(receiver)? {
            self.concurrent_uploads()
        } else {
            Ok(1)
        }
    }
    pub fn claim_native(&mut self, receiver: &str, now: i64) -> Result<Option<Job>> {
        let active: u32 = self
            .conn
            .query_row(
                "SELECT COUNT(*) FROM jobs WHERE receiver_id=?1 AND state='running'",
                [receiver],
                |r| r.get(0),
            )
            .map_err(db)?;
        let window = self.transfer_window(receiver)?;
        if active >= window {
            return Ok(None);
        }
        self.claim(receiver, now)
    }
    pub fn checkpoint(&self, id: i64) -> Result<Option<AssetStatus>> {
        let value: Option<String> = self
            .conn
            .query_row(
                "SELECT status FROM native_checkpoints WHERE job_id=?1",
                [id],
                |r| r.get(0),
            )
            .optional()
            .map_err(db)?;
        value
            .map(|v| serde_json::from_str(&v).map_err(Into::into))
            .transpose()
    }
    pub fn check_native(&self, a: &Attempt, task_id: &str) -> Result<()> {
        if self.current(a)?.native_task_id.as_deref() != Some(task_id) {
            return Err(Error::Conflict("superseded native task".into()));
        }
        Ok(())
    }
    /// Persist acknowledgement and release the OS binding in the same transaction.
    pub fn complete_native(
        &mut self,
        a: &Attempt,
        task_id: &str,
        status: &AssetStatus,
    ) -> Result<()> {
        self.check_native(a, task_id)?;
        let job = self.current(a)?;
        next_action(&job.asset, status, MAX_CHUNK_BYTES)?;
        let bytes = status
            .resources
            .iter()
            .try_fold(0u64, |n, r| n.checked_add(r.offset))
            .filter(|n| *n <= i64::MAX as u64)
            .ok_or(Error::Capacity)?;
        let tx = self.conn.transaction().map_err(db)?;
        tx.execute(
            "INSERT OR REPLACE INTO native_checkpoints VALUES(?1,?2)",
            params![a.job_id, serde_json::to_string(status)?],
        )
        .map_err(db)?;
        tx.execute("UPDATE jobs SET confirmed_bytes=?1,state=?2,native_task_id=NULL,attempts=0,next_attempt_at=0,error_code=NULL WHERE id=?3",
            params![bytes as i64, if status.receipt==ReceiptState::Received {"received"} else {"queued"},a.job_id]).map_err(db)?;
        if status.receipt == ReceiptState::Received {
            tx.execute("INSERT OR REPLACE INTO processing_observations(job_id,state,error,checked_at) VALUES(?1,?2,?3,0)",
                params![a.job_id, processing_name(&status.processing), status.processing_error]).map_err(db)?;
        }
        tx.commit().map_err(db)?;
        Ok(())
    }
    pub fn clear_checkpoint(&mut self, id: i64) -> Result<()> {
        self.conn
            .execute("DELETE FROM native_checkpoints WHERE job_id=?1", [id])
            .map_err(db)?;
        Ok(())
    }
    /// Only receiver acknowledgements advance confirmed progress or mark receipt.
    pub fn acknowledge(&mut self, a: &Attempt, status: &AssetStatus) -> Result<()> {
        let job = self.current(a)?;
        next_action(&job.asset, status, MAX_CHUNK_BYTES)?;
        let bytes = status
            .resources
            .iter()
            .try_fold(0u64, |n, r| n.checked_add(r.offset))
            .ok_or(Error::Capacity)?;
        if bytes > i64::MAX as u64 {
            return Err(Error::Capacity);
        }
        self.conn.execute("UPDATE jobs SET confirmed_bytes=?1,state=?2,native_task_id=CASE WHEN ?2='received' THEN NULL ELSE native_task_id END WHERE id=?3",params![bytes as i64,if status.receipt==ReceiptState::Received {"received"} else {"running"},a.job_id]).map_err(db)?;
        if status.receipt == ReceiptState::Received {
            self.conn.execute("INSERT OR REPLACE INTO processing_observations(job_id,state,error,checked_at) VALUES(?1,?2,?3,0)",
                params![a.job_id, processing_name(&status.processing), status.processing_error]).map_err(db)?;
        }
        Ok(())
    }
    /// Select a small due batch without changing transport completion or retrying bytes.
    pub fn processing_due(
        &self,
        receiver: &str,
        now: i64,
        limit: u32,
    ) -> Result<Vec<(i64, String)>> {
        let mut stmt = self.conn.prepare("SELECT j.id,j.asset_id FROM jobs j LEFT JOIN processing_observations p ON p.job_id=j.id WHERE j.receiver_id=?1 AND j.state='received' AND (p.state IS NULL OR p.state!='complete') AND (p.checked_at IS NULL OR p.checked_at<=?2) ORDER BY COALESCE(p.checked_at,0),j.id DESC LIMIT ?3").map_err(db)?;
        let result = stmt
            .query_map(params![receiver, now, limit.clamp(1, 20)], |r| {
                Ok((r.get(0)?, r.get(1)?))
            })
            .map_err(db)?
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(db)?;
        Ok(result)
    }
    pub fn processing_event_jobs(&self, receiver: &str) -> Result<Vec<(i64, String)>> {
        let mut query=self.conn.prepare("SELECT j.id,j.asset_id FROM jobs j LEFT JOIN processing_observations p ON p.job_id=j.id WHERE j.receiver_id=?1 AND j.state IN ('running','received') AND (p.state IS NULL OR p.state!='complete') ORDER BY j.id DESC LIMIT 128").map_err(db)?;
        let items = query
            .query_map([receiver], |row| Ok((row.get(0)?, row.get(1)?)))
            .map_err(db)?
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(db)?;
        Ok(items)
    }
    /// First observed Photos publication. Older observations remain undated.
    pub fn publication_time(&self, id: i64) -> Result<Option<u64>> {
        self.conn
            .query_row(
                "SELECT observed_ms FROM publication_times WHERE job_id=?1",
                [id],
                |r| r.get::<_, i64>(0).map(|t| t as u64),
            )
            .optional()
            .map_err(db)
    }
    pub fn observe_processing(&mut self, id: i64, status: &AssetStatus, now: i64) -> Result<()> {
        let job = self.job(id)?;
        if job.state != JobState::Received
            || job.asset.id()? != status.asset_id
            || status.receipt != ReceiptState::Received
        {
            return Err(Error::Conflict("processing observation identity".into()));
        }
        let next = now.saturating_add(if status.processing == ProcessingState::Failed {
            60
        } else {
            15
        });
        self.conn.execute("INSERT OR REPLACE INTO processing_observations(job_id,state,error,checked_at) VALUES(?1,?2,?3,?4)",
            params![id, processing_name(&status.processing), status.processing_error, next]).map_err(db)?;
        if job.processing.as_ref() != Some(&status.processing)
            || job.processing_error != status.processing_error
        {
            // Refresh the UI revision without rewriting a transfer receipt.
            self.conn
                .execute("UPDATE settings SET value=value+1 WHERE key='revision'", [])
                .map_err(db)?;
        }
        Ok(())
    }
    pub fn postpone_processing(&mut self, id: i64, now: i64) -> Result<()> {
        self.conn.execute("INSERT INTO processing_observations(job_id,checked_at) VALUES(?1,?2) ON CONFLICT(job_id) DO UPDATE SET checked_at=excluded.checked_at",
            params![id, now.saturating_add(30)]).map_err(db)?;
        Ok(())
    }
    pub fn fail(&mut self, a: &Attempt, failure: Failure, now: i64) -> Result<()> {
        let job = self.current(a)?;
        self.clear_checkpoint(a.job_id)?;
        // Stable per-job jitter, capped exponential backoff; no sleeping in core.
        let base = if matches!(failure, Failure::Capacity | Failure::LowSpace) {
            60i64
        } else {
            5
        };
        let delay = (base * (1i64 << job.attempts.saturating_sub(1).min(8))).min(900)
            + job.id.rem_euclid(7);
        let due = now.max(0).saturating_add(delay);
        let code = serde_json::to_value(&failure)?.as_str().unwrap().to_owned();
        self.conn.execute("UPDATE jobs SET state=?1,next_attempt_at=?2,error_code=?3,native_task_id=NULL WHERE id=?4",params![if failure.automatic(){"waiting"}else{"failed"},due,code,a.job_id]).map_err(db)?;
        Ok(())
    }
    /// Pause/cancel completion is not a failure and never resets received assets.
    pub fn interrupted(&mut self, a: &Attempt) -> Result<()> {
        self.current(a)?;
        self.clear_checkpoint(a.job_id)?;
        self.conn.execute("UPDATE jobs SET state='queued',generation=generation+1,native_task_id=NULL WHERE id=?1",[a.job_id]).map_err(db)?;
        Ok(())
    }
    pub fn pause_job(&mut self, id: i64) -> Result<Option<String>> {
        let job = self.job(id)?;
        if job.state == JobState::Received {
            return Ok(None);
        }
        self.conn.execute("UPDATE jobs SET state='paused',generation=generation+1,native_task_id=NULL WHERE id=?1",[id]).map_err(db)?;
        Ok(job.native_task_id)
    }
    pub fn retry(&mut self, id: i64) -> Result<()> {
        let job = self.job(id)?;
        if matches!(
            job.state,
            JobState::Waiting | JobState::Failed | JobState::Paused
        ) {
            self.conn.execute("UPDATE jobs SET state='queued',next_attempt_at=0,error_code=NULL,generation=generation+1 WHERE id=?1",[id]).map_err(db)?;
        }
        Ok(())
    }
    /// Called after authenticating the existing peer at its recovered route.
    /// Do not resume global/per-job pauses or retry unrelated content failures.
    pub fn recover_connection(&mut self, receiver: &str) -> Result<usize> {
        self.conn.execute("UPDATE jobs SET state='queued',next_attempt_at=0,error_code=NULL,generation=generation+1 WHERE receiver_id=?1 AND state IN ('waiting','failed') AND error_code IN ('network','authentication')", [receiver]).map_err(db)
    }
    /// The host enumerates all live OS tasks in its session first. Returned IDs
    /// are stale tasks to cancel. Missing tasks are requeued and query receiver
    /// status before uploading, including when a final acknowledgement was lost.
    pub fn reconcile_native(&mut self, live: &BTreeSet<String>) -> Result<Vec<String>> {
        let mut stmt=self.conn.prepare("SELECT id,native_task_id FROM jobs WHERE state='running' AND native_task_id IS NOT NULL").map_err(db)?;
        let rows = stmt
            .query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))
            .map_err(db)?
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(db)?;
        drop(stmt);
        let known: BTreeSet<_> = rows.iter().map(|(_, t)| t.clone()).collect();
        let tx = self.conn.transaction().map_err(db)?;
        for (id, task) in rows {
            if !live.contains(&task) {
                tx.execute("DELETE FROM native_checkpoints WHERE job_id=?1", [id])
                    .map_err(db)?;
                tx.execute("UPDATE jobs SET state='queued',generation=generation+1,native_task_id=NULL WHERE id=?1",[id]).map_err(db)?;
            }
        }
        tx.commit().map_err(db)?;
        Ok(live.difference(&known).cloned().collect())
    }
}
