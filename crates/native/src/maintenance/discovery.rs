//! Idempotent metadata-only handoff from a platform change-token outbox.
//! Once accepted, only the common preparation queue decides order and retry.
use super::*;
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DiscoverySource {
    pub handoff_id: String,
    pub source: String,
    pub created_at_ms: Option<i64>,
    #[serde(default)]
    pub retry_at: i64,
}
impl Maintenance {
    pub(super) fn migrate_discovery(conn: &Connection) -> Result<()> {
        conn.execute_batch("CREATE TABLE IF NOT EXISTS discovery_handoffs(receiver TEXT NOT NULL,handoff TEXT NOT NULL,source TEXT NOT NULL,PRIMARY KEY(receiver,handoff));").map_err(database)?;
        Ok(())
    }
    pub fn handoff_sources(&self, receiver: &str, sources: &[DiscoverySource]) -> Result<()> {
        if receiver.is_empty()
            || receiver.len() > 256
            || sources.len() > 200
            || sources.iter().any(|s| {
                s.handoff_id.is_empty()
                    || s.handoff_id.len() > 128
                    || s.source.is_empty()
                    || s.source.len() > 8192
                    || s.retry_at < 0
                    || s.created_at_ms.is_some_and(|date| date < 0)
            })
        {
            return Err(Error::Invalid("discovery handoff".into()));
        }
        let tx = self.conn.unchecked_transaction().map_err(database)?;
        for source in sources {
            let old: Option<String> = tx
                .query_row(
                    "SELECT source FROM discovery_handoffs WHERE receiver=?1 AND handoff=?2",
                    params![receiver, source.handoff_id],
                    |row| row.get(0),
                )
                .optional()
                .map_err(database)?;
            if let Some(old) = old {
                if old != source.source {
                    return Err(Error::Conflict("discovery handoff identity".into()));
                }
                continue; // Lost reply after preparation completed cannot requeue it.
            }
            tx.execute(
                "INSERT INTO discovery_handoffs VALUES(?1,?2,?3)",
                params![receiver, source.handoff_id, source.source],
            )
            .map_err(database)?;
            tx.execute("INSERT INTO pending_sources(receiver,source,retry_at,created_at_ms) VALUES(?1,?2,?3,?4) ON CONFLICT(receiver,source) DO UPDATE SET retry_at=MAX(pending_sources.retry_at,excluded.retry_at),created_at_ms=COALESCE(pending_sources.created_at_ms,excluded.created_at_ms)",params![receiver,source.source,source.retry_at,source.created_at_ms]).map_err(database)?;
        }
        tx.commit().map_err(database)?;
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn discovery_handoff_retains_retry_and_lost_reply_does_not_resurrect_completed_work() {
        let root = std::env::temp_dir().join(format!(
            "discovery-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let m = Maintenance::open(&root).unwrap();
        let entry = |id: &str, source: &str, date: i64, retry: i64| DiscoverySource {
            handoff_id: id.into(),
            source: source.into(),
            created_at_ms: Some(date),
            retry_at: retry,
        };
        m.handoff_sources(
            "target",
            &[
                entry("a", "older", 100, 0),
                entry("b", "newer", 900, 0),
                entry("c", "retry", 1000, now() + 300),
            ],
        )
        .unwrap();
        assert_eq!(
            m.pending("target").unwrap()["sources"],
            json!(["newer", "older"])
        );
        m.source_result("target", "newer", true).unwrap();
        m.handoff_sources("target", &[entry("b", "newer", 900, 0)])
            .unwrap();
        assert_eq!(m.pending("target").unwrap()["count"], 2);
        assert!(m
            .handoff_sources(
                "target",
                &[
                    entry("fresh", "other", 50, 0),
                    entry("a", "contradictory", 100, 0)
                ]
            )
            .is_err());
        assert_eq!(m.pending("target").unwrap()["count"], 2); // Whole batch rolled back.
        m.handoff_sources("other", &[entry("a", "older", 100, 0)])
            .unwrap();
        assert_eq!(m.pending("other").unwrap()["count"], 1);
        drop(m);
        let m = Maintenance::open(&root).unwrap();
        assert_eq!(m.pending("target").unwrap()["count"], 2);
        m.handoff_sources("target", &[entry("b", "newer", 900, 0)])
            .unwrap();
        assert_eq!(m.pending("target").unwrap()["count"], 2);
        drop(m);
        fs::remove_dir_all(root).unwrap();
    }
}
