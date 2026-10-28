//! Shared preparation membership and decisions. Native hosts retain opaque
//! access descriptors; they do not choose queue order, retry eligibility or IDs.
use super::*;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PreparationRegistration {
    pub receiver_id: String,
    pub request_id: String,
    pub source: String,
    pub revision: Option<String>,
    #[serde(default)]
    pub repeat: bool,
    pub captured_at_ms: Option<i64>,
    pub error: Option<String>,
}
impl Maintenance {
    /// Whole-library pending preparation facts, including source-only legacy
    /// intents. A pending export is not evidence of transfer receipt.
    pub fn library_preparation_states(
        &self,
        receiver: &str,
        handed_off: &std::collections::BTreeSet<String>,
    ) -> Result<std::collections::BTreeMap<String, backupduck_sender::LibrarySourceState>> {
        use backupduck_sender::{LibrarySourceState, LibraryTileState};
        let mut query = self
            .conn
            .prepare(
                "SELECT COALESCE(r.source_ref,p.source),r.revision,p.error_code,p.source
             FROM pending_sources p LEFT JOIN source_preparations r
             ON r.receiver=p.receiver AND r.request=p.source
             WHERE p.receiver=?1 ORDER BY p.rowid",
            )
            .map_err(database)?;
        let rows = query
            .query_map([receiver], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, Option<String>>(1)?,
                    row.get::<_, Option<String>>(2)?,
                    row.get::<_, String>(3)?,
                ))
            })
            .map_err(database)?;
        let mut result = std::collections::BTreeMap::new();
        for row in rows {
            let (source, revision, error_code, request) = row.map_err(database)?;
            if handed_off.contains(&request) {
                continue;
            }
            let attention = error_code.as_deref().is_some_and(|e| {
                !matches!(e, "local_cache_budget" | "local_free_space" | "network")
            });
            result.insert(
                source,
                LibrarySourceState {
                    job_id: None,
                    revision,
                    transfer_state: None,
                    received: None,
                    preparing: true,
                    processing: None,
                    error_code,
                    processing_error: None,
                    tile_state: if attention {
                        LibraryTileState::NeedsYou
                    } else {
                        LibraryTileState::Sending
                    },
                },
            );
        }
        Ok(result)
    }

    pub(super) fn migrate_preparations(conn: &Connection) -> Result<()> {
        conn.execute_batch("CREATE TABLE IF NOT EXISTS source_preparations(
            receiver TEXT NOT NULL, request TEXT NOT NULL, source_ref TEXT NOT NULL,
            revision TEXT, repeating INTEGER NOT NULL,
            completed INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(receiver,request));
            CREATE INDEX IF NOT EXISTS preparation_identity ON source_preparations(receiver,source_ref,revision,repeating,completed);") .map_err(database)?;
        let has_error:bool=conn.query_row("SELECT EXISTS(SELECT 1 FROM pragma_table_info('pending_sources') WHERE name='error_code')",[],|r|r.get(0)).map_err(database)?;
        if !has_error {
            conn.execute("ALTER TABLE pending_sources ADD COLUMN error_code TEXT", [])
                .map_err(database)?;
        }
        // Compatibility with disposable development roots from the first
        // draft: move error ownership onto the common pending row once.
        let old_error:bool=conn.query_row("SELECT EXISTS(SELECT 1 FROM pragma_table_info('source_preparations') WHERE name='error')",[],|r|r.get(0)).map_err(database)?;
        if old_error {
            conn.execute_batch("UPDATE pending_sources SET error_code=(SELECT error FROM source_preparations WHERE receiver=pending_sources.receiver AND request=pending_sources.source) WHERE error_code IS NULL; UPDATE source_preparations SET error=NULL;").map_err(database)?;
        }
        Ok(())
    }
    pub fn register_preparation(&self, r: &PreparationRegistration) -> Result<Value> {
        let result = self.register_preparations(std::slice::from_ref(r))?;
        Ok(result[0].clone())
    }
    pub fn register_preparations(
        &self,
        registrations: &[PreparationRegistration],
    ) -> Result<Value> {
        if registrations.len() > 200 {
            return Err(Error::Invalid("source preparation batch".into()));
        }
        let tx = self.conn.unchecked_transaction().map_err(database)?;
        let results = registrations
            .iter()
            .map(|r| Self::register_preparation_in(&tx, r))
            .collect::<Result<Vec<_>>>()?;
        tx.commit().map_err(database)?;
        Ok(json!(results))
    }
    pub(super) fn register_preparation_in(
        tx: &rusqlite::Transaction<'_>,
        r: &PreparationRegistration,
    ) -> Result<Value> {
        if r.receiver_id.is_empty()
            || r.receiver_id.len() > 256
            || r.request_id.is_empty()
            || r.request_id.len() > 256
            || r.source.is_empty()
            || r.source.len() > 8192
            || r.revision
                .as_ref()
                .is_some_and(|v| v.is_empty() || v.len() > 256)
            || r.error.as_ref().is_some_and(|v| v.len() > 256)
            || r.captured_at_ms.is_some_and(|v| v < 0)
        {
            return Err(Error::Invalid("source preparation".into()));
        }
        // Stable request replay (including migration after a lost reply) must
        // never resurrect preparation already durably acknowledged.
        let existing:Option<(String,Option<String>,bool,bool)>=tx.query_row(
            "SELECT source_ref,revision,repeating,completed FROM source_preparations WHERE receiver=?1 AND request=?2",
            params![r.receiver_id,r.request_id],|row|Ok((row.get(0)?,row.get(1)?,row.get(2)?,row.get(3)?))).optional().map_err(database)?;
        if let Some((source, revision, repeating, completed)) = existing {
            if source != r.source || revision != r.revision || repeating != r.repeat {
                return Err(Error::Conflict("source preparation identity".into()));
            }
            if r.request_id != r.source {
                tx.execute("DELETE FROM pending_sources WHERE receiver=?1 AND source=?2 AND NOT EXISTS(SELECT 1 FROM source_preparations WHERE receiver=?1 AND request=?2)",params![r.receiver_id,r.source]).map_err(database)?;
            }
            return Ok(json!({"request_id":r.request_id,"queued":!completed}));
        }
        // Unknown revisions (e.g. a picker grant pending original hashing) do
        // not provide a dedupe key. The executor resolves the revision later.
        if let Some(revision) = &r.revision {
            let duplicate:Option<String>=tx.query_row(
                "SELECT request FROM source_preparations WHERE receiver=?1 AND source_ref=?2 AND revision=?3 AND repeating=?4 AND completed=0 ORDER BY rowid LIMIT 1",
                params![r.receiver_id,r.source,revision,r.repeat],|row|row.get(0)).optional().map_err(database)?;
            if let Some(request) = duplicate {
                tx.execute("DELETE FROM pending_sources WHERE receiver=?1 AND source=?2 AND NOT EXISTS(SELECT 1 FROM source_preparations WHERE receiver=?1 AND request=?2)",params![r.receiver_id,r.source]).map_err(database)?;
                return Ok(json!({"request_id":request,"queued":true}));
            }
        }
        tx.execute("INSERT INTO source_preparations(receiver,request,source_ref,revision,repeating) VALUES(?1,?2,?3,?4,?5)",
            params![r.receiver_id,r.request_id,r.source,r.revision,r.repeat]).map_err(database)?;
        // Adopt a source-only entry created by shared historical enumeration.
        // It becomes this descriptor-backed request in the same transaction.
        tx.execute("DELETE FROM pending_sources WHERE receiver=?1 AND source=?2 AND NOT EXISTS(SELECT 1 FROM source_preparations WHERE receiver=?1 AND request=?2)",params![r.receiver_id,r.source]).map_err(database)?;
        tx.execute("INSERT INTO pending_sources(receiver,source,created_at_ms,error_code) VALUES(?1,?2,?3,?4) ON CONFLICT(receiver,source) DO UPDATE SET created_at_ms=COALESCE(pending_sources.created_at_ms,excluded.created_at_ms),error_code=excluded.error_code",params![r.receiver_id,r.request_id,r.captured_at_ms,r.error]).map_err(database)?;
        Ok(json!({"request_id":r.request_id,"queued":true}))
    }
    /// Read-only acknowledgement recovery. It must never register an intent
    /// whose enclosing historical transaction was rejected.
    pub fn lookup_preparations(&self, registrations: &[PreparationRegistration]) -> Result<Value> {
        if registrations.len() > 200 {
            return Err(Error::Invalid("preparation lookup batch".into()));
        }
        let mut results = Vec::new();
        for r in registrations {
            let exact:Option<(String,Option<String>,bool,bool)>=self.conn.query_row("SELECT source_ref,revision,repeating,completed FROM source_preparations WHERE receiver=?1 AND request=?2",params![r.receiver_id,r.request_id],|row|Ok((row.get(0)?,row.get(1)?,row.get(2)?,row.get(3)?))).optional().map_err(database)?;
            if let Some((source, revision, repeating, completed)) = exact {
                if source != r.source || revision != r.revision || repeating != r.repeat {
                    return Err(Error::Conflict("preparation lookup identity".into()));
                }
                results
                    .push(json!({"registered":true,"request_id":r.request_id,"queued":!completed}));
                continue;
            }
            let canonical: Option<(String, bool)> = if let Some(revision) = &r.revision {
                self.conn.query_row("SELECT request,completed FROM source_preparations WHERE receiver=?1 AND source_ref=?2 AND revision=?3 AND repeating=?4 ORDER BY completed,rowid DESC LIMIT 1",params![r.receiver_id,r.source,revision,r.repeat],|row|Ok((row.get(0)?,row.get(1)?))).optional().map_err(database)?
            } else {
                None
            };
            results.push(match canonical {
                Some((id, completed)) => {
                    json!({"registered":true,"request_id":id,"queued":!completed})
                }
                None => json!({"registered":false,"request_id":r.request_id}),
            });
        }
        Ok(json!(results))
    }
    pub fn preparation_link(
        &self,
        receiver: &str,
        source: &str,
        revision: &str,
        request: Option<&str>,
        repeating: bool,
    ) -> Result<Option<(String, i64, Option<i64>)>> {
        self.conn.query_row("SELECT p.source,p.feed_cursor,p.added_at_ms FROM pending_sources p LEFT JOIN source_preparations r ON r.receiver=p.receiver AND r.request=p.source WHERE p.receiver=?1 AND COALESCE(r.source_ref,p.source)=?2 AND (r.revision IS NULL OR r.revision=?3) AND (?4 IS NULL OR p.source=?4) AND (?4 IS NOT NULL OR COALESCE(r.repeating,0)=?5) ORDER BY p.rowid LIMIT 1", params![receiver,source,revision,request,repeating],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?))).optional().map_err(database)
    }
    pub fn revision(&self) -> i64 {
        self.conn.total_changes() as i64
    }
    pub fn preparations(&self, receiver: Option<&str>, ready: bool, limit: u32) -> Result<Value> {
        let mut query=self.conn.prepare("SELECT p.source,p.receiver,r.repeating,p.error_code FROM pending_sources p JOIN source_preparations r ON r.receiver=p.receiver AND r.request=p.source WHERE (?1 IS NULL OR p.receiver=?1) AND (?2=0 OR (p.retry_at<=?3 AND (p.error_code IS NULL OR p.error_code IN ('local_cache_budget','local_free_space','network')))) ORDER BY p.created_at_ms DESC,p.source LIMIT ?4").map_err(database)?;
        let rows=query.query_map(params![receiver,ready,now(),limit.clamp(1,500)],|row|Ok(json!({"request_id":row.get::<_,String>(0)?,"target":row.get::<_,String>(1)?,"repeat":row.get::<_,bool>(2)?,"error":row.get::<_,Option<String>>(3)?}))).map_err(database)?.collect::<std::result::Result<Vec<_>,_>>().map_err(database)?;
        Ok(json!(rows))
    }
    pub fn retry_source(&self, receiver: &str, source: &str) -> Result<()> {
        let changed=self.conn.execute("UPDATE pending_sources SET retry_at=0,error_code=NULL WHERE receiver=?1 AND source=?2",params![receiver,source]).map_err(database)?;
        if changed == 0 {
            return Err(Error::NotFound);
        }
        Ok(())
    }
    pub fn retry_sources(&self, receiver: &str, space_only: bool) -> Result<()> {
        let tx = self.conn.unchecked_transaction().map_err(database)?;
        tx.execute("UPDATE pending_sources SET retry_at=0,error_code=NULL WHERE receiver=?1 AND (?2=0 OR error_code IN('local_cache_budget','local_free_space','file_exceeds_cache_budget'))",params![receiver,space_only]).map_err(database)?;
        tx.commit().map_err(database)?;
        Ok(())
    }
    pub fn source_result_with_error(
        &self,
        receiver: &str,
        source: &str,
        complete: bool,
        error: Option<&str>,
    ) -> Result<()> {
        if error.is_some_and(|e| e.len() > 256) {
            return Err(Error::Invalid("source preparation error".into()));
        }
        let tx = self.conn.unchecked_transaction().map_err(database)?;
        if complete {
            tx.execute(
                "UPDATE source_preparations SET completed=1 WHERE receiver=?1 AND request=?2",
                params![receiver, source],
            )
            .map_err(database)?;
            tx.execute(
                "DELETE FROM pending_sources WHERE receiver=?1 AND source=?2",
                params![receiver, source],
            )
            .map_err(database)?;
        } else {
            let retry_at = if error.is_none() || error == Some("network") {
                now() + 300
            } else {
                0
            };
            tx.execute("UPDATE pending_sources SET retry_at=?3,error_code=?4 WHERE receiver=?1 AND source=?2",params![receiver,source,retry_at,error]).map_err(database)?;
        }
        tx.commit().map_err(database)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn transient_source_failure_retries_after_existing_backoff_and_survives_restart() {
        let dir =
            std::env::temp_dir().join(format!("source-backoff-{}-{}", std::process::id(), now()));
        let path = &dir;
        {
            let m = Maintenance::open(path).unwrap();
            m.register_preparations(&[request("retry", "asset", 1)])
                .unwrap();
            m.source_result_with_error("target", "retry", false, Some("network"))
                .unwrap();
            assert!(m
                .preparations(Some("target"), true, 10)
                .unwrap()
                .as_array()
                .unwrap()
                .is_empty());
            let (retry_at, error): (i64, String) = m
                .conn
                .query_row(
                    "SELECT retry_at,error_code FROM pending_sources WHERE source='retry'",
                    [],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )
                .unwrap();
            assert!(retry_at >= now() + 299);
            assert_eq!(error, "network");
            let states = m
                .library_preparation_states("target", &Default::default())
                .unwrap();
            assert_eq!(
                states["asset"].tile_state,
                backupduck_sender::LibraryTileState::Sending
            );
        }
        let m = Maintenance::open(path).unwrap();
        m.conn
            .execute("UPDATE pending_sources SET retry_at=0", [])
            .unwrap();
        assert_eq!(
            m.preparations(Some("target"), true, 10)
                .unwrap()
                .as_array()
                .unwrap()
                .len(),
            1
        );
        assert_eq!(m.pending("target").unwrap()["sources"], json!(["retry"]));
        assert_eq!(m.pending("other").unwrap()["sources"], json!([]));
        m.source_result_with_error("target", "retry", false, Some("source_unavailable"))
            .unwrap();
        assert!(m
            .preparations(Some("target"), true, 10)
            .unwrap()
            .as_array()
            .unwrap()
            .is_empty());
        assert_eq!(
            m.library_preparation_states("target", &Default::default())
                .unwrap()["asset"]
                .tile_state,
            backupduck_sender::LibraryTileState::NeedsYou
        );
    }

    fn request(id: &str, source: &str, date: i64) -> PreparationRegistration {
        PreparationRegistration {
            receiver_id: "target".into(),
            request_id: id.into(),
            source: source.into(),
            revision: Some("1".into()),
            repeat: false,
            captured_at_ms: Some(date),
            error: None,
        }
    }
    #[test]
    fn apple_selected_submission_resumes_exact_repeat_without_retargeting() {
        let root =
            std::env::temp_dir().join(format!("apple-selected-{}-{}", std::process::id(), now()));
        let m = Maintenance::open(&root).unwrap();
        let mut r = request("manual-repeat", "photokit-id", 900);
        r.repeat = true;
        m.register_preparation(&r).unwrap();
        drop(m); // App exits before exporting any original.
        let m = Maintenance::open(&root).unwrap();
        let pending = m.pending("target").unwrap();
        assert_eq!(
            pending["preparations"],
            json!([{
                "request_id":"manual-repeat", "source":"photokit-id", "revision":"1", "repeat":true
            }])
        );
        assert_eq!(m.pending("other-phone").unwrap()["count"], 0);
        // Failed export stays visible and requires retry, not another selection.
        m.source_result_with_error("target", "manual-repeat", false, Some("source_changed"))
            .unwrap();
        assert_eq!(m.pending("target").unwrap()["count"], 1);
        let page = m
            .source_page_sorted("target", false, 0, None, "added", true)
            .unwrap();
        assert_eq!(page["items"][0]["source"], "photokit-id");
        assert_eq!(page["items"][0]["request_id"], "manual-repeat");
        assert_eq!(page["items"][0]["error_code"], "source_changed");
        assert_eq!(m.pending("target").unwrap()["preparations"], json!([]));
        m.retry_source("target", "manual-repeat").unwrap();
        assert_eq!(
            m.pending("target").unwrap()["preparations"][0]["repeat"],
            true
        );
        assert_eq!(
            m.pending("target").unwrap()["preparations"][0]["request_id"],
            "manual-repeat"
        );
        m.source_result("target", "manual-repeat", true).unwrap();
        assert_eq!(m.register_preparation(&r).unwrap()["queued"], false);
        assert_eq!(m.pending("target").unwrap()["count"], 0);
        drop(m);
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn common_preparation_adopts_history_dedupes_orders_and_replays_completion() {
        let root = std::env::temp_dir().join(format!(
            "prep-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let m = Maintenance::open(&root).unwrap();
        let history = m.history_control("target", HistoryAction::Start).unwrap();
        m.history_batch(
            "target",
            history.run,
            &[("old".into(), "1".into()), ("new".into(), "1".into())],
            &BTreeMap::new(),
            true,
        )
        .unwrap();
        m.register_preparation(&request("request-old", "old", 100))
            .unwrap();
        m.register_preparation(&request("request-new", "new", 900))
            .unwrap();
        assert_eq!(
            m.pending("target").unwrap()["sources"],
            json!(["request-new", "request-old"])
        );
        assert_eq!(m.history_status("target").unwrap().unwrap().pending, 2);
        let browse = m
            .source_page_sorted("target", false, 0, None, "capture", true)
            .unwrap();
        assert_eq!(browse["items"][0]["source"], "new");
        assert_eq!(browse["items"][0]["request_id"], "request-new");
        assert_eq!(
            m.pending_states("target", &[("old".into(), "1".into())])
                .unwrap()["old"],
            "preparing"
        );
        // Replayed enumeration cannot add a ghost source-only pending row.
        m.schedule_sources("target", &["old".into()]).unwrap();
        assert_eq!(
            m.register_preparation(&request("duplicate", "old", 100))
                .unwrap()["request_id"],
            "request-old"
        );
        assert_eq!(m.pending("target").unwrap()["count"], 2);
        m.source_result_with_error("target", "request-new", false, Some("source_changed"))
            .unwrap();
        assert_eq!(
            m.preparations(Some("target"), true, 10)
                .unwrap()
                .as_array()
                .unwrap()
                .len(),
            1
        );
        m.retry_sources("target", true).unwrap();
        assert_eq!(
            m.preparations(Some("target"), true, 10)
                .unwrap()
                .as_array()
                .unwrap()
                .len(),
            1
        );
        m.retry_sources("target", false).unwrap();
        assert_eq!(
            m.preparations(Some("target"), true, 10)
                .unwrap()
                .as_array()
                .unwrap()
                .len(),
            2
        );
        m.source_result("target", "request-new", true).unwrap();
        assert_eq!(m.history_status("target").unwrap().unwrap().pending, 1);
        drop(m);
        let m = Maintenance::open(&root).unwrap();
        assert_eq!(
            m.register_preparation(&request("request-new", "new", 900))
                .unwrap()["queued"],
            false
        );
        assert_eq!(m.pending("target").unwrap()["count"], 1);
        let mut changed = request("request-old", "different", 100);
        assert!(m.register_preparation(&changed).is_err());
        changed = request("other-target", "old", 100);
        changed.receiver_id = "other".into();
        m.register_preparation(&changed).unwrap();
        assert_eq!(m.pending("target").unwrap()["count"], 1);
        assert_eq!(m.pending("other").unwrap()["count"], 1);
        // A failed batch cannot partially register earlier descriptors.
        let good = request("atomic-good", "atomic", 100);
        let mut invalid = request("atomic-invalid", "invalid", 100);
        invalid.source = String::new();
        assert!(m.register_preparations(&[good, invalid]).is_err());
        assert_eq!(m.pending("target").unwrap()["count"], 1);
        // The legacy Apple source-only interface shares the same error gate.
        m.schedule_sources("legacy", &["native-id".into()]).unwrap();
        m.source_result_with_error("legacy", "native-id", false, Some("source_changed"))
            .unwrap();
        assert_eq!(m.pending("legacy").unwrap()["count"], 1);
        assert_eq!(m.pending("legacy").unwrap()["sources"], json!([]));
        m.retry_sources("legacy", false).unwrap();
        assert_eq!(
            m.pending("legacy").unwrap()["sources"],
            json!(["native-id"])
        );
        // Unknown revisions and explicit rebackup intents are kept distinct.
        let mut unknown = request("picker-1", "picker", 0);
        unknown.revision = None;
        m.register_preparation(&unknown).unwrap();
        unknown.request_id = "picker-2".into();
        m.register_preparation(&unknown).unwrap();
        let mut repeat = request("repeat", "old", 100);
        repeat.repeat = true;
        m.register_preparation(&repeat).unwrap();
        assert_eq!(m.pending("target").unwrap()["count"], 4);
        drop(m);
        fs::remove_dir_all(root).unwrap();
    }
}
