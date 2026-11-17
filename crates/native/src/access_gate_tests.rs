use super::*;
use std::sync::atomic::{AtomicU64, Ordering};
static SEQUENCE: AtomicU64 = AtomicU64::new(0);
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        Self(std::env::temp_dir().join(format!(
            "backupduck-access-{}-{}",
            std::process::id(),
            SEQUENCE.fetch_add(1, Ordering::Relaxed)
        )))
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn access_hold_preserves_pending_preparation_and_user_intent_across_restart() {
    let root = Temp::new();
    let host = SenderHost::open(&root.0).unwrap();
    host.maintenance
        .lock()
        .unwrap()
        .register_preparation(&maintenance::PreparationRegistration {
            receiver_id: "pixel".into(),
            request_id: "request".into(),
            source: "photo".into(),
            revision: Some("1".into()),
            repeat: false,
            captured_at_ms: Some(1),
            error: None,
        })
        .unwrap();
    assert_eq!(
        host.pending_sources("pixel").unwrap()["preparations"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    host.set_access(true, Some(0)).unwrap();
    let state = host.execution_status().unwrap();
    assert_eq!(state["paused"], false);
    assert_eq!(state["access_allowed"], true);
    assert_eq!(state["access_valid_until"], 0);
    assert_eq!(state["execution_blocked"], true);
    assert_eq!(host.pending_sources("pixel").unwrap()["count"], 1);
    assert_eq!(
        host.pending_sources("pixel").unwrap()["preparations"],
        json!([])
    );
    assert_eq!(
        host.source_preparations(Some("pixel"), true, 5).unwrap(),
        json!([])
    );
    assert_eq!(
        host.source_preparations(Some("pixel"), false, 5)
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        1
    );
    drop(host);
    let host = SenderHost::open(&root.0).unwrap();
    assert_eq!(host.execution_status().unwrap(), state);
    host.pause(true).unwrap();
    host.set_access(true, None).unwrap();
    assert_eq!(host.execution_status().unwrap()["execution_blocked"], true);
    assert_eq!(
        host.pending_sources("pixel").unwrap()["preparations"],
        json!([])
    );
    host.pause(false).unwrap();
    assert_eq!(
        host.pending_sources("pixel").unwrap()["preparations"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
}

#[test]
fn native_access_hold_preserves_late_receipt_and_blocks_subsequent_requests() {
    let root = Temp::new();
    let host = SenderHost::open(&root.0).unwrap();
    let file = root.0.join("photo.jpg");
    fs::write(&file, b"synthetic original").unwrap();
    let (asset, sources) = manifest(
        "photo".into(),
        "1".into(),
        AssetKind::Photo,
        BTreeMap::new(),
        vec![ExportedResource {
            role: ResourceRole::Photo,
            filename: "photo.jpg".into(),
            media_type: "image/jpeg".into(),
            path: file,
        }],
    )
    .unwrap();
    host.set_access(false, None).unwrap();
    assert!(matches!(
        host.enqueue_prepared_with_gate("pixel", asset.clone(), sources.clone(), None, true),
        Err(Error::Cancelled)
    ));
    assert!(host.list(0).unwrap().is_empty());
    host.set_access(true, None).unwrap();
    let job = host.enqueue("pixel", asset, sources).unwrap();
    let request = host.prepare_native("pixel").unwrap().unwrap();
    host.set_access(false, None).unwrap();
    assert!(host.bind_native(&request.attempt, "before-hold").is_err());
    host.abandon_native(&request.attempt).unwrap();
    assert!(host.prepare_native("pixel").unwrap().is_none());
    host.set_access(true, None).unwrap();
    let request = host.prepare_native("pixel").unwrap().unwrap();
    host.bind_native(&request.attempt, "late-receipt").unwrap();
    host.set_access(false, None).unwrap();
    let status = AssetStatus {
        asset_id: job.asset.id().unwrap(),
        receipt: ReceiptState::Received,
        processing: ProcessingState::Pending,
        processing_error: None,
        resources: job
            .asset
            .resources
            .iter()
            .map(|r| ResourceStatus {
                sha256: r.sha256.clone(),
                offset: r.size,
                complete: true,
            })
            .collect(),
    };
    let completed = host
        .finish_native(
            &request.attempt,
            "late-receipt",
            200,
            &serde_json::to_string(&status).unwrap(),
            None,
            false,
        )
        .unwrap();
    assert_eq!(completed.state, backupduck_sender::JobState::Received);
    assert_eq!(completed.confirmed_bytes, 18);
    assert!(host.prepare_native("pixel").unwrap().is_none());
    assert_eq!(host.execution_status().unwrap()["paused"], false);
}

#[test]
fn access_command_uses_optional_unix_seconds_and_rejects_invalid_deadline() {
    let command: Command = serde_json::from_value(
        json!({"op":"set_sender_access", "allowed":true, "valid_until":1234}),
    )
    .unwrap();
    assert!(matches!(
        command,
        Command::SetSenderAccess {
            allowed: true,
            valid_until: Some(1234)
        }
    ));
    let unrestricted: Command =
        serde_json::from_value(json!({"op":"set_sender_access", "allowed":true})).unwrap();
    assert!(matches!(
        unrestricted,
        Command::SetSenderAccess {
            allowed: true,
            valid_until: None
        }
    ));
    let root = Temp::new();
    let host = SenderHost::open(&root.0).unwrap();
    host.set_access(false, Some(1234)).unwrap();
    assert!(host.set_access(true, Some(-1)).is_err());
    let status = host.execution_status().unwrap();
    assert_eq!(status["access_allowed"], false);
    assert_eq!(status["access_valid_until"], 1234);
}
