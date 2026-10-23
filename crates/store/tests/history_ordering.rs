use backupduck_core::*;
use backupduck_store::{catalog::Catalog, Receiver};
use rusqlite::{params, Connection};
use std::collections::{BTreeMap, HashSet};

#[test]
fn latest_snapshot_has_no_gaps_or_duplicates_when_states_change_between_pages() {
    let root = std::env::temp_dir().join(format!("duck-history-ordering-{}", std::process::id()));
    let receiver = Receiver::open(&root, 1_000_000).unwrap();
    let conn = Connection::open(root.join("receiver.sqlite3")).unwrap();
    let mut expected = Vec::new();
    for index in 1..=411i64 {
        let asset = Asset {
            version: PROTOCOL_VERSION,
            source_id: format!("ordering-{index}"),
            revision: "1".into(),
            kind: AssetKind::Photo,
            metadata: BTreeMap::new(),
            resources: vec![Resource {
                role: ResourceRole::Photo,
                filename: format!("{index}.jpg"),
                media_type: "image/jpeg".into(),
                size: 1,
                sha256: digest(b"x"),
            }],
        };
        let id = asset.id().unwrap();
        // Arrival IDs ascend; changes interleave four pages, including equal times.
        let changed = 1_700_000_000_000 + ((index * 137) % 61) * 86_400_000;
        conn.execute(
            "INSERT INTO assets(id,manifest,received,processing) VALUES(?1,?2,1,'complete')",
            params![id, serde_json::to_string(&asset).unwrap()],
        )
        .unwrap();
        conn.execute("UPDATE assets SET received_at_ms=?2,published_at_ms=?2,state_changed_at_ms=?3 WHERE id=?1", params![id, 1_600_000_000_000i64 + index, changed]).unwrap();
        expected.push((changed, index));
    }
    expected.sort_by(|a, b| b.cmp(a));
    let mut snapshot = Catalog::open(&root).unwrap();
    let revision = snapshot.freeze_latest().unwrap();
    let first = snapshot.latest_page(None, "all", "all", 100, None).unwrap();
    assert_eq!(first.total, 411);
    assert_eq!(
        first
            .items
            .iter()
            .map(|i| (i.state_changed_at_ms.unwrap(), i.cursor))
            .collect::<Vec<_>>(),
        expected[..100]
    );
    // Both a visited and an unseen item move ahead of the cursor; the cursor
    // asset itself is deleted. None may disappear or be returned twice.
    let unseen = expected[305].1;
    conn.execute(
        "UPDATE assets SET processing='failed',processing_error='storage' WHERE rowid IN (?1,?2)",
        params![expected[10].1, unseen],
    )
    .unwrap();
    conn.execute(
        "DELETE FROM assets WHERE rowid=?1",
        [first.next_cursor.unwrap()],
    )
    .unwrap();
    // A new arrival belongs to the next refresh, not this snapshot.
    let manifest: String = conn
        .query_row("SELECT manifest FROM assets LIMIT 1", [], |r| r.get(0))
        .unwrap();
    conn.execute(
        "INSERT INTO assets(id,manifest,received) VALUES('new-arrival',?1,1)",
        [manifest],
    )
    .unwrap();
    let mut seen = first
        .items
        .iter()
        .map(|i| (i.state_changed_at_ms.unwrap(), i.cursor))
        .collect::<Vec<_>>();
    let mut next = first.next_cursor;
    while let Some(before) = next {
        let page = snapshot
            .latest_page(Some(before), "all", "all", 100, None)
            .unwrap();
        seen.extend(
            page.items
                .iter()
                .map(|i| (i.state_changed_at_ms.unwrap(), i.cursor)),
        );
        next = page.next_cursor;
    }
    assert_eq!(seen, expected);
    assert_eq!(seen.iter().map(|i| i.1).collect::<HashSet<_>>().len(), 411);
    // Replaying a cursor gives the same boundary, including the deleted row.
    assert_eq!(
        snapshot
            .latest_page(first.next_cursor, "all", "all", 100, None)
            .unwrap()
            .items[0]
            .cursor,
        expected[100].1
    );
    let mut fresh = Catalog::open(&root).unwrap();
    assert!(fresh.freeze_latest().unwrap() > revision);
    let failures = fresh.latest_page(None, "failed", "all", 100, None).unwrap();
    assert_eq!(failures.items.len(), 2);
    assert!(failures
        .items
        .iter()
        .all(|i| i.processing == "failed" && i.state_changed_at_ms.unwrap() > expected[0].0));
    // The compatibility operation still uses arrival row IDs.
    let legacy = Catalog::open(&root)
        .unwrap()
        .page(None, "all", "all", 100)
        .unwrap();
    assert!(legacy.items.windows(2).all(|p| p[0].cursor > p[1].cursor));
    drop(snapshot);
    drop(fresh);
    drop(conn);
    drop(receiver);
    std::fs::remove_dir_all(root).unwrap();
}
