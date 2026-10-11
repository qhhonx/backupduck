use backupduck_core::*;
use backupduck_store::Receiver;
use std::{
    collections::BTreeMap,
    sync::atomic::{AtomicU64, Ordering},
    time::Duration,
};

static SEQUENCE: AtomicU64 = AtomicU64::new(0);
#[test]
fn durable_chunks_emit_progress_and_receipt_requires_commit() {
    let root = std::env::temp_dir().join(format!(
        "backupduck-progress-{}-{}",
        std::process::id(),
        SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    let bytes = vec![42; 1024 * 1024];
    let hash = digest(&bytes);
    let asset = Asset {
        version: PROTOCOL_VERSION,
        source_id: "generated-progress".into(),
        revision: "1".into(),
        kind: AssetKind::Photo,
        metadata: BTreeMap::new(),
        resources: vec![Resource {
            role: ResourceRole::Photo,
            filename: "generated.jpg".into(),
            media_type: "image/jpeg".into(),
            size: bytes.len() as u64,
            sha256: hash.clone(),
        }],
    };
    let mut receiver = Receiver::open(&root, 8 * 1024 * 1024).unwrap();
    let state = receiver.register(asset).unwrap();
    let id = state.asset_id;
    let feed = receiver.progress_feed();
    let mut previous = feed.wait(0, Duration::ZERO);
    assert_eq!(previous.items[0].confirmed_bytes, 0);
    let waiting = feed.clone();
    let revision = previous.revision;
    let waiter = std::thread::spawn(move || waiting.wait(revision, Duration::from_secs(1)));
    for offset in (0..bytes.len()).step_by(256 * 1024) {
        let chunk = &bytes[offset..offset + 256 * 1024];
        receiver
            .append(&id, &hash, offset as u64, chunk, &digest(chunk))
            .unwrap();
        let next = feed.wait(previous.revision, Duration::ZERO);
        assert!(next.revision > previous.revision);
        assert_eq!(next.items[0].confirmed_bytes, (offset + chunk.len()) as u64);
        assert_eq!(next.items[0].total_bytes, bytes.len() as u64);
        assert!(
            !next.items[0].received,
            "Resource bytes alone do not establish an asset receipt"
        );
        previous = next;
    }
    assert!(
        waiter.join().unwrap().items[0].confirmed_bytes > 0,
        "Writer must wake a waiting consumer without taking its receiver lock"
    );
    let revision = previous.revision;
    assert!(receiver
        .append(&id, &hash, 0, b"wrong", &digest(b"wrong"))
        .is_err());
    assert_eq!(feed.wait(revision, Duration::ZERO).revision, revision);
    receiver.commit(&id).unwrap();
    let received = feed.wait(revision, Duration::ZERO);
    assert!(received.items[0].received);
    assert_eq!(received.items[0].confirmed_bytes, bytes.len() as u64);
    receiver
        .set_processing_result(&id, ProcessingState::Pending, None)
        .unwrap();
    let pending = feed.wait(received.revision, Duration::ZERO);
    assert_eq!(pending.items[0].processing, ProcessingState::Pending);
    receiver
        .set_processing_result(&id, ProcessingState::Failed, Some("unsupported"))
        .unwrap();
    let failed = feed.wait(pending.revision, Duration::ZERO);
    assert_eq!(failed.items[0].processing, ProcessingState::Failed);
    assert_eq!(
        failed.items[0].processing_error.as_deref(),
        Some("unsupported")
    );
    receiver.retry_processing_item(Some(&id)).unwrap();
    let retried = feed.wait(failed.revision, Duration::ZERO);
    assert_eq!(retried.items[0].processing, ProcessingState::Pending);
    receiver
        .record_gallery_copy(
            &id,
            &backupduck_store::retention::GalleryCopy {
                locator: "content://generated/1".into(),
                sha256: hash.clone(),
                size: bytes.len() as u64,
                display_name: None,
            },
        )
        .unwrap();
    let saved = feed.wait(retried.revision, Duration::ZERO);
    assert_eq!(saved.items[0].processing, ProcessingState::Complete);
    drop(receiver);
    std::fs::remove_dir_all(root).unwrap();
}
