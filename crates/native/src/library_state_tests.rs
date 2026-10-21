use super::*;
use backupduck_sender::LibraryTileState;

#[test]
fn whole_library_preparations_preserve_unknown_receipt_and_handoff_to_job_facts() {
    struct Temp(PathBuf);
    impl Drop for Temp {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    let path = std::env::temp_dir().join(format!(
        "backupduck-library-host-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let root = Temp(path);
    let host = SenderHost::open(&root.0).unwrap();
    let mut preparation = maintenance::PreparationRegistration {
        receiver_id: "pixel".into(),
        request_id: "request".into(),
        source: "photo".into(),
        revision: Some("1".into()),
        repeat: false,
        captured_at_ms: None,
        error: None,
    };
    {
        let m = host.maintenance.lock().unwrap();
        m.register_preparation(&preparation).unwrap();
        m.source_result_with_error("pixel", "request", false, Some("source_changed"))
            .unwrap();
    }
    let states = host.library_source_states("pixel").unwrap();
    assert_eq!(states["photo"].tile_state, LibraryTileState::NeedsYou);
    assert_eq!(states["photo"].received, None);
    assert!(states["photo"].preparing);
    assert!(host.library_source_states("other").unwrap().is_empty());
    host.maintenance
        .lock()
        .unwrap()
        .retry_source("pixel", "request")
        .unwrap();
    assert_eq!(
        host.library_source_states("pixel").unwrap()["photo"].tile_state,
        LibraryTileState::Sending
    );
    let original = root.0.join("test.jpg");
    fs::write(&original, b"synthetic").unwrap();
    let (asset, sources) = manifest(
        "photo".into(),
        "1".into(),
        AssetKind::Photo,
        BTreeMap::new(),
        vec![ExportedResource {
            role: ResourceRole::Photo,
            filename: "test.jpg".into(),
            media_type: "image/jpeg".into(),
            path: original,
        }],
    )
    .unwrap();
    let job = host
        .enqueue_prepared("pixel", asset, sources, Some("request"))
        .unwrap();
    // Lost preparation acknowledgement leaves a pending row, but the durable
    // job_preparations link already establishes that transfer owns the intent.
    let state = &host.library_source_states("pixel").unwrap()["photo"];
    assert_eq!(state.job_id, Some(job.id));
    assert!(!state.preparing);
    assert_eq!(state.received, Some(false));
    {
        let mut sender = host.sender.lock().unwrap();
        let running = sender.claim("pixel", 0).unwrap().unwrap();
        sender
            .acknowledge(
                &running.attempt(),
                &AssetStatus {
                    asset_id: running.asset.id().unwrap(),
                    receipt: ReceiptState::Received,
                    processing: ProcessingState::Pending,
                    processing_error: None,
                    resources: vec![ResourceStatus {
                        sha256: running.asset.resources[0].sha256.clone(),
                        offset: 9,
                        complete: true,
                    }],
                },
            )
            .unwrap();
    }
    assert_eq!(
        host.library_source_states("pixel").unwrap()["photo"].tile_state,
        LibraryTileState::Saving
    );
    // A new revision awaiting export must not inherit the older job's receipt.
    preparation.request_id = "request-2".into();
    preparation.revision = Some("2".into());
    preparation.error = Some("local_free_space".into());
    host.maintenance
        .lock()
        .unwrap()
        .register_preparation(&preparation)
        .unwrap();
    let states = host.library_source_states("pixel").unwrap();
    assert_eq!(states["photo"].tile_state, LibraryTileState::Sending);
    assert_eq!(states["photo"].received, None);
    assert_eq!(states["photo"].revision.as_deref(), Some("2"));
}

#[test]
fn storage_breakdown_command_works_before_receiver_start_without_creating_a_store() {
    let root = std::env::temp_dir().join(format!(
        "backupduck-storage-bridge-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let command: Command =
        serde_json::from_value(json!({"op":"receiver_storage_breakdown","root":root})).unwrap();
    let value = dispatch(command).unwrap();
    assert_eq!(value["own_copy_bytes"], 0);
    assert_eq!(value["reclaimable_bytes"], 0);
    assert!(value["free_bytes"].is_null());
    assert!(!root.exists());
    let _: Command =
        serde_json::from_value(json!({"op":"library_source_states","receiver_id":"pixel"}))
            .unwrap();
}
