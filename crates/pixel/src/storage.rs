//! Read-only receiver media accounting. File lengths are distinct from reserved
//! transfer capacity; recorded gallery evidence is not a fresh deletion proof.
use backupduck_core::{Error, Result};
use rusqlite::{Connection, OpenFlags};
use serde::Serialize;
use std::{collections::BTreeMap, fs, io, path::Path};

#[derive(Debug, Default, Serialize)]
pub struct StorageBreakdown {
    pub own_copy_bytes: u64,
    pub ready_bytes: u64,
    pub partial_bytes: u64,
    pub converted_original_bytes: Option<u64>,
    pub pending_bytes: Option<u64>,
    pub other_original_bytes: Option<u64>,
    /// Subset of own copies with recorded gallery evidence for every retained
    /// reference. Manual relay estimate only; fresh verification is still required.
    pub reclaimable_bytes: Option<u64>,
    pub free_bytes: Option<u64>,
}

fn db(e: rusqlite::Error) -> Error {
    Error::Storage(e.to_string())
}
fn add(total: &mut u64, bytes: u64) -> Result<()> {
    *total = total.checked_add(bytes).ok_or(Error::Capacity)?;
    Ok(())
}

/// `root` is the native receiver root (its catalog is in `store/`). Does not
/// open a Receiver, reconcile files, acquire its writer lock or change policy.
pub fn breakdown(root: &Path) -> Result<StorageBreakdown> {
    let mut result = StorageBreakdown::default();
    result.free_bytes = match fs::metadata(root) {
        Ok(_) => Some(fs2::available_space(root)?),
        Err(e) if e.kind() == io::ErrorKind::NotFound => None,
        Err(e) => return Err(e.into()),
    };
    let store = root.join("store");
    let mut files = BTreeMap::new();
    // Ready takes precedence across an observed rename; each hash counts once.
    for (folder, ready) in [("partial", false), ("blobs", true)] {
        let path = store.join(folder);
        match fs::symlink_metadata(&path) {
            Ok(m) if m.is_dir() => {}
            Ok(_) => return Err(Error::Integrity),
            Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
            Err(e) => return Err(e.into()),
        }
        for entry in fs::read_dir(path)? {
            let entry = entry?;
            let metadata = match fs::symlink_metadata(entry.path()) {
                Ok(m) => m,
                Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
                Err(e) => return Err(e.into()),
            };
            if metadata.is_file() {
                files.insert(entry.file_name(), (metadata.len(), ready));
            }
        }
    }
    for &(bytes, ready) in files.values() {
        add(&mut result.own_copy_bytes, bytes)?;
        add(
            if ready {
                &mut result.ready_bytes
            } else {
                &mut result.partial_bytes
            },
            bytes,
        )?;
    }
    let catalog = store.join("receiver.sqlite3");
    if !catalog.try_exists()? {
        // No catalog plus existing files cannot establish their purpose/safety.
        if files.is_empty() {
            result.converted_original_bytes = Some(0);
            result.pending_bytes = Some(0);
            result.other_original_bytes = Some(0);
            result.reclaimable_bytes = Some(0);
        }
        return Ok(result);
    }
    let conn =
        Connection::open_with_flags(catalog, OpenFlags::SQLITE_OPEN_READ_ONLY).map_err(db)?;
    conn.busy_timeout(std::time::Duration::from_millis(250))
        .map_err(db)?;
    let mut query = conn
        .prepare(
            "WITH refs AS (
            SELECT json_extract(r.value,'$.sha256') AS hash,
                a.received,a.processing,json_extract(a.manifest,'$.kind') AS kind,
                g.asset_id IS NOT NULL AS has_copy
            FROM assets a JOIN json_each(a.manifest,'$.resources') r
            LEFT JOIN gallery_copies g ON g.asset_id=a.id
            WHERE a.originals_released=0
        )
        SELECT hash,MAX(received=0 OR processing!='complete'),
            MAX(kind='motion' AND received=1 AND processing='complete' AND has_copy),
            MIN(received=1 AND processing='complete' AND has_copy)
        FROM refs GROUP BY hash",
        )
        .map_err(db)?;
    let rows = query
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, bool>(1)?,
                r.get::<_, bool>(2)?,
                r.get::<_, bool>(3)?,
            ))
        })
        .map_err(db)?;
    let (mut converted, mut pending, mut reclaimable) = (0, result.partial_bytes, 0);
    for row in rows {
        let (hash, is_pending, is_converted, can_reclaim) = row.map_err(db)?;
        let Some(&(bytes, ready)) = files.get(std::ffi::OsStr::new(&hash)) else {
            continue;
        };
        if ready && is_pending {
            add(&mut pending, bytes)?;
        } else if ready && is_converted {
            add(&mut converted, bytes)?;
        }
        if ready && can_reclaim {
            add(&mut reclaimable, bytes)?;
        }
    }
    // Uncatalogued partials are still unfinished local copies.
    // Ready files without a retained reference remain in the residual category.
    result.converted_original_bytes = Some(converted);
    result.pending_bytes = Some(pending);
    result.other_original_bytes = Some(result.own_copy_bytes - pending - converted);
    result.reclaimable_bytes = Some(reclaimable);
    Ok(result)
}

#[cfg(test)]
mod tests;
