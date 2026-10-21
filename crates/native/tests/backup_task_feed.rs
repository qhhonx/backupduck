//! Preparation-to-transfer UI membership, through the real FFI and databases.
use serde_json::{json, Value};
use std::{
    ffi::{CStr, CString},
    fs,
};
fn call(input: Value) -> Value {
    let input = CString::new(input.to_string()).unwrap();
    let out = unsafe { backupduck_native::backupduck_call(input.as_ptr()) };
    assert!(!out.is_null());
    let envelope: Value =
        unsafe { serde_json::from_slice(CStr::from_ptr(out).to_bytes()).unwrap() };
    unsafe { backupduck_native::backupduck_free(out) };
    assert_eq!(envelope["ok"], true, "{envelope}");
    envelope["value"].clone()
}
#[test]
fn preparations_are_exhaustive_paged_and_handoff_keeps_identity_without_changing_asset() {
    let root = std::env::temp_dir().join(format!("backup-feed-{}", std::process::id()));
    let _ = fs::remove_dir_all(&root);
    fs::create_dir_all(&root).unwrap();
    call(json!({"op":"open_sender","root":root}));
    let feed = |category: &str| {
        call(
            json!({"op":"backup_tasks","receiver_id":"target","state":category,"sort":"capture","descending":true}),
        )
    };
    let rev = call(json!({"op":"sender_revision"}));
    call(json!({"op":"schedule_sources","receiver_id":"target","sources":["one","two","three"]}));
    assert!(call(json!({"op":"sender_revision"})).as_i64().unwrap() > rev.as_i64().unwrap());
    call(
        json!({"op":"source_dates","receiver_id":"target","dates":[["one",300],["two",200],["three",100]]}),
    );
    call(json!({"op":"schedule_sources","receiver_id":"other","sources":["private-other"]}));
    let before = feed("all");
    assert_eq!(before["summary"]["total"], 3);
    assert_eq!(feed("active")["items"].as_array().unwrap().len(), 3);
    let first = before["items"][0].clone();
    assert_eq!(first["preparation"]["source"], "one");
    call(
        json!({"op":"source_result","receiver_id":"target","source":"three","complete":false,"error":"source_unavailable"}),
    );
    assert_eq!(
        feed("attention")["items"][0]["preparation"]["error_code"],
        "source_unavailable"
    );
    call(json!({"op":"retry_source","receiver_id":"target","source":"three"}));
    assert_eq!(feed("attention")["summary"]["attention"], 0);
    call(
        json!({"op":"source_result","receiver_id":"target","source":"three","complete":false,"error":"source_unavailable"}),
    );
    let file = root.join("fixture.jpg");
    fs::write(&file, b"synthetic-original").unwrap();
    let job = call(
        json!({"op":"enqueue","receiver_id":"target","source_id":"one","revision":"1","kind":"photo","preparation_id":"one","metadata":{"created_at_ms":"300"},"resources":[{"role":"photo","filename":"fixture.jpg","media_type":"image/jpeg","path":file}]}),
    );
    assert!(
        job["asset"]["metadata"]
            .get("backupduck_preparation_id")
            .is_none(),
        "presentation identity is not part of the protocol asset hash"
    );
    assert!(call(json!({"op":"history_status","receiver_id":"target"})).is_null());
    let history = call(json!({"op":"history_control","receiver_id":"target","action":"start"}));
    assert_eq!(
        call(json!({"op":"history_status","receiver_id":"target"}))["published"],
        0
    );
    call(
        json!({"op":"history_batch","receiver_id":"target","run":history["run"],"sources":[["one","1"]],"finished":true}),
    );
    let history_status = || call(json!({"op":"history_status","receiver_id":"target"}));
    assert_eq!(history_status()["checked"], 1);
    assert_eq!(history_status()["state"], "scanned");
    assert_eq!(history_status()["published"], 0);
    let overlap = feed("all");
    assert_eq!(
        overlap["summary"]["total"], 3,
        "enqueue committed, preparation ack not yet committed"
    );
    assert_eq!(overlap["items"][0]["id"], first["id"]);
    assert_eq!(overlap["items"][0]["cursor"], first["cursor"]);
    assert!(overlap["items"][0]["job"].is_object());
    call(json!({"op":"source_result","receiver_id":"target","source":"one","complete":true}));
    assert_eq!(feed("all")["items"][0]["id"], first["id"]);
    // Synthetic publication observations validate category semantics without
    // claiming a network receipt or real Android gallery publication.
    let db = rusqlite::Connection::open(root.join("sender.sqlite3")).unwrap();
    let id = job["id"].as_i64().unwrap();
    db.execute(
        "INSERT INTO processing_observations(job_id,state) VALUES(?1,'complete')",
        [id],
    )
    .unwrap();
    assert_eq!(history_status()["published"], 0, "Receipt is also required");
    db.execute("DELETE FROM processing_observations WHERE job_id=?1", [id])
        .unwrap();
    db.execute("UPDATE jobs SET state='received' WHERE id=?1", [id])
        .unwrap();
    assert_eq!(
        history_status()["published"],
        0,
        "Receipt alone is insufficient"
    );
    assert_eq!(feed("active")["items"].as_array().unwrap().len(), 2);
    db.execute(
        "INSERT INTO processing_observations(job_id,state,error) VALUES(?1,'failed','conversion_required')",
        [id],
    )
    .unwrap();
    assert_eq!(history_status()["published"], 0);
    assert_eq!(feed("all")["summary"]["conversion_required"], 1);
    assert_eq!(
        call(json!({"op":"sender_summary","receiver_id":"target"}))["conversion_required"],
        1
    );
    assert_eq!(
        call(json!({"op":"backup_summary","receiver_id":"target"}))["conversion_required"],
        1
    );
    assert_eq!(feed("attention")["items"].as_array().unwrap().len(), 2);
    db.execute(
        "UPDATE processing_observations SET state='complete' WHERE job_id=?1",
        [id],
    )
    .unwrap();
    assert_eq!(history_status()["published"], 1);
    assert_eq!(history_status()["pending"], 0);
    assert_eq!(history_status()["checked"], 1);
    assert_eq!(feed("all")["summary"]["conversion_required"], 0);
    assert!(call(json!({"op":"history_status","receiver_id":"other"})).is_null());
    assert_eq!(feed("saved")["items"].as_array().unwrap().len(), 1);
    let summary = feed("all")["summary"].clone();
    assert_eq!(
        summary["total"].as_i64().unwrap(),
        summary["active"].as_i64().unwrap()
            + summary["attention"].as_i64().unwrap()
            + summary["saved"].as_i64().unwrap()
    );
    assert_eq!(
        call(json!({"op":"backup_summary","receiver_id":"target","source_filter":"folder"}))
            ["total"],
        0
    );
    let sources: Vec<_> = (0..405).map(|n| format!("page-{n}")).collect();
    call(json!({"op":"schedule_sources","receiver_id":"pages","sources":sources}));
    let mut after = 0;
    let mut value = None;
    let mut ids = std::collections::BTreeSet::new();
    loop {
        let page = call(
            json!({"op":"backup_tasks","receiver_id":"pages","sort":"capture","descending":true,"after":after,"after_value":value}),
        );
        let rows = page["items"].as_array().unwrap();
        assert_eq!(page["summary"]["total"], 405);
        for item in rows {
            assert!(ids.insert(item["id"].as_str().unwrap().to_owned()));
        }
        if rows.len() < 200 {
            break;
        }
        let last = rows.last().unwrap();
        after = last["cursor"].as_i64().unwrap();
        value = last["sort_value"].as_i64();
    }
    call(json!({"op":"source_result","receiver_id":"pages","source":"page-404","complete":true}));
    call(json!({"op":"schedule_sources","receiver_id":"pages","sources":["replacement"]}));
    let replacement =
        call(json!({"op":"backup_tasks","receiver_id":"pages","sort":"added","descending":true}));
    let current: Vec<_> = replacement["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["cursor"].as_i64().unwrap())
        .collect();
    assert_eq!(
        current
            .iter()
            .collect::<std::collections::BTreeSet<_>>()
            .len(),
        current.len(),
        "deleting the highest pending row must not reuse a cursor"
    );
    assert_eq!(ids.len(), 405);
    assert!(file.is_file(), "presentation queries retain originals");
    drop(db);
    let _ = fs::remove_dir_all(root);
}
