//! Whole-library presentation from persisted transfer and publication facts.
use super::*;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LibraryTileState {
    Sending,
    Saving,
    Saved,
    NeedsYou,
    Unknown,
}

#[derive(Clone, Debug, Serialize)]
pub struct LibrarySourceState {
    pub job_id: Option<i64>,
    pub revision: Option<String>,
    pub transfer_state: Option<JobState>,
    pub received: Option<bool>,
    pub preparing: bool,
    pub processing: Option<ProcessingState>,
    pub error_code: Option<String>,
    pub processing_error: Option<String>,
    pub tile_state: LibraryTileState,
}

impl Sender {
    /// Preparation membership already handed to jobs, including interrupted
    /// host acknowledgements. These pending rows must not hide job facts.
    pub fn handed_off_preparations(&self, receiver: &str) -> Result<BTreeSet<String>> {
        let mut query = self
            .conn
            .prepare("SELECT request FROM job_preparations WHERE receiver=?1")
            .map_err(db)?;
        let rows = query
            .query_map([receiver], |row| row.get::<_, String>(0))
            .map_err(db)?;
        rows.collect::<std::result::Result<_, _>>().map_err(db)
    }
    /// One query, no per-source lookups or manifest/resource deserialization.
    /// Latest job wins, exactly as in `latest_source_job`; an older receipt must
    /// not hide an edited revision or an explicit repeat still being sent.
    pub fn library_source_states(
        &self,
        receiver: &str,
    ) -> Result<BTreeMap<String, LibrarySourceState>> {
        let mut query = self
            .conn
            .prepare(
                "WITH latest AS (
                SELECT MAX(id) AS id FROM jobs WHERE receiver_id=?1
                GROUP BY json_extract(manifest,'$.source_id')
            )
            SELECT json_extract(j.manifest,'$.source_id'),j.id,
                json_extract(j.manifest,'$.revision'),j.state,p.state,
                j.error_code,p.error
            FROM latest JOIN jobs j ON j.id=latest.id
            LEFT JOIN processing_observations p ON p.job_id=j.id",
            )
            .map_err(db)?;
        let rows = query
            .query_map([receiver], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, Option<String>>(4)?,
                    row.get::<_, Option<String>>(5)?,
                    row.get::<_, Option<String>>(6)?,
                ))
            })
            .map_err(db)?;
        let mut result = BTreeMap::new();
        for row in rows {
            let (source, job_id, revision, state, processing, error_code, processing_error) =
                row.map_err(db)?;
            let transfer_state: JobState = serde_json::from_value(serde_json::json!(state))?;
            let processing: Option<ProcessingState> = processing
                .map(|s| serde_json::from_value(serde_json::json!(s)))
                .transpose()?;
            let received = transfer_state == JobState::Received;
            let tile_state = match (&transfer_state, &processing) {
                (JobState::Failed, _) => LibraryTileState::NeedsYou,
                (JobState::Received, Some(ProcessingState::Pending)) => LibraryTileState::Saving,
                (JobState::Received, Some(ProcessingState::Complete)) => LibraryTileState::Saved,
                (JobState::Received, Some(ProcessingState::Failed)) => LibraryTileState::NeedsYou,
                (JobState::Received, _) => LibraryTileState::Unknown,
                _ => LibraryTileState::Sending,
            };
            result.insert(
                source,
                LibrarySourceState {
                    job_id: Some(job_id),
                    revision: Some(revision),
                    transfer_state: Some(transfer_state),
                    received: Some(received),
                    preparing: false,
                    processing,
                    error_code,
                    processing_error,
                    tile_state,
                },
            );
        }
        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Temp(std::path::PathBuf);
    impl Temp {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "backupduck-library-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            ));
            Self(path)
        }
    }
    impl Drop for Temp {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    fn enqueue(sender: &mut Sender, receiver: &str, source: &str, revision: &str) -> Job {
        let hash = digest(b"synthetic");
        sender
            .enqueue(
                receiver,
                Asset {
                    version: PROTOCOL_VERSION,
                    source_id: source.into(),
                    revision: revision.into(),
                    kind: AssetKind::Photo,
                    metadata: BTreeMap::new(),
                    resources: vec![Resource {
                        role: ResourceRole::Photo,
                        filename: "test.jpg".into(),
                        media_type: "image/jpeg".into(),
                        size: 9,
                        sha256: hash.clone(),
                    }],
                },
                BTreeMap::from([(hash, "opaque-export".into())]),
            )
            .unwrap()
    }

    #[test]
    fn metadata_revision_reuses_receipt_but_content_and_repeat_still_queue() {
        let root = Temp::new();
        let mut sender = Sender::open(&root.0).unwrap();
        let original = enqueue(&mut sender, "pixel", "photo", "1");
        sender
            .conn
            .execute(
                "UPDATE jobs SET state='received' WHERE id=?1",
                [original.id],
            )
            .unwrap();
        let status = AssetStatus {
            asset_id: original.asset.id().unwrap(),
            receipt: ReceiptState::Received,
            processing: ProcessingState::Complete,
            processing_error: None,
            resources: vec![],
        };
        sender.observe_processing(original.id, &status, 1).unwrap();
        let mut asset = original.asset.clone();
        asset.revision = "2".into();
        asset.resources[0].filename = "renamed.jpg".into();
        let same = sender
            .enqueue("pixel", asset.clone(), original.sources.clone())
            .unwrap();
        assert_eq!(same.state, JobState::Received);
        assert_eq!(same.processing, Some(ProcessingState::Complete));
        assert_eq!(
            sender
                .source_states("pixel", &[("photo".into(), "2".into())])
                .unwrap()["photo"],
            "received"
        );
        assert_eq!(
            sender.library_source_states("pixel").unwrap()["photo"].tile_state,
            LibraryTileState::Saved
        );
        assert!(sender.claim("pixel", 10).unwrap().is_none());
        // The photo is counted once: the revision record reuses the receipt.
        assert_eq!(sender.summary("pixel").unwrap()["total"], 1);
        assert_eq!(
            sender.publication_time(same.id).unwrap(),
            sender.publication_time(original.id).unwrap()
        );
        asset.revision = "3".into();
        asset.resources[0].sha256 = digest(b"different");
        let changed = sender
            .enqueue(
                "pixel",
                asset.clone(),
                BTreeMap::from([(asset.resources[0].sha256.clone(), "new-export".into())]),
            )
            .unwrap();
        assert_eq!(changed.state, JobState::Queued);
        let mut repeat = original.asset.clone();
        repeat.revision = "4".into();
        repeat
            .metadata
            .insert("backupduck_rebackup_id".into(), "explicit".into());
        assert_eq!(
            sender
                .enqueue("pixel", repeat, original.sources.clone())
                .unwrap()
                .state,
            JobState::Queued
        );
        assert_eq!(
            sender
                .enqueue("other", same.asset, original.sources)
                .unwrap()
                .state,
            JobState::Queued
        );
    }

    #[test]
    fn metadata_revision_requires_the_complete_role_size_hash_set() {
        let root = Temp::new();
        let mut sender = Sender::open(&root.0).unwrap();
        let original = enqueue(&mut sender, "pixel", "photo", "1");
        sender
            .conn
            .execute(
                "UPDATE jobs SET state='received' WHERE id=?1",
                [original.id],
            )
            .unwrap();
        let mut changed = original.asset.clone();
        changed.revision = "size-change".into();
        changed.resources[0].size += 1;
        assert_eq!(
            sender
                .enqueue("pixel", changed, original.sources.clone())
                .unwrap()
                .state,
            JobState::Queued
        );
        let mut changed = original.asset.clone();
        changed.revision = "role-change".into();
        changed.kind = AssetKind::Video;
        changed.resources[0].role = ResourceRole::Video;
        assert_eq!(
            sender
                .enqueue("pixel", changed, original.sources.clone())
                .unwrap()
                .state,
            JobState::Queued
        );
        let mut motion = original.asset.clone();
        motion.revision = "additional-resource".into();
        motion.kind = AssetKind::Motion;
        let tail = Resource {
            role: ResourceRole::PairedVideo,
            filename: "paired.mov".into(),
            media_type: "video/quicktime".into(),
            size: 15,
            sha256: digest(b"paired"),
        };
        let mut sources = original.sources.clone();
        sources.insert(tail.sha256.clone(), "paired-export".into());
        motion.resources.push(tail);
        let full = sender
            .enqueue("pixel", motion.clone(), sources.clone())
            .unwrap();
        assert_eq!(full.state, JobState::Queued);
        sender
            .conn
            .execute("UPDATE jobs SET state='received' WHERE id=?1", [full.id])
            .unwrap();
        motion.revision = "same-complete-set".into();
        assert_eq!(
            sender
                .enqueue("pixel", motion.clone(), sources.clone())
                .unwrap()
                .state,
            JobState::Received
        );
        motion.revision = "changed-paired-video".into();
        sources.remove(&motion.resources[1].sha256);
        motion.resources[1].sha256 = digest(b"edited-paired");
        sources.insert(
            motion.resources[1].sha256.clone(),
            "new-paired-export".into(),
        );
        assert_eq!(
            sender.enqueue("pixel", motion, sources).unwrap().state,
            JobState::Queued
        );
    }

    #[test]
    fn revision_receives_future_processing_from_original_only() {
        let root = Temp::new();
        let mut sender = Sender::open(&root.0).unwrap();
        let original = enqueue(&mut sender, "pixel", "photo", "1");
        sender
            .conn
            .execute(
                "UPDATE jobs SET state='received' WHERE id=?1",
                [original.id],
            )
            .unwrap();
        let same = enqueue(&mut sender, "pixel", "photo", "2");
        assert_eq!(
            sender.processing_due("pixel", 0, 20).unwrap(),
            vec![(original.id, original.asset.id().unwrap())]
        );
        sender
            .observe_processing(
                original.id,
                &AssetStatus {
                    asset_id: original.asset.id().unwrap(),
                    receipt: ReceiptState::Received,
                    processing: ProcessingState::Complete,
                    processing_error: None,
                    resources: vec![],
                },
                1,
            )
            .unwrap();
        assert_eq!(
            sender.job(same.id).unwrap().processing,
            Some(ProcessingState::Complete)
        );
        assert_eq!(
            sender.publication_time(same.id).unwrap(),
            sender.publication_time(original.id).unwrap()
        );
    }

    #[test]
    fn receipt_publication_failure_and_unknown_remain_distinct() {
        let root = Temp::new();
        let mut sender = Sender::open(&root.0).unwrap();
        let job = enqueue(&mut sender, "pixel", "photo", "1");
        for (state, expected) in [
            ("queued", LibraryTileState::Sending),
            ("running", LibraryTileState::Sending),
            ("waiting", LibraryTileState::Sending),
            ("paused", LibraryTileState::Sending),
            ("failed", LibraryTileState::NeedsYou),
            ("received", LibraryTileState::Unknown),
        ] {
            sender
                .conn
                .execute(
                    "UPDATE jobs SET state=?1 WHERE id=?2",
                    params![state, job.id],
                )
                .unwrap();
            let snapshot = sender.library_source_states("pixel").unwrap();
            assert_eq!(snapshot["photo"].tile_state, expected);
            assert_eq!(snapshot["photo"].received, Some(state == "received"));
            assert_eq!(snapshot["photo"].processing, None);
        }
        let mut status = AssetStatus {
            asset_id: job.asset.id().unwrap(),
            receipt: ReceiptState::Received,
            processing: ProcessingState::NotRequested,
            processing_error: None,
            resources: vec![ResourceStatus {
                sha256: job.asset.resources[0].sha256.clone(),
                offset: 9,
                complete: true,
            }],
        };
        for (processing, expected) in [
            (ProcessingState::NotRequested, LibraryTileState::Unknown),
            (ProcessingState::Pending, LibraryTileState::Saving),
            (ProcessingState::Failed, LibraryTileState::NeedsYou),
            (ProcessingState::Complete, LibraryTileState::Saved),
        ] {
            status.processing = processing.clone();
            status.processing_error =
                (processing == ProcessingState::Failed).then(|| "unsupported".into());
            sender.observe_processing(job.id, &status, 100).unwrap();
            let snapshot = sender.library_source_states("pixel").unwrap();
            let item = &snapshot["photo"];
            assert_eq!(item.tile_state, expected);
            assert_eq!(item.received, Some(true));
            assert_eq!(item.processing, Some(processing));
            assert_eq!(item.processing_error, status.processing_error);
            assert_eq!(sender.received_sources("pixel").unwrap(), vec!["photo"]);
        }
        assert!(sender
            .library_source_states("other-pixel")
            .unwrap()
            .is_empty());
        // Pin a different timestamp so this regression cannot pass merely
        // because two observations happened within the same millisecond.
        sender
            .conn
            .execute(
                "UPDATE publication_times SET observed_ms=123 WHERE job_id=?1",
                [job.id],
            )
            .unwrap();
        sender.observe_processing(job.id, &status, 200).unwrap();
        assert_eq!(sender.publication_time(job.id).unwrap(), Some(123));
        assert!(!sender
            .library_source_states("pixel")
            .unwrap()
            .contains_key("unknown-photo"));
        let mut edit = job.asset.clone();
        edit.revision = "2".into();
        edit.resources[0].sha256 = digest(b"actual-edit");
        let edited = sender
            .enqueue(
                "pixel",
                edit.clone(),
                BTreeMap::from([(edit.resources[0].sha256.clone(), "edited-export".into())]),
            )
            .unwrap();
        let snapshot = sender.library_source_states("pixel").unwrap();
        assert_eq!(snapshot["photo"].job_id, Some(edited.id));
        assert_eq!(snapshot["photo"].revision.as_deref(), Some("2"));
        assert_eq!(snapshot["photo"].tile_state, LibraryTileState::Sending);
        assert_eq!(snapshot["photo"].processing, None);
        assert_eq!(snapshot["photo"].received, Some(false));
    }

    #[test]
    fn whole_library_is_not_limited_to_the_visible_window() {
        let root = Temp::new();
        let mut sender = Sender::open(&root.0).unwrap();
        for i in 0..425 {
            enqueue(&mut sender, "pixel", &format!("photo-{i}"), "1");
        }
        enqueue(&mut sender, "other", "foreign-photo", "1");
        let states = sender.library_source_states("pixel").unwrap();
        assert_eq!(states.len(), 425);
        assert!(states
            .values()
            .all(|s| s.tile_state == LibraryTileState::Sending));
        assert_eq!(sender.library_source_states("other").unwrap().len(), 1);
    }
}
