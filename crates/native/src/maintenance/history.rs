//! Durable enumeration runs. Scan completion is deliberately not backup completion.
use super::*;

#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "snake_case")]
pub enum HistoryAction {
    Start,
    Restart,
    Pause,
    Resume,
}
#[derive(Serialize, Deserialize, Debug)]
pub struct HistoryStatus {
    pub run: i64,
    pub state: String,
    pub checked: i64,
    pub pending: i64,
    pub snapshot_id: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub preparations: Vec<Value>,
}
impl Maintenance {
    pub fn history_status(&self, receiver: &str) -> Result<Option<HistoryStatus>> {
        let run: Option<(i64, String, Option<String>)> = self
            .conn
            .query_row(
                "SELECT run,state,snapshot_id FROM history_runs WHERE receiver=?1",
                [receiver],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()
            .map_err(database)?;
        run.map(|(run,state,snapshot_id)| {
            let checked = self.conn.query_row("SELECT COUNT(*) FROM history_members WHERE receiver=?1", [receiver], |r|r.get(0)).map_err(database)?;
            let pending = self.conn.query_row("SELECT COUNT(*) FROM history_members h WHERE h.receiver=?1 AND EXISTS(SELECT 1 FROM pending_sources p WHERE p.receiver=h.receiver AND (p.source=h.source OR EXISTS(SELECT 1 FROM source_preparations r WHERE r.receiver=p.receiver AND r.request=p.source AND r.source_ref=h.source)))", [receiver], |r|r.get(0)).map_err(database)?;
            Ok(HistoryStatus {run,state,checked,pending,snapshot_id,preparations:Vec::new()})
        }).transpose()
    }
    #[cfg(test)]
    pub fn history_control(&self, receiver: &str, action: HistoryAction) -> Result<HistoryStatus> {
        self.history_control_with_snapshot(receiver, action, None)
    }
    pub fn history_control_with_snapshot(
        &self,
        receiver: &str,
        action: HistoryAction,
        snapshot: Option<&str>,
    ) -> Result<HistoryStatus> {
        if snapshot.is_some_and(|id| id.is_empty() || id.len() > 128) {
            return Err(Error::Invalid("history snapshot identity".into()));
        }
        if receiver.is_empty() || receiver.len() > 256 {
            return Err(Error::Invalid("history receiver".into()));
        }
        let event = match &action {
            HistoryAction::Start => "history_scan_started",
            HistoryAction::Restart => "history_scan_started",
            HistoryAction::Pause => "history_scan_paused",
            HistoryAction::Resume => "history_scan_resumed",
        };
        let restarting = matches!(action, HistoryAction::Restart);
        let tx = self.conn.unchecked_transaction().map_err(database)?;
        match action {
            HistoryAction::Start | HistoryAction::Restart => {
                let old: Option<(i64, String)> = tx
                    .query_row(
                        "SELECT run,state FROM history_runs WHERE receiver=?1",
                        [receiver],
                        |r| Ok((r.get(0)?, r.get(1)?)),
                    )
                    .optional()
                    .map_err(database)?;
                // Repeated clicks are idempotent; starting again is explicit after enumeration.
                if restarting || old.as_ref().is_none_or(|(_, s)| s == "scanned") {
                    let run = old.map_or(1, |(r, _)| r.saturating_add(1));
                    tx.execute("INSERT INTO history_runs(receiver,run,state,snapshot_id) VALUES(?1,?2,'scanning',?3) ON CONFLICT(receiver) DO UPDATE SET run=excluded.run,state=excluded.state,snapshot_id=excluded.snapshot_id",params![receiver,run,snapshot]).map_err(database)?;
                    tx.execute("DELETE FROM history_members WHERE receiver=?1", [receiver])
                        .map_err(database)?;
                }
            }
            HistoryAction::Pause => {
                tx.execute(
                    "UPDATE history_runs SET state='paused' WHERE receiver=?1 AND state='scanning'",
                    [receiver],
                )
                .map_err(database)?;
            }
            HistoryAction::Resume => {
                tx.execute(
                    "UPDATE history_runs SET state='scanning' WHERE receiver=?1 AND state='paused'",
                    [receiver],
                )
                .map_err(database)?;
            }
        }
        tx.commit().map_err(database)?;
        let _ = self.log(event, None, None);
        self.history_status(receiver)?.ok_or(Error::NotFound)
    }
    #[cfg(test)]
    pub fn history_batch(
        &self,
        receiver: &str,
        run: i64,
        sources: &[(String, String)],
        known: &BTreeMap<String, String>,
        finished: bool,
    ) -> Result<HistoryStatus> {
        self.history_batch_with_preparations(receiver, run, sources, known, finished, None, &[])
    }
    // One transaction binds enumeration, snapshot and preparation registrations.
    #[allow(clippy::too_many_arguments)]
    pub fn history_batch_with_preparations(
        &self,
        receiver: &str,
        run: i64,
        sources: &[(String, String)],
        known: &BTreeMap<String, String>,
        finished: bool,
        snapshot: Option<&str>,
        registrations: &[PreparationRegistration],
    ) -> Result<HistoryStatus> {
        if registrations.len() > 200
            || registrations.iter().any(|r| {
                r.receiver_id != receiver
                    || r.repeat
                    || !sources
                        .iter()
                        .any(|(id, rev)| id == &r.source && r.revision.as_ref() == Some(rev))
            })
        {
            return Err(Error::Invalid("history preparation scope".into()));
        }
        if sources.len() > 200
            || sources.iter().any(|(id, rev)| {
                id.is_empty() || id.len() > 8192 || rev.is_empty() || rev.len() > 256
            })
        {
            return Err(Error::Invalid("history batch".into()));
        }
        let tx = self.conn.unchecked_transaction().map_err(database)?;
        let current: Option<(String, Option<String>)> = tx
            .query_row(
                "SELECT state,snapshot_id FROM history_runs WHERE receiver=?1 AND run=?2",
                params![receiver, run],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()
            .map_err(database)?;
        let Some((state, bound_snapshot)) = current else {
            return Err(Error::Conflict("history scan changed".into()));
        };
        if bound_snapshot.as_deref() != snapshot {
            return Err(Error::Conflict("history snapshot changed".into()));
        }
        if state != "scanning" {
            // A final reply or platform cursor write can be lost. Replay only
            // exact members already committed in the same completed run.
            if state != "scanned" || !finished {
                return Err(Error::Conflict("history scan changed".into()));
            }
            for (source, revision) in sources {
                let exact:bool=tx.query_row("SELECT EXISTS(SELECT 1 FROM history_members WHERE receiver=?1 AND source=?2 AND revision=?3)",params![receiver,source,revision],|r|r.get(0)).map_err(database)?;
                if !exact {
                    return Err(Error::Conflict("history completed membership".into()));
                }
            }
        }
        for (source, revision) in sources {
            tx.execute("INSERT INTO history_members(receiver,source,revision) VALUES(?1,?2,?3) ON CONFLICT(receiver,source) DO UPDATE SET revision=excluded.revision",params![receiver,source,revision]).map_err(database)?;
            if known.get(source).is_none_or(|state| state == "failed") {
                tx.execute(
                    "INSERT OR IGNORE INTO pending_sources(receiver,source) VALUES(?1,?2)",
                    params![receiver, source],
                )
                .map_err(database)?;
            }
        }
        let mut prepared = Vec::new();
        for registration in registrations {
            let result = Self::register_preparation_in(&tx, registration)?;
            if known
                .get(&registration.source)
                .is_some_and(|state| state != "failed")
            {
                let request = result["request_id"]
                    .as_str()
                    .ok_or_else(|| Error::Storage("preparation result".into()))?;
                tx.execute(
                    "UPDATE source_preparations SET completed=1 WHERE receiver=?1 AND request=?2",
                    params![receiver, request],
                )
                .map_err(database)?;
                tx.execute(
                    "DELETE FROM pending_sources WHERE receiver=?1 AND source=?2",
                    params![receiver, request],
                )
                .map_err(database)?;
                prepared.push(json!({"request_id":request,"queued":false}));
            } else {
                prepared.push(result);
            }
        }
        if finished {
            tx.execute(
                "UPDATE history_runs SET state='scanned' WHERE receiver=?1 AND run=?2",
                params![receiver, run],
            )
            .map_err(database)?;
        }
        tx.commit().map_err(database)?;
        if finished {
            let _ = self.log("history_scan_finished", None, None);
        }
        let mut status = self.history_status(receiver)?.ok_or(Error::NotFound)?;
        status.preparations = prepared;
        Ok(status)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn history_is_resumable_idempotent_and_receiver_scoped() {
        let root = std::env::temp_dir().join(format!("backupduck-history-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let m = Maintenance::open(&root).unwrap();
        m.schedule_sources("a", &["new-photo".into()]).unwrap();
        let first = m.history_control("a", HistoryAction::Start).unwrap();
        assert_eq!(
            m.history_control("a", HistoryAction::Start).unwrap().run,
            first.run
        );
        let sources = vec![
            ("one".into(), "1".into()),
            ("already-received".into(), "1".into()),
        ];
        let known = BTreeMap::from([("already-received".into(), "received".into())]);
        let s = m
            .history_batch("a", first.run, &sources, &known, false)
            .unwrap();
        assert_eq!((s.checked, s.pending), (2, 1));
        let restarted = m.history_control("a", HistoryAction::Restart).unwrap();
        assert!(restarted.run > first.run);
        assert_eq!(restarted.checked, 0);
        assert!(m
            .history_batch("a", first.run, &sources, &known, false)
            .is_err());
        let first = restarted;
        m.history_batch("a", first.run, &sources, &known, false)
            .unwrap();
        m.history_control("a", HistoryAction::Pause).unwrap();
        assert!(m
            .history_batch("a", first.run, &sources, &known, true)
            .is_err());
        assert_eq!(m.pending("a").unwrap()["count"], 2);
        drop(m);
        let m = Maintenance::open(&root).unwrap();
        assert_eq!(m.history_status("a").unwrap().unwrap().state, "paused");
        assert!(m.history_status("b").unwrap().is_none());
        m.history_control("a", HistoryAction::Resume).unwrap();
        m.source_result("a", "one", true).unwrap();
        let known = BTreeMap::from([
            ("one".into(), "queued".into()),
            ("already-received".into(), "received".into()),
        ]);
        let s = m
            .history_batch("a", first.run, &sources, &known, true)
            .unwrap();
        assert_eq!((s.checked, s.pending), (2, 0));
        assert_eq!(s.state, "scanned");
        assert_eq!(m.pending("a").unwrap()["count"], 1); // incremental work survives
        let second = m.history_control("a", HistoryAction::Start).unwrap();
        assert!(second.run > first.run);
        assert!(m
            .history_batch("a", first.run, &sources, &known, true)
            .is_err());
        m.history_batch("a", second.run, &sources, &known, true)
            .unwrap();
        assert_eq!(m.pending("a").unwrap()["count"], 1);
        drop(m);
        fs::remove_dir_all(root).unwrap();
    }
}

#[cfg(test)]
mod snapshot_tests {
    use super::*;
    #[test]
    fn snapshots_fence_runs_and_final_history_reply_replays_without_new_members() {
        let root = std::env::temp_dir().join(format!(
            "history-snapshot-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let m = Maintenance::open(&root).unwrap();
        let first = m
            .history_control_with_snapshot("target", HistoryAction::Start, Some("snapshot-a"))
            .unwrap();
        let registration = |id: &str, source: &str| PreparationRegistration {
            receiver_id: "target".into(),
            request_id: id.into(),
            source: source.into(),
            revision: Some("1".into()),
            repeat: false,
            captured_at_ms: Some(100),
            error: None,
        };
        let source = vec![("old".into(), "1".into())];
        let rejected = registration("rejected", "old");
        assert!(m
            .history_batch_with_preparations(
                "target",
                first.run,
                &source,
                &BTreeMap::new(),
                true,
                Some("snapshot-b"),
                &[rejected]
            )
            .is_err());
        assert_eq!(m.history_status("target").unwrap().unwrap().checked, 0);
        assert_eq!(m.pending("target").unwrap()["count"], 0);
        let approved = registration("approved", "old");
        let result = m
            .history_batch_with_preparations(
                "target",
                first.run,
                &source,
                &BTreeMap::new(),
                true,
                Some("snapshot-a"),
                &[approved],
            )
            .unwrap();
        assert_eq!((result.checked, result.pending), (1, 1));
        assert_eq!(result.preparations[0]["queued"], true);
        // Lost final response/local cursor: same frozen membership is replayable.
        let replay = registration("replay", "old");
        let result = m
            .history_batch_with_preparations(
                "target",
                first.run,
                &source,
                &BTreeMap::new(),
                true,
                Some("snapshot-a"),
                &[replay],
            )
            .unwrap();
        assert_eq!(result.preparations[0]["request_id"], "approved");
        assert_eq!(m.pending("target").unwrap()["count"], 1);
        assert!(m
            .history_batch_with_preparations(
                "target",
                first.run,
                &[("later".into(), "1".into())],
                &BTreeMap::new(),
                true,
                Some("snapshot-a"),
                &[]
            )
            .is_err());
        let next = m
            .history_control_with_snapshot("target", HistoryAction::Restart, Some("snapshot-b"))
            .unwrap();
        m.history_control("target", HistoryAction::Pause).unwrap();
        assert!(m
            .history_batch_with_preparations(
                "target",
                next.run,
                &source,
                &BTreeMap::new(),
                true,
                Some("snapshot-b"),
                &[]
            )
            .is_err());
        let resumed = m.history_control("target", HistoryAction::Resume).unwrap();
        assert_eq!(resumed.snapshot_id.as_deref(), Some("snapshot-b"));
        assert!(m
            .history_batch_with_preparations(
                "target",
                first.run,
                &source,
                &BTreeMap::new(),
                true,
                Some("snapshot-a"),
                &[]
            )
            .is_err());
        let received = BTreeMap::from([("old".into(), "received".into())]);
        let done = registration("already-received", "old");
        let result = m
            .history_batch_with_preparations(
                "target",
                next.run,
                &source,
                &received,
                true,
                Some("snapshot-b"),
                &[done],
            )
            .unwrap();
        assert_eq!(result.pending, 0);
        assert_eq!(result.preparations[0]["queued"], false);
        let unaccepted = registration("unaccepted", "later");
        assert_eq!(
            m.lookup_preparations(&[unaccepted]).unwrap()[0]["registered"],
            false
        );
        drop(m);
        fs::remove_dir_all(root).unwrap();
    }
}
