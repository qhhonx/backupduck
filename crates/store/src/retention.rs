//! Host-local delivery evidence. This is not a cloud receipt or original archive.
use super::*;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GalleryCopy {
    pub locator: String,
    pub sha256: String,
    pub size: u64,
    /// The exact MediaStore display name chosen at publication. Older receipts omit it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
}
impl GalleryCopy {
    fn validate(&self) -> Result<()> {
        if self.locator.is_empty()
            || self.locator.len() > 2048
            || self.locator.chars().any(char::is_control)
            || !valid_digest(&self.sha256)
            || self.size == 0
            || self.size > i64::MAX as u64
            || self.display_name.as_ref().is_some_and(|name| {
                name.is_empty()
                    || name.len() > 255
                    || name.contains(['/', '\\'])
                    || name.chars().any(char::is_control)
            })
        {
            return Err(Error::Invalid("gallery copy".into()));
        }
        Ok(())
    }
}

#[cfg(test)]
mod audit_name_tests {
    use super::GalleryCopy;

    #[test]
    fn old_receipt_loads_and_new_display_name_is_checked() {
        let old = format!(
            r#"{{"locator":"content://media/1","sha256":"{}","size":2}}"#,
            "a".repeat(64)
        );
        let mut copy: GalleryCopy = serde_json::from_str(&old).unwrap();
        assert_eq!(copy.display_name, None);
        copy.display_name = Some("BD_20260930_000000Z_abcd_MP.heic".into());
        copy.validate().unwrap();
        assert!(serde_json::to_string(&copy)
            .unwrap()
            .contains("display_name"));
        copy.display_name = Some("../other.jpg".into());
        assert!(copy.validate().is_err());
    }
}
#[derive(Serialize)]
pub struct GalleryCandidate {
    pub publication: Publication,
    pub copy: Option<GalleryCopy>,
    pub confirmed: bool,
}
impl Receiver {
    /// Snapshot received records, never capture dates or a wall-clock cutoff.
    /// Pending receptions become eligible when they complete after this choice.
    pub fn set_relay_history(&mut self, include_history: bool) -> Result<()> {
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db)?;
        tx.execute("DELETE FROM relay_exclusions", []).map_err(db)?;
        if !include_history {
            tx.execute(
                "INSERT INTO relay_exclusions SELECT id FROM assets WHERE received=1",
                [],
            )
            .map_err(db)?;
        }
        tx.commit().map_err(db)
    }
    pub fn relay_eligible(&self, id: &str) -> Result<bool> {
        self.conn
            .query_row(
                "SELECT NOT EXISTS(SELECT 1 FROM relay_exclusions WHERE asset_id=?1)",
                [id],
                |r| r.get(0),
            )
            .map_err(db)
    }

    /// Estimate physical bytes freed by this exact plan, accounting for blobs
    /// still referenced by any retained asset outside the plan.
    pub fn gallery_release_bytes(&self, ids: &[String]) -> Result<u64> {
        let encoded = serde_json::to_string(ids)?;
        let bytes: i64 = self.conn.query_row("SELECT COALESCE(SUM(size),0) FROM blobs WHERE ready=1 AND EXISTS (SELECT 1 FROM assets,json_each(assets.manifest,'$.resources') r WHERE assets.id IN (SELECT value FROM json_each(?1)) AND originals_released=0 AND json_extract(r.value,'$.sha256')=blobs.hash) AND NOT EXISTS (SELECT 1 FROM assets,json_each(assets.manifest,'$.resources') r WHERE originals_released=0 AND assets.id NOT IN (SELECT value FROM json_each(?1)) AND json_extract(r.value,'$.sha256')=blobs.hash)", [encoded], |r| r.get(0)).map_err(db)?;
        Ok(bytes as u64)
    }
    pub fn expected_gallery_copy(&self, id: &str) -> Result<Option<GalleryCopy>> {
        let value: Option<String> = self
            .conn
            .query_row(
                "SELECT copy FROM gallery_expected WHERE asset_id=?1",
                [id],
                |r| r.get(0),
            )
            .optional()
            .map_err(db)?;
        value
            .map(|v| serde_json::from_str(&v).map_err(Error::from))
            .transpose()
    }
    pub fn prepare_gallery_copy(&mut self, id: &str, copy: &GalleryCopy) -> Result<()> {
        copy.validate()?;
        let eligible: bool = self
            .conn
            .query_row(
                "SELECT received=1 AND originals_released=0 FROM assets WHERE id=?1",
                [id],
                |r| r.get(0),
            )
            .map_err(db)?;
        if !eligible {
            return Err(Error::Integrity);
        }
        if self.gallery_copy(id)?.is_some_and(|old| old != *copy) {
            return Err(Error::Integrity);
        }
        // Only the host's owned pending item may be replaced. Complete copies
        // are immutable and must be read back against existing evidence.
        self.conn.execute("INSERT INTO gallery_expected(asset_id,copy) VALUES(?1,?2) ON CONFLICT(asset_id) DO UPDATE SET copy=excluded.copy", params![id,serde_json::to_string(copy)?]).map_err(db)?;
        Ok(())
    }
    pub fn gallery_copy(&self, id: &str) -> Result<Option<GalleryCopy>> {
        let value: Option<String> = self
            .conn
            .query_row(
                "SELECT copy FROM gallery_copies WHERE asset_id=?1",
                [id],
                |r| r.get(0),
            )
            .optional()
            .map_err(db)?;
        value
            .map(|v| serde_json::from_str(&v).map_err(Error::from))
            .transpose()
    }
    /// The native adapter freshly verifies complete delivery bytes before calling.
    /// Record the immutable evidence and publication completion atomically.
    pub fn record_gallery_copy(&mut self, id: &str, copy: &GalleryCopy) -> Result<()> {
        copy.validate()?;
        let received: bool = self
            .conn
            .query_row("SELECT received FROM assets WHERE id=?1", [id], |r| {
                r.get(0)
            })
            .map_err(db)?;
        if !received {
            return Err(Error::Integrity);
        }
        if self.gallery_copy(id)?.is_some_and(|old| old != *copy) {
            return Err(Error::Conflict("gallery copy changed".into()));
        }
        if self
            .expected_gallery_copy(id)?
            .is_some_and(|old| old != *copy)
        {
            return Err(Error::Integrity);
        }
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db)?;
        tx.execute(
            "INSERT OR IGNORE INTO gallery_copies(asset_id,copy) VALUES(?1,?2)",
            params![id, serde_json::to_string(copy)?],
        )
        .map_err(db)?;
        tx.execute("DELETE FROM gallery_expected WHERE asset_id=?1", [id])
            .map_err(db)?;
        tx.execute("UPDATE assets SET processing='complete',published_at_ms=COALESCE(published_at_ms,?2) WHERE id=?1", params![id, now_ms()?])
            .map_err(db)?;
        tx.commit().map_err(db)?;
        self.publish_progress(&self.asset(id)?, self.status(id)?);
        Ok(())
    }
    /// Independent opt-in relay policy; never pass gallery evidence to archive
    /// reclamation. The fresh proof must exactly match recorded delivery bytes.
    pub fn release_gallery_copy(
        &mut self,
        id: &str,
        verified: &GalleryCopy,
        relay_enabled: bool,
    ) -> Result<u64> {
        if !relay_enabled {
            return Err(Error::Conflict("relay disabled".into()));
        }
        verified.validate()?;
        if self.gallery_copy(id)?.as_ref() != Some(verified) {
            return Err(Error::Integrity);
        }
        let eligible: bool = self
            .conn
            .query_row(
                "SELECT received=1 AND processing='complete' FROM assets WHERE id=?1",
                [id],
                |r| r.get(0),
            )
            .map_err(db)?;
        if !eligible {
            return Err(Error::Integrity);
        }
        // Mark before deleting, preserving receipts and recovery after a crash.
        self.conn.execute("UPDATE assets SET originals_released=1,release_reason='gallery' WHERE id=?1 AND originals_released=0",[id]).map_err(db)?;
        self.reclaim_unreferenced()
    }
    pub fn gallery_candidates(&self, after: &str) -> Result<Vec<GalleryCandidate>> {
        self.gallery_candidates_scoped(after, false)
    }
    pub fn gallery_candidates_scoped(
        &self,
        after: &str,
        manual: bool,
    ) -> Result<Vec<GalleryCandidate>> {
        if !after.is_empty() && !valid_digest(after) {
            return Err(Error::Invalid("gallery cursor".into()));
        }
        let mut query = self.conn.prepare("SELECT id FROM assets WHERE received=1 AND processing='complete' AND originals_released=0 AND id>?1 AND (?2 OR NOT EXISTS(SELECT 1 FROM relay_exclusions WHERE asset_id=assets.id)) ORDER BY id LIMIT 4").map_err(db)?;
        let ids = query
            .query_map(params![after, manual], |r| r.get::<_, String>(0))
            .map_err(db)?
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(db)?;
        ids.into_iter()
            .map(|id| {
                let asset = self.asset(&id)?;
                let resources = asset
                    .resources
                    .iter()
                    .map(|r| (r.sha256.clone(), self.paths(&r.sha256).1))
                    .collect();
                let confirmed_copy = self.gallery_copy(&id)?;
                let confirmed = confirmed_copy.is_some();
                let copy = confirmed_copy.or(self.expected_gallery_copy(&id)?);
                Ok(GalleryCandidate {
                    publication: Publication {
                        id,
                        asset,
                        resources,
                        processing: ProcessingState::Complete,
                    },
                    copy,
                    confirmed,
                })
            })
            .collect()
    }
}
