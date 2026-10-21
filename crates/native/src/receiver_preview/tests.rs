use super::*;
use std::cell::Cell;

struct Fixture {
    base: PathBuf,
    root: PathBuf,
    cache: PathBuf,
    receiver: Receiver,
}
impl Fixture {
    fn new() -> Self {
        let base = std::env::temp_dir().join(format!(
            "backupduck-preview-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let root = base.join("receiver");
        let cache = base.join("cache");
        fs::create_dir_all(&cache).unwrap();
        let receiver = Receiver::open(root.join("store"), 1 << 20).unwrap();
        let mut m = maintenance::Maintenance::open(&root).unwrap();
        let mut settings = m.settings.clone();
        settings.min_free_bytes = 0;
        m.save(settings).unwrap();
        Self {
            base,
            root,
            cache,
            receiver,
        }
    }
    fn register(&mut self, source: &str, mime: &str, received: bool) -> (String, PathBuf) {
        let bytes = format!("synthetic original {source}");
        let resource = Resource {
            role: if mime.starts_with("video/") {
                ResourceRole::Video
            } else {
                ResourceRole::Photo
            },
            filename: "original".into(),
            media_type: mime.into(),
            size: bytes.len() as u64,
            sha256: digest(bytes.as_bytes()),
        };
        let asset = Asset {
            version: PROTOCOL_VERSION,
            source_id: source.into(),
            revision: "1".into(),
            kind: if mime.starts_with("video/") {
                AssetKind::Video
            } else {
                AssetKind::Photo
            },
            metadata: BTreeMap::new(),
            resources: vec![resource.clone()],
        };
        let id = self.receiver.register(asset).unwrap().asset_id;
        if received {
            self.receiver
                .append(&id, &resource.sha256, 0, bytes.as_bytes(), &resource.sha256)
                .unwrap();
            self.receiver.commit(&id).unwrap();
        }
        (id, self.root.join("store/blobs").join(resource.sha256))
    }
    fn command(&self, id: &str) -> Command {
        serde_json::from_value(json!({"op":"receiver_preview", "root":self.root,
            "cache_dir":self.cache, "id":id}))
        .unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.base);
    }
}

#[test]
fn miss_generates_once_hit_and_os_purge_regenerate_without_touching_original() {
    let mut f = Fixture::new();
    let (id, original) = f.register("photo", "image/jpeg", true);
    let before = fs::read(&original).unwrap();
    let timestamp = fs::metadata(&original).unwrap().modified().unwrap();
    let calls = Cell::new(0);
    let decoder = |path: &Path| {
        assert_eq!(path, original.canonicalize().unwrap());
        calls.set(calls.get() + 1);
        Some(b"synthetic JPEG supplied by test decoder".to_vec())
    };
    let first = preview_with(&f.root, &f.cache, &id, decoder).unwrap();
    assert_eq!(first["cache_hit"], false);
    assert_eq!(first["max_edge"], 512);
    let path = PathBuf::from(first["path"].as_str().unwrap());
    assert!(path.starts_with(f.cache.canonicalize().unwrap()));
    // Exercise the real JSON command dispatch for the hit, including with the
    // receiver still open: no second writer/reconciliation is needed.
    let second = dispatch(f.command(&id)).unwrap();
    assert_eq!(second["cache_hit"], true);
    assert_eq!(first["path"], second["path"]);
    assert_eq!(calls.get(), 1);
    fs::remove_file(path).unwrap();
    assert_eq!(
        preview_with(&f.root, &f.cache, &id, decoder).unwrap()["cache_hit"],
        false
    );
    assert_eq!(calls.get(), 2);
    assert_eq!(fs::read(&original).unwrap(), before);
    assert_eq!(
        fs::metadata(&original).unwrap().modified().unwrap(),
        timestamp
    );
    assert_eq!(
        f.receiver.status(&id).unwrap().receipt,
        ReceiptState::Received
    );
}

#[test]
fn unsupported_decode_failure_missing_original_and_pending_are_unavailable() {
    let mut f = Fixture::new();
    for mime in ["image/jpeg", "image/png", "image/heic"] {
        let (id, _) = f.register(mime, mime, true);
        let value = preview_with(&f.root, &f.cache, &id, |_| None).unwrap();
        assert_eq!(value["status"], "unavailable");
        assert_eq!(value["reason"], "decode_unavailable");
        assert!(value["path"].is_null());
    }
    let (id, _) = f.register("video", "video/mp4", true);
    assert_eq!(
        preview_with(&f.root, &f.cache, &id, |_| panic!("unsupported decoder")).unwrap()["reason"],
        "unsupported_format"
    );
    let (id, original) = f.register("missing-original", "image/jpeg", true);
    fs::remove_file(original).unwrap();
    assert_eq!(
        preview_with(&f.root, &f.cache, &id, |_| panic!("missing decoder")).unwrap()["reason"],
        "original_unavailable"
    );
    let (id, _) = f.register("pending", "image/jpeg", false);
    assert_eq!(dispatch(f.command(&id)).unwrap()["reason"], "not_received");
}

#[test]
fn missing_item_is_not_found_and_invalid_id_cannot_become_a_path() {
    let f = Fixture::new();
    assert!(matches!(
        dispatch(f.command(&digest(b"missing"))),
        Err(Error::NotFound)
    ));
    assert!(matches!(
        dispatch(f.command("../../original")),
        Err(Error::Invalid(_))
    ));
    assert!(!f.cache.join("receiver-previews-v1").exists());
    let absent = f.base.join("absent");
    assert!(matches!(
        preview(&absent, &f.cache, &digest(b"missing")),
        Err(Error::NotFound)
    ));
    assert!(!absent.exists());
}

#[test]
fn cache_respects_shared_budget_reclaims_old_and_interrupted_files() {
    let mut f = Fixture::new();
    let (one, _) = f.register("one", "image/jpeg", true);
    let (two, _) = f.register("two", "image/jpeg", true);
    let mut m = maintenance::Maintenance::open(&f.root).unwrap();
    let mut settings = m.settings.clone();
    settings.cache_budget_bytes = 100;
    m.save(settings.clone()).unwrap();
    let decoder = |_: &Path| Some(vec![42; 60]);
    let first = preview_with(&f.root, &f.cache, &one, decoder).unwrap();
    let first_path = PathBuf::from(first["path"].as_str().unwrap());
    let folder = first_path.parent().unwrap();
    fs::write(folder.join("interrupted.tmp"), [0; 10]).unwrap();
    let second = preview_with(&f.root, &f.cache, &two, decoder).unwrap();
    assert_eq!(second["status"], "available");
    assert!(!first_path.exists());
    assert!(!folder.join("interrupted.tmp").exists());
    assert_eq!(maintenance::directory_bytes(folder), 60);
    // An unrelated app cache consumer leaves insufficient budget for a preview.
    fs::write(f.cache.join("other-cache"), [0; 80]).unwrap();
    assert_eq!(
        preview_with(&f.root, &f.cache, &one, decoder).unwrap()["reason"],
        "cache_budget"
    );
    assert_eq!(maintenance::directory_bytes(folder), 0);
    fs::remove_file(f.cache.join("other-cache")).unwrap();
}

#[test]
fn originals_and_cache_symlinks_cannot_be_used_as_output_directories() {
    let mut f = Fixture::new();
    let (id, original) = f.register("photo", "image/jpeg", true);
    let before = fs::read(&original).unwrap();
    assert!(matches!(
        preview_with(&f.root, &f.root.join("store/blobs"), &id, |_| panic!(
            "unsafe decoder"
        )),
        Err(Error::Invalid(_))
    ));
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(
            f.root.join("store/blobs"),
            f.cache.join("receiver-previews-v1"),
        )
        .unwrap();
        assert!(matches!(dispatch(f.command(&id)), Err(Error::Invalid(_))));
    }
    assert_eq!(fs::read(original).unwrap(), before);
}

#[cfg(not(target_os = "android"))]
#[test]
fn command_without_a_platform_decoder_is_explicitly_unavailable() {
    let mut f = Fixture::new();
    let (id, _) = f.register("photo", "image/jpeg", true);
    assert_eq!(
        dispatch(f.command(&id)).unwrap()["reason"],
        "decode_unavailable"
    );
}

#[test]
fn cached_preview_survives_original_release_but_cannot_be_regenerated() {
    let mut f = Fixture::new();
    let (id, original) = f.register("released", "image/jpeg", true);
    let first = preview_with(&f.root, &f.cache, &id, |_| Some(vec![1; 60])).unwrap();
    f.receiver
        .set_processing(&id, ProcessingState::Pending)
        .unwrap();
    f.receiver
        .set_processing(&id, ProcessingState::Complete)
        .unwrap();
    let verified = BTreeSet::from([digest(&fs::read(&original).unwrap())]);
    f.receiver
        .release_archived(std::slice::from_ref(&id), &verified)
        .unwrap();
    assert!(!original.exists());
    assert_eq!(dispatch(f.command(&id)).unwrap()["cache_hit"], true);
    fs::remove_file(first["path"].as_str().unwrap()).unwrap();
    assert_eq!(
        preview_with(&f.root, &f.cache, &id, |_| panic!("released decoder")).unwrap()["reason"],
        "original_unavailable"
    );
}
