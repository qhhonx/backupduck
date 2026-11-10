use super::*;

static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
struct Fixture {
    root: PathBuf,
    host: SenderHost,
    index: Index,
}
impl Fixture {
    fn new() -> Self {
        let root = std::env::temp_dir().join(format!(
            "backupduck-folder-repeat-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(root.join("originals")).unwrap();
        fs::write(root.join("originals/a.jpg"), b"synthetic photo").unwrap();
        let host = SenderHost::open(&root.join("sender")).unwrap();
        let mut index = Index::open(&root.join("folders.sqlite3")).unwrap();
        index.begin("folder", &root.join("originals"), 1).unwrap();
        while index.step(1, 100).unwrap().scanning {}
        Self { root, host, index }
    }
    fn selections(&self) -> Vec<(String, String)> {
        let entry = self.index.entry("folder", "a.jpg").unwrap();
        vec![(entry.relative, entry.revision)]
    }
    fn request(&mut self, repeat: bool, receiver: &str) -> Result<Value> {
        let source = self.index.entry("folder", "a.jpg").unwrap().source_id;
        let selections = self.selections();
        call_with_index(
            &self.host,
            &mut self.index,
            Command::RequestSelected {
                source: "folder".into(),
                receiver: receiver.into(),
                selections,
                repeat_sources: if repeat {
                    BTreeSet::from([source])
                } else {
                    BTreeSet::new()
                },
            },
        )
    }
    fn prepare(&mut self) -> Result<Value> {
        let entry = self.index.entry("folder", "a.jpg").unwrap();
        call_with_index(
            &self.host,
            &mut self.index,
            Command::Prepare {
                source: "folder".into(),
                name: "Pictures".into(),
                root: self.root.join("originals"),
                relative: entry.relative,
                source_id: entry.source_id,
                revision: entry.revision,
                receiver: "pixel".into(),
                metadata: BTreeMap::new(),
                paired: None,
            },
        )
    }
    fn receive(&self, processing: ProcessingState) -> i64 {
        let mut queue = self.host.sender.lock().unwrap();
        let running = queue.claim("pixel", 0).unwrap().unwrap();
        queue
            .acknowledge(
                &running.attempt(),
                &AssetStatus {
                    asset_id: running.asset.id().unwrap(),
                    receipt: ReceiptState::Received,
                    processing,
                    processing_error: None,
                    resources: running
                        .asset
                        .resources
                        .iter()
                        .map(|r| ResourceStatus {
                            sha256: r.sha256.clone(),
                            offset: r.size,
                            complete: true,
                        })
                        .collect(),
                },
            )
            .unwrap();
        running.id
    }
    fn repeats(&self, receiver: &str) -> BTreeMap<String, (String, i64)> {
        selected_repeat_sources(
            &self.index,
            &self.host.sender.lock().unwrap(),
            "folder",
            receiver,
            &self.selections(),
        )
        .unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

#[test]
fn explicit_folder_repeat_preserves_receipt_and_replays_without_duplicate_jobs() {
    let mut f = Fixture::new();
    f.request(false, "pixel").unwrap();
    f.prepare().unwrap();
    let original = f.receive(ProcessingState::Complete);
    assert_eq!(f.repeats("pixel").len(), 1);
    f.request(false, "pixel").unwrap();
    assert!(!f.index.selected_pending("folder", "pixel").unwrap());
    assert_eq!(f.host.list(0).unwrap().len(), 1);

    f.request(true, "pixel").unwrap();
    assert!(f.index.selected_pending("folder", "pixel").unwrap());
    assert_eq!(
        f.index
            .selected_candidates("folder", "pixel", 20000)
            .unwrap()
            .len(),
        1
    );
    assert!(f.repeats("pixel").is_empty());
    // Repeated clicks, an ordinary selection, and restart preserve one intent.
    f.request(true, "pixel").unwrap();
    f.request(false, "pixel").unwrap();
    f.index = Index::open(&f.root.join("folders.sqlite3")).unwrap();
    f.prepare().unwrap();
    let rows = f.host.list(0).unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0].state, backupduck_sender::JobState::Received);
    assert_eq!(rows[0].processing, Some(ProcessingState::Complete));
    assert_eq!(rows[0].id, original);
    assert_eq!(rows[1].state, backupduck_sender::JobState::Queued);
    assert!(rows[1]
        .asset
        .metadata
        .contains_key("backupduck_rebackup_id"));
    assert_eq!(rows[0].asset.source_id, rows[1].asset.source_id);
    assert_eq!(rows[0].asset.revision, rows[1].asset.revision);
    assert_ne!(rows[0].asset.id().unwrap(), rows[1].asset.id().unwrap());
    f.request(true, "pixel").unwrap();
    f.prepare().unwrap();
    assert_eq!(f.host.list(0).unwrap().len(), 2);

    // Simulate an interrupted index acknowledgement after the queue committed.
    let selection = f.selections();
    f.index
        .mark("folder", "a.jpg", "pixel", &selection[0].1, original)
        .unwrap();
    f.index
        .request_selected_with_repeats(
            "folder",
            "pixel",
            &selection,
            &BTreeMap::from([("a.jpg".into(), original)]),
        )
        .unwrap();
    f.prepare().unwrap();
    assert_eq!(f.host.list(0).unwrap().len(), 2);
    assert!(!f.index.selected_pending("folder", "pixel").unwrap());
    assert_eq!(
        f.index.job_id("folder", "a.jpg", "pixel").unwrap(),
        Some(rows[1].id)
    );
}

#[test]
fn folder_repeat_requires_saved_publication_matching_revision_and_receiver() {
    let mut f = Fixture::new();
    f.request(false, "pixel").unwrap();
    f.prepare().unwrap();
    f.receive(ProcessingState::Pending);
    assert!(f.repeats("pixel").is_empty());
    f.request(true, "pixel").unwrap();
    assert!(!f.index.selected_pending("folder", "pixel").unwrap());
    assert!(f.repeats("other").is_empty());
    let entry = f.index.entry("folder", "a.jpg").unwrap();
    assert!(selected_repeat_sources(
        &f.index,
        &f.host.sender.lock().unwrap(),
        "folder",
        "pixel",
        &[(entry.relative.clone(), "stale".into())]
    )
    .is_err());
    assert!(f
        .index
        .request_selected_with_repeats(
            "folder",
            "other",
            &f.selections(),
            &BTreeMap::from([("a.jpg".into(), 1)])
        )
        .is_err());
    assert!(!f.index.selected_pending("folder", "other").unwrap());
    assert_eq!(f.host.list(0).unwrap().len(), 1);
}
