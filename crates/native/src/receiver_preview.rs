//! Disposable local previews. Catalog reads never reconcile receiver originals.
use super::*;

const LONG_EDGE: u32 = 512;
const DISK_BUDGET: u64 = 12 << 20;
const MAX_JPEG_BYTES: u64 = 2 << 20;
static PREVIEWS: Mutex<()> = Mutex::new(());

fn unavailable(reason: &str) -> Value {
    json!({"status":"unavailable", "path":null, "reason":reason})
}

pub(super) fn preview(root: &Path, cache_dir: &Path, id: &str) -> Result<Value> {
    preview_with(root, cache_dir, id, decode)
}

fn preview_with(
    root: &Path,
    cache_dir: &Path,
    id: &str,
    decode: impl Fn(&Path) -> Option<Vec<u8>>,
) -> Result<Value> {
    // Bound decode concurrency and serialize eviction/publication. No receiver or
    // network mutex is held during image decoding.
    let _guard = PREVIEWS.lock().map_err(lock)?;
    let (asset, received, released) =
        backupduck_store::catalog::Catalog::open(&root.join("store"))?.preview_asset(id)?;
    if !received {
        return Ok(unavailable("not_received"));
    }
    // The host must pass its app-owned cache directory (Context.cacheDir on
    // Android), never an original/export directory. Canonical paths also reject
    // aliases and symlinks pointing back into the receiver store.
    let root = root.canonicalize()?;
    let cache_root = cache_dir.canonicalize()?;
    if cache_root.starts_with(&root) || root.starts_with(&cache_root) {
        return Err(Error::Invalid("preview cache directory".into()));
    }
    let folder = cache_root.join("receiver-previews-v1");
    match fs::symlink_metadata(&folder) {
        Ok(m) if !m.is_dir() => return Err(Error::Invalid("preview cache directory".into())),
        Ok(_) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => fs::create_dir(&folder)?,
        Err(e) => return Err(e.into()),
    }
    let settings = receiver_storage::with_maintenance(Some(&root), |m| Ok(m.settings.clone()))?;
    let budget = DISK_BUDGET.min(settings.cache_budget_bytes);
    // Other files in the shared app cache consume the same total cache budget.
    let other_bytes = maintenance::directory_bytes(&cache_root)
        .saturating_sub(maintenance::directory_bytes(&folder));
    let budget = budget.min(settings.cache_budget_bytes.saturating_sub(other_bytes));
    prune(&folder, budget)?;
    let path = folder.join(format!("{id}.jpg"));
    if let Ok(metadata) = fs::symlink_metadata(&path) {
        if metadata.is_file() && metadata.len() > 0 && metadata.len() <= MAX_JPEG_BYTES {
            // Touch on access for least-recently-used eviction. Cache files are
            // private, disposable; source timestamps and bytes are untouched.
            File::open(&path)?.set_times(fs::FileTimes::new().set_modified(SystemTime::now()))?;
            return Ok(
                json!({"status":"available","path":path,"cache_hit":true,"max_edge":LONG_EDGE}),
            );
        }
        fs::remove_file(&path)?;
    }
    if released {
        return Ok(unavailable("original_unavailable"));
    }
    let Some(resource) = asset.resources.iter().find(|r| {
        r.role == ResourceRole::Photo
            && matches!(
                r.media_type.as_str(),
                "image/jpeg" | "image/png" | "image/heic" | "image/heif"
            )
    }) else {
        return Ok(unavailable("unsupported_format"));
    };
    if budget == 0
        || fs2::available_space(&folder)? < settings.min_free_bytes.saturating_add(MAX_JPEG_BYTES)
    {
        return Ok(unavailable("cache_budget"));
    }
    let source = root.join("store/blobs").join(&resource.sha256);
    if !fs::symlink_metadata(&source).is_ok_and(|m| m.is_file() && m.len() == resource.size) {
        return Ok(unavailable("original_unavailable"));
    }
    let Some(bytes) = decode(&source) else {
        return Ok(unavailable("decode_unavailable"));
    };
    if bytes.is_empty() || bytes.len() as u64 > MAX_JPEG_BYTES {
        return Ok(unavailable("decode_unavailable"));
    }
    if bytes.len() as u64 > budget {
        return Ok(unavailable("cache_budget"));
    }
    // Recheck free space after decoding; neither originals nor receipts change
    // when an OS cache purge or disk pressure prevents publication.
    if fs2::available_space(&folder)? < settings.min_free_bytes.saturating_add(bytes.len() as u64) {
        return Ok(unavailable("cache_budget"));
    }
    prune(&folder, budget.saturating_sub(bytes.len() as u64))?;
    let temporary = folder.join(format!("{id}.tmp"));
    let result = (|| {
        private_write(&temporary, &bytes)?;
        fs::rename(&temporary, &path)?;
        Ok(json!({"status":"available","path":path,"cache_hit":false,"max_edge":LONG_EDGE}))
    })();
    if result.is_err() {
        let _ = fs::remove_file(temporary);
    }
    result
}

fn prune(folder: &Path, budget: u64) -> Result<()> {
    let mut entries = Vec::new();
    let mut used = 0u64;
    for entry in fs::read_dir(folder)? {
        let entry = entry?;
        let m = fs::symlink_metadata(entry.path())?;
        // Do not follow symlinks or traverse unexpected directories. Temp files
        // are leftovers from interrupted writes and are always reclaimable.
        if !m.is_file() || entry.path().extension().is_none_or(|e| e != "jpg") {
            if !m.is_dir() {
                fs::remove_file(entry.path())?;
            }
            continue;
        }
        used = used.saturating_add(m.len());
        entries.push((m.modified().unwrap_or(UNIX_EPOCH), entry.path(), m.len()));
    }
    entries.sort();
    for (_, path, bytes) in entries {
        if used <= budget {
            break;
        }
        fs::remove_file(path)?;
        used = used.saturating_sub(bytes);
    }
    Ok(())
}

#[cfg(not(target_os = "android"))]
fn decode(_source: &Path) -> Option<Vec<u8>> {
    None
}
#[cfg(target_os = "android")]
fn decode(source: &Path) -> Option<Vec<u8>> {
    android::decode(source)
}

#[cfg(target_os = "android")]
pub(super) mod android;

#[cfg(test)]
mod tests;
