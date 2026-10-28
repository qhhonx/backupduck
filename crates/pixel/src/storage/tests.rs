use super::*;
use backupduck_core::*;
use backupduck_store::{retention::GalleryCopy, Receiver};

static SEQ: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
struct Temp(std::path::PathBuf);
impl Temp {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "backupduck-storage-parts-{}-{}-{}",
            std::process::id(),
            SEQ.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
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
fn asset(source: &str, parts: &[&[u8]]) -> Asset {
    Asset {
        version: PROTOCOL_VERSION,
        source_id: source.into(),
        revision: "1".into(),
        kind: if parts.len() == 2 {
            AssetKind::Motion
        } else {
            AssetKind::Photo
        },
        metadata: BTreeMap::new(),
        resources: parts
            .iter()
            .enumerate()
            .map(|(i, bytes)| Resource {
                role: if i == 0 {
                    ResourceRole::Photo
                } else {
                    ResourceRole::PairedVideo
                },
                filename: if i == 0 { "test.jpg" } else { "test.mov" }.into(),
                media_type: if i == 0 {
                    "image/jpeg"
                } else {
                    "video/quicktime"
                }
                .into(),
                size: bytes.len() as u64,
                sha256: digest(bytes),
            })
            .collect(),
    }
}
fn receive(receiver: &mut Receiver, source: &str, parts: &[&[u8]]) -> String {
    let a = asset(source, parts);
    let id = receiver.register(a.clone()).unwrap().asset_id;
    for (r, bytes) in a.resources.iter().zip(parts) {
        receiver
            .append(&id, &r.sha256, 0, bytes, &digest(bytes))
            .unwrap();
    }
    receiver.commit(&id).unwrap();
    id
}
fn copy(bytes: &[u8], locator: &str) -> GalleryCopy {
    GalleryCopy {
        locator: locator.into(),
        sha256: digest(bytes),
        size: bytes.len() as u64,
        display_name: None,
    }
}

#[test]
fn physical_copies_and_reclaim_estimate_respect_shared_and_pending_resources() {
    let root = Temp::new();
    let mut receiver = Receiver::open(root.0.join("store"), 10000).unwrap();
    let motion = receive(&mut receiver, "motion", &[b"photo", b"movie!!"]);
    let delivery = copy(b"converted", "content://motion");
    receiver.record_gallery_copy(&motion, &delivery).unwrap();
    let shared = receive(&mut receiver, "shared", &[b"photo"]);
    let plain = receive(&mut receiver, "plain", &[b"ordinary"]);
    receiver
        .set_processing(&plain, ProcessingState::Pending)
        .unwrap();
    receiver
        .set_processing(&plain, ProcessingState::Complete)
        .unwrap();
    let failed = receive(&mut receiver, "failed", &[b"failed"]);
    receiver
        .set_processing(&failed, ProcessingState::Pending)
        .unwrap();
    receiver
        .set_processing_result(&failed, ProcessingState::Failed, Some("unsupported"))
        .unwrap();
    let uploading = receiver
        .register(asset("uploading", &[b"abcdef"]))
        .unwrap()
        .asset_id;
    receiver
        .append(&uploading, &digest(b"abcdef"), 0, b"ab", &digest(b"ab"))
        .unwrap();
    receiver
        .register(asset("unwritten", &[b"unwritten"]))
        .unwrap();
    // Query while the receiver holds the writer lock: no reopen/reconciliation.
    let before = fs::read(root.0.join("store/receiver.sqlite3")).unwrap();
    let parts = breakdown(&root.0).unwrap();
    assert_eq!(
        (parts.own_copy_bytes, parts.ready_bytes, parts.partial_bytes),
        (28, 26, 2)
    );
    assert_eq!(
        (
            parts.converted_original_bytes,
            parts.pending_bytes,
            parts.other_original_bytes
        ),
        (Some(7), Some(13), Some(8))
    );
    assert_eq!(parts.reclaimable_bytes, Some(7));
    assert!(parts.free_bytes.is_some_and(|n| n > 0));
    assert_eq!(
        fs::read(root.0.join("store/receiver.sqlite3")).unwrap(),
        before
    );
    // One received-but-unpublished reference blocks freeing the shared blob.
    receiver
        .record_gallery_copy(&shared, &copy(b"photo", "content://shared"))
        .unwrap();
    let parts = breakdown(&root.0).unwrap();
    assert_eq!(parts.converted_original_bytes, Some(12));
    assert_eq!(parts.pending_bytes, Some(8));
    assert_eq!(parts.reclaimable_bytes, Some(12));
    receiver
        .record_gallery_copy(&plain, &copy(b"ordinary", "content://plain"))
        .unwrap();
    assert_eq!(breakdown(&root.0).unwrap().reclaimable_bytes, Some(20));
    receiver
        .release_gallery_copy(&motion, &delivery, true)
        .unwrap();
    let parts = breakdown(&root.0).unwrap();
    assert_eq!(parts.own_copy_bytes, 21);
    assert_eq!(parts.converted_original_bytes, Some(0));
    assert_eq!(parts.reclaimable_bytes, Some(13));
}

#[test]
fn missing_catalog_is_unknown_and_reading_never_removes_unreferenced_files() {
    let root = Temp::new();
    let empty = breakdown(&root.0).unwrap();
    assert_eq!(empty.own_copy_bytes, 0);
    assert_eq!(empty.free_bytes, None);
    assert!(!root.0.exists());
    fs::create_dir_all(root.0.join("store/blobs")).unwrap();
    fs::create_dir_all(root.0.join("store/partial")).unwrap();
    fs::write(root.0.join("store/blobs/a"), b"ready").unwrap();
    fs::write(root.0.join("store/partial/a"), b"ready").unwrap();
    fs::write(root.0.join("store/partial/b"), b"pending").unwrap();
    #[cfg(unix)]
    std::os::unix::fs::symlink(
        root.0.join("store/blobs/a"),
        root.0.join("store/blobs/link"),
    )
    .unwrap();
    let parts = breakdown(&root.0).unwrap();
    assert_eq!(
        (parts.own_copy_bytes, parts.ready_bytes, parts.partial_bytes),
        (12, 5, 7)
    );
    assert_eq!(parts.converted_original_bytes, None);
    assert_eq!(parts.pending_bytes, None);
    assert_eq!(parts.reclaimable_bytes, None);
    assert!(root.0.join("store/partial/a").exists());
    assert!(!root.0.join("store/receiver.sqlite3").exists());
}

#[test]
fn partials_and_missing_ready_files_count_actual_lengths_not_declared_sizes() {
    let root = Temp::new();
    let mut receiver = Receiver::open(root.0.join("store"), 10000).unwrap();
    let id = receive(&mut receiver, "missing", &[b"missing"]);
    receiver
        .record_gallery_copy(&id, &copy(b"missing", "content://missing"))
        .unwrap();
    fs::remove_file(root.0.join("store/blobs").join(digest(b"missing"))).unwrap();
    fs::write(root.0.join("store/partial/orphan"), b"123").unwrap();
    let parts = breakdown(&root.0).unwrap();
    assert_eq!(parts.own_copy_bytes, 3);
    assert_eq!(parts.pending_bytes, Some(3));
    assert_eq!(parts.other_original_bytes, Some(0));
    assert_eq!(parts.reclaimable_bytes, Some(0));
    assert!(root.0.join("store/partial/orphan").exists());
}
