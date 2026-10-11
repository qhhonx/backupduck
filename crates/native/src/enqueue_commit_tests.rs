use super::*;

#[test]
fn committed_job_remains_acknowledged_when_activity_storage_fails() {
    struct Temp(PathBuf);
    impl Drop for Temp {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
    let root = Temp(std::env::temp_dir().join(format!(
            "backupduck-enqueue-commit-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        )));
    std::fs::create_dir_all(&root.0).unwrap();
    let sender_root = root.0.join("sender");
    let host = SenderHost::open(&sender_root).unwrap();
    let photo = root.0.join("original.jpg");
    std::fs::write(&photo, b"synthetic verified original bytes").unwrap();
    let (asset, paths) = manifest(
        "synthetic-source".into(),
        "1".into(),
        AssetKind::Photo,
        BTreeMap::new(),
        vec![ExportedResource {
            role: ResourceRole::Photo,
            filename: "original.jpg".into(),
            media_type: "image/jpeg".into(),
            path: photo.clone(),
        }],
    )
    .unwrap();
    // Inject a real SQLite failure after queue commitment, not a mocked result.
    let log = rusqlite::Connection::open(sender_root.join("maintenance.sqlite3")).unwrap();
    log.execute_batch("DROP TABLE events").unwrap();
    let accepted = host
        .enqueue("synthetic-receiver", asset.clone(), paths.clone())
        .unwrap();
    assert!(host
        .maintenance
        .lock()
        .unwrap()
        .log("transfer_queued", Some(accepted.id), None)
        .is_err());
    assert_eq!(
        host.enqueue("synthetic-receiver", asset, paths).unwrap().id,
        accepted.id
    );
    drop(host);
    let reopened = SenderHost::open(&sender_root).unwrap();
    let rows = reopened.list(0).unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].id, accepted.id);
    assert_eq!(rows[0].state, backupduck_sender::JobState::Queued);
    assert_eq!(
        std::fs::read(photo).unwrap(),
        b"synthetic verified original bytes"
    );
}
