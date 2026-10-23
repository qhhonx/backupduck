//! Bounded, process-local read snapshots for latest-change pagination.
//! No business state is kept here; expired cursors fail explicitly so hosts can
//! atomically refresh rather than accidentally splice two different timelines.
use backupduck_core::{Error, Result};
use backupduck_store::catalog::Catalog;
use serde_json::{json, Value};
use std::{
    path::{Path, PathBuf},
    sync::{Mutex, OnceLock},
    time::{Duration, Instant},
};

struct Snapshot {
    token: String,
    root: PathBuf,
    state: String,
    kind: String,
    sender: Option<String>,
    touched: Instant,
    revision: i64,
    catalog: Catalog,
}
static SNAPSHOTS: OnceLock<Mutex<Vec<Snapshot>>> = OnceLock::new();

pub fn page(
    root: &Path,
    cursor: Option<&str>,
    state: &str,
    kind: &str,
    sender: Option<&str>,
    known_revision: Option<i64>,
) -> Result<Value> {
    let mut snapshots = SNAPSHOTS
        .get_or_init(|| Mutex::new(Vec::new()))
        .lock()
        .map_err(super::lock)?;
    snapshots.retain(|s| s.touched.elapsed() < Duration::from_secs(300));
    let (index, before) = if let Some(cursor) = cursor {
        let (token, before) = cursor
            .split_once(':')
            .ok_or_else(|| Error::Invalid("history cursor".into()))?;
        let before = before
            .parse::<i64>()
            .map_err(|_| Error::Invalid("history cursor".into()))?;
        let index = snapshots
            .iter()
            .position(|s| {
                s.token == token
                    && s.root == root
                    && s.state == state
                    && s.kind == kind
                    && s.sender.as_deref() == sender
            })
            .ok_or_else(|| Error::Conflict("history_snapshot_expired".into()))?;
        (index, Some(before))
    } else {
        let mut catalog = Catalog::open(&root.join("store"))?;
        if known_revision == Some(catalog.revision()?) {
            return Ok(json!({"unchanged":true}));
        }
        let revision = catalog.freeze_latest()?;
        let mut random = [0; 16];
        getrandom::fill(&mut random).map_err(|_| Error::Storage("random source".into()))?;
        let token = random.iter().map(|b| format!("{b:02x}")).collect();
        if snapshots.len() >= 8 {
            snapshots.remove(0);
        }
        snapshots.push(Snapshot {
            token,
            root: root.into(),
            state: state.into(),
            kind: kind.into(),
            sender: sender.map(str::to_owned),
            touched: Instant::now(),
            revision,
            catalog,
        });
        (snapshots.len() - 1, None)
    };
    let snapshot = &mut snapshots[index];
    snapshot.touched = Instant::now();
    let page = snapshot
        .catalog
        .latest_page(before, state, kind, 100, sender)?;
    let next = page
        .next_cursor
        .map(|id| format!("{}:{id}", snapshot.token));
    let mut value = serde_json::to_value(page)?;
    value["next_cursor"] = json!(next);
    value["revision"] = json!(snapshot.revision);
    value["counts"] = snapshot.catalog.counts()?;
    Ok(value)
}
