use backupduck_core::*;
use backupduck_sender::*;
use std::{
    collections::{BTreeMap, BTreeSet},
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};
static SEQ: AtomicU64 = AtomicU64::new(0);
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        Self(std::env::temp_dir().join(format!(
            "backupduck-queue-{}-{}",
            std::process::id(),
            SEQ.fetch_add(1, Ordering::Relaxed)
        )))
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn asset() -> Asset {
    Asset {
        version: PROTOCOL_VERSION,
        source_id: "native:42".into(),
        revision: "1".into(),
        kind: AssetKind::Photo,
        metadata: BTreeMap::new(),
        resources: vec![Resource {
            role: ResourceRole::Photo,
            filename: "photo.jpg".into(),
            media_type: "image/jpeg".into(),
            size: 10,
            sha256: digest(b"0123456789"),
        }],
    }
}
fn add(s: &mut Sender) -> Job {
    let a = asset();
    let sources = BTreeMap::from([(
        a.resources[0].sha256.clone(),
        "opaque-native-resource-reference".into(),
    )]);
    s.enqueue("receiver-1", a, sources).unwrap()
}
fn status(j: &Job, received: bool) -> AssetStatus {
    AssetStatus {
        asset_id: j.asset.id().unwrap(),
        receipt: if received {
            ReceiptState::Received
        } else {
            ReceiptState::Receiving
        },
        processing: ProcessingState::NotRequested,
        processing_error: None,
        resources: vec![ResourceStatus {
            sha256: j.asset.resources[0].sha256.clone(),
            offset: if received { 10 } else { 5 },
            complete: received,
        }],
    }
}

#[test]
fn explicit_rebackup_creates_a_new_job_without_changing_source_revision() {
    let t = Temp::new();
    let mut sender = Sender::open(&t.0).unwrap();
    let first = add(&mut sender);
    let running = sender.claim("receiver-1", 0).unwrap().unwrap();
    sender
        .acknowledge(&running.attempt(), &status(&running, true))
        .unwrap();
    assert_eq!(sender.job(first.id).unwrap().state, JobState::Received);

    let mut repeat = asset();
    repeat
        .metadata
        .insert("backupduck_rebackup_id".into(), "manual-request-1".into());
    let sources = BTreeMap::from([(
        repeat.resources[0].sha256.clone(),
        "opaque-native-resource-reference".into(),
    )]);
    let second = sender.enqueue("receiver-1", repeat, sources).unwrap();
    assert_ne!(first.id, second.id);
    assert_ne!(first.asset.id().unwrap(), second.asset.id().unwrap());
    assert_eq!(second.state, JobState::Queued);
    assert_eq!(second.asset.source_id, first.asset.source_id);
    assert_eq!(second.asset.revision, first.asset.revision);
    assert_eq!(sender.job(first.id).unwrap().state, JobState::Received);
    assert_eq!(
        sender
            .source_states("receiver-1", &[("native:42".into(), "1".into())])
            .unwrap()["native:42"],
        "queued"
    );
}

#[test]
fn gallery_failure_stays_visible_and_retry_never_requeues_original_bytes() {
    let t = Temp::new();
    let mut s = Sender::open(&t.0).unwrap();
    add(&mut s);
    let j = s.claim("receiver-1", 0).unwrap().unwrap();
    let mut receipt = status(&j, true);
    receipt.processing = ProcessingState::Pending;
    s.acknowledge(&j.attempt(), &receipt).unwrap();
    assert_eq!(
        s.job(j.id).unwrap().processing,
        Some(ProcessingState::Pending)
    );
    assert_eq!(s.processing_due("receiver-1", 1, 10).unwrap().len(), 1);
    assert!(s.claim("receiver-1", 1).unwrap().is_none());

    receipt.processing = ProcessingState::Failed;
    receipt.processing_error = Some("unsupported".into());
    s.observe_processing(j.id, &receipt, 2).unwrap();
    assert_eq!(
        s.job(j.id).unwrap().processing_error.as_deref(),
        Some("unsupported")
    );
    assert_eq!(s.summary("receiver-1").unwrap()["publication_failed"], 1);
    assert!(s.processing_due("receiver-1", 20, 10).unwrap().is_empty());
    assert_eq!(
        s.processing_event_jobs("receiver-1").unwrap().len(),
        1,
        "Foreground events must not inherit the 60-second failure delay"
    );
    assert!(s
        .processing_event_jobs("different-receiver")
        .unwrap()
        .is_empty());

    receipt.processing = ProcessingState::Complete;
    receipt.processing_error = None;
    s.observe_processing(j.id, &receipt, 63).unwrap();
    drop(s);
    let mut s = Sender::open(&t.0).unwrap();
    assert_eq!(s.job(j.id).unwrap().state, JobState::Received);
    assert_eq!(
        s.job(j.id).unwrap().processing,
        Some(ProcessingState::Complete)
    );
    assert_eq!(s.summary("receiver-1").unwrap()["published"], 1);
    assert!(s.processing_due("receiver-1", 1000, 10).unwrap().is_empty());
    assert!(s.processing_event_jobs("receiver-1").unwrap().is_empty());
    assert!(s.claim("receiver-1", 1000).unwrap().is_none());
}

#[test]
fn capture_order_survives_restart_and_keeps_running_and_delayed_jobs() {
    let t = Temp::new();
    let mut s = Sender::open(&t.0).unwrap();
    let mut ids = Vec::new();
    for (name, date) in [
        ("old", Some(100)),
        ("new", Some(900)),
        ("middle", Some(500)),
        ("unknown", None),
    ] {
        let mut a = asset();
        a.source_id = name.into();
        if let Some(date) = date {
            a.metadata.insert("created_at_ms".into(), date.to_string());
        }
        let sources = BTreeMap::from([(a.resources[0].sha256.clone(), "resource".into())]);
        ids.push(s.enqueue("receiver-1", a, sources).unwrap().id);
    }
    drop(s);
    let mut s = Sender::open(&t.0).unwrap();
    let newest = s.claim("receiver-1", 10).unwrap().unwrap();
    assert_eq!(newest.id, ids[1]);
    s.fail(&newest.attempt(), Failure::Network, 10).unwrap();
    let retry_at = s.job(newest.id).unwrap().next_attempt_at;
    let middle = s.claim("receiver-1", 10).unwrap().unwrap();
    assert_eq!(middle.id, ids[2]);
    // An eligible retry follows capture order; an existing upload is not reset.
    assert_eq!(s.claim("receiver-1", retry_at).unwrap().unwrap().id, ids[1]);
    assert_eq!(s.job(middle.id).unwrap().state, JobState::Running);
    assert_eq!(s.claim("receiver-1", retry_at).unwrap().unwrap().id, ids[0]);
    assert_eq!(s.claim("receiver-1", retry_at).unwrap().unwrap().id, ids[3]);
}

#[test]
fn concurrency_setting_persists_and_does_not_cancel_active_tasks() {
    let t = Temp::new();
    let mut s = Sender::open(&t.0).unwrap();
    assert_eq!(s.concurrent_uploads().unwrap(), 4);
    assert!(s.set_concurrent_uploads(0).is_err());
    assert!(s.set_concurrent_uploads(5).is_err());
    s.set_concurrent_uploads(2).unwrap();
    s.set_bundle_upload("receiver-1", true).unwrap();
    for n in 0..4 {
        let mut a = asset();
        a.source_id = format!("concurrent-{n}");
        let sources = BTreeMap::from([(a.resources[0].sha256.clone(), "resource".into())]);
        s.enqueue("receiver-1", a, sources).unwrap();
    }
    let first = s.claim_native("receiver-1", 1).unwrap().unwrap();
    let second = s.claim_native("receiver-1", 1).unwrap().unwrap();
    assert!(s.claim_native("receiver-1", 1).unwrap().is_none());
    s.set_concurrent_uploads(1).unwrap();
    assert_eq!(s.job(first.id).unwrap().state, JobState::Running);
    assert_eq!(s.job(second.id).unwrap().state, JobState::Running);
    assert!(s.claim_native("receiver-1", 1).unwrap().is_none());
    s.acknowledge(&first.attempt(), &status(&first, true))
        .unwrap();
    assert!(s.claim_native("receiver-1", 1).unwrap().is_none());
    s.acknowledge(&second.attempt(), &status(&second, true))
        .unwrap();
    assert!(s.claim_native("receiver-1", 1).unwrap().is_some());
    drop(s);
    let s = Sender::open(&t.0).unwrap();
    assert_eq!(s.concurrent_uploads().unwrap(), 1);
}
#[test]
fn restart_resumes_and_keeps_pause_progress_and_dedupe() {
    let t = Temp::new();
    let mut s = Sender::open(&t.0).unwrap();
    let id = add(&mut s).id;
    assert_eq!(id, add(&mut s).id);
    let j = s.claim("receiver-1", 10).unwrap().unwrap();
    s.acknowledge(&j.attempt(), &status(&j, false)).unwrap();
    s.set_paused(true).unwrap();
    drop(s);
    let mut s = Sender::open(&t.0).unwrap();
    assert!(s.claim("receiver-1", 11).unwrap().is_none());
    assert_eq!(s.job(id).unwrap().confirmed_bytes, 5);
    s.set_paused(false).unwrap();
    let next = s.claim("receiver-1", 12).unwrap().unwrap();
    assert!(next.generation > j.generation);
    assert!(s.acknowledge(&j.attempt(), &status(&j, true)).is_err());
    s.acknowledge(&next.attempt(), &status(&next, true))
        .unwrap();
    s.retry(id).unwrap();
    assert_eq!(s.job(id).unwrap().state, JobState::Received);
    assert!(s.claim("receiver-1", 999).unwrap().is_none());
}
#[test]
fn transient_failure_is_automatic_permanent_failure_requires_action() {
    let t = Temp::new();
    let mut s = Sender::open(&t.0).unwrap();
    let id = add(&mut s).id;
    for f in [
        Failure::Network,
        Failure::Capacity,
        Failure::LowSpace,
        Failure::Busy,
    ] {
        let j = s.claim("receiver-1", 10000).unwrap().unwrap();
        s.fail(&j.attempt(), f, 10000).unwrap();
        let waiting = s.job(id).unwrap();
        assert_eq!(waiting.state, JobState::Waiting);
        assert!(s
            .claim("receiver-1", waiting.next_attempt_at - 1)
            .unwrap()
            .is_none());
        let j = s
            .claim("receiver-1", waiting.next_attempt_at)
            .unwrap()
            .unwrap();
        s.interrupted(&j.attempt()).unwrap();
    }
    let j = s.claim("receiver-1", 20000).unwrap().unwrap();
    s.fail(&j.attempt(), Failure::Authentication, 20000)
        .unwrap();
    assert!(s.claim("receiver-1", i64::MAX).unwrap().is_none());
    s.retry(id).unwrap();
    assert!(s.claim("receiver-1", 20001).unwrap().is_some());
}
#[test]
fn native_task_survives_restart_and_lost_completion_queries_receiver() {
    let t = Temp::new();
    let mut s = Sender::open(&t.0).unwrap();
    add(&mut s);
    let j = s.claim("receiver-1", 0).unwrap().unwrap();
    s.bind_native_task(&j.attempt(), "session:42").unwrap();
    drop(s);
    let mut s = Sender::open(&t.0).unwrap();
    assert!(s.claim("receiver-1", 0).unwrap().is_none());
    let cancel = s
        .reconcile_native(&BTreeSet::from([
            "session:42".into(),
            "session:stale".into(),
        ]))
        .unwrap();
    assert_eq!(cancel, vec!["session:stale"]);
    assert!(s.claim("receiver-1", 0).unwrap().is_none());
    s.reconcile_native(&BTreeSet::new()).unwrap();
    let next = s.claim("receiver-1", 0).unwrap().unwrap();
    assert!(s.acknowledge(&j.attempt(), &status(&j, true)).is_err());
    s.acknowledge(&next.attempt(), &status(&next, true))
        .unwrap();
}
#[test]
fn pause_invalidates_native_callbacks_and_multiple_destinations_are_independent() {
    let t = Temp::new();
    let mut s = Sender::open(&t.0).unwrap();
    let first = add(&mut s);
    let second = s
        .enqueue("receiver-2", first.asset.clone(), first.sources.clone())
        .unwrap();
    assert_ne!(first.id, second.id);
    let j = s.claim("receiver-1", 0).unwrap().unwrap();
    s.bind_native_task(&j.attempt(), "session:task").unwrap();
    assert_eq!(s.pause_job(j.id).unwrap().as_deref(), Some("session:task"));
    assert!(s.acknowledge(&j.attempt(), &status(&j, true)).is_err());
    assert!(s.claim("receiver-1", 999).unwrap().is_none());
    assert!(s.claim("receiver-2", 0).unwrap().is_some());
}
#[test]
fn invalid_ack_cannot_complete_and_root_has_single_owner() {
    let t = Temp::new();
    let mut s = Sender::open(&t.0).unwrap();
    assert!(Sender::open(&t.0).is_err());
    add(&mut s);
    let j = s.claim("receiver-1", 0).unwrap().unwrap();
    let mut st = status(&j, true);
    st.asset_id = digest(b"other");
    assert!(s.acknowledge(&j.attempt(), &st).is_err());
    assert_eq!(s.job(j.id).unwrap().state, JobState::Running);
}

#[test]
fn reexport_repairs_missing_sources_without_duplicating_the_asset() {
    let t = Temp::new();
    let mut sender = Sender::open(&t.0).unwrap();
    let first = add(&mut sender);
    let running = sender.claim("receiver-1", 0).unwrap().unwrap();
    sender
        .fail(&running.attempt(), Failure::SourceUnavailable, 0)
        .unwrap();
    let replacement = BTreeMap::from([(
        first.asset.resources[0].sha256.clone(),
        "new-export-reference".into(),
    )]);
    let repaired = sender
        .enqueue("receiver-1", first.asset, replacement.clone())
        .unwrap();
    assert_eq!(repaired.id, first.id);
    assert_eq!(repaired.sources, replacement);
    assert_eq!(repaired.state, JobState::Queued);
    assert_eq!(sender.list(0, 500).unwrap().len(), 1);
    assert!(sender
        .acknowledge(&running.attempt(), &status(&running, true))
        .is_err());
}

#[test]
fn native_ack_is_atomic_and_only_its_bound_attempt_can_advance() {
    let t = Temp::new();
    let mut s = Sender::open(&t.0).unwrap();
    add(&mut s);
    let j = s.claim_native("receiver-1", 0).unwrap().unwrap();
    assert!(s.claim_native("receiver-1", 0).unwrap().is_none());
    s.bind_native_task(&j.attempt(), "42").unwrap();
    assert!(s.bind_native_task(&j.attempt(), "other").is_err());
    assert!(s
        .complete_native(&j.attempt(), "other", &status(&j, false))
        .is_err());
    s.complete_native(&j.attempt(), "42", &status(&j, false))
        .unwrap();
    drop(s);
    let mut s = Sender::open(&t.0).unwrap();
    assert_eq!(s.checkpoint(j.id).unwrap().unwrap().resources[0].offset, 5);
    assert_eq!(s.job(j.id).unwrap().attempts, 0);
    let next = s.claim_native("receiver-1", 0).unwrap().unwrap();
    assert!(s
        .complete_native(&j.attempt(), "42", &status(&j, true))
        .is_err());
    s.set_paused(true).unwrap();
    assert!(s.bind_native_task(&next.attempt(), "43").is_err());
    s.interrupted(&next.attempt()).unwrap();
    assert!(s.checkpoint(j.id).unwrap().is_none());
    assert!(s.claim_native("receiver-1", 999).unwrap().is_none());
}

#[test]
fn visible_source_status_is_scoped_to_receiver_and_revision() {
    let t = Temp::new();
    let mut s = Sender::open(&t.0).unwrap();
    let before = s.revision().unwrap();
    let first = add(&mut s);
    assert!(s.revision().unwrap() > before);
    let keys = vec![(first.asset.source_id.clone(), first.asset.revision.clone())];
    assert_eq!(
        s.source_states("receiver-1", &keys).unwrap()[&first.asset.source_id],
        "queued"
    );
    assert!(s.source_states("receiver-2", &keys).unwrap().is_empty());
    assert!(s
        .source_states(
            "receiver-1",
            &[(first.asset.source_id.clone(), "edited".into())]
        )
        .unwrap()
        .is_empty());
    assert!(s.received_sources("receiver-1").unwrap().is_empty());
    let job = s.claim("receiver-1", 0).unwrap().unwrap();
    s.acknowledge(&job.attempt(), &status(&job, true)).unwrap();
    assert_eq!(
        s.source_states("receiver-1", &keys).unwrap()[&first.asset.source_id],
        "received"
    );
    assert_eq!(
        s.received_sources("receiver-1").unwrap(),
        vec![first.asset.source_id.clone()]
    );
    assert!(s.received_sources("receiver-2").unwrap().is_empty());
    let latest = s
        .latest_source_job("receiver-1", &first.asset.source_id)
        .unwrap()
        .unwrap();
    assert_eq!(latest.asset.source_id, first.asset.source_id);
    assert!(s
        .latest_source_job("receiver-2", &first.asset.source_id)
        .unwrap()
        .is_none());
    let edited = vec![(first.asset.source_id.clone(), "edited".into())];
    assert!(s.source_states("receiver-1", &edited).unwrap().is_empty());
    assert_eq!(
        s.previous_receipts("receiver-1", &edited).unwrap()[&first.asset.source_id],
        "received_previous"
    );
    assert!(s
        .previous_receipts("receiver-2", &edited)
        .unwrap()
        .is_empty());
    let summary = s.summary("receiver-1").unwrap();
    assert_eq!(summary["received"], 1);
    assert_eq!(summary["confirmed_bytes"], 10);
    assert_eq!(s.summary("receiver-2").unwrap()["total"], 0);
    assert!(s
        .source_states("receiver-1", &vec![keys[0].clone(); 401])
        .is_err());
}

#[test]
fn filtering_precedes_task_pagination() {
    let t = Temp::new();
    let mut sender = Sender::open(&t.0).unwrap();
    for index in 0..205 {
        let mut a = asset();
        a.source_id = format!("source-{index}");
        sender
            .enqueue(
                "receiver-1",
                a,
                BTreeMap::from([(digest(b"0123456789"), "resource".into())]),
            )
            .unwrap();
    }
    let mut a = asset();
    a.source_id = "other-receiver".into();
    let other = sender
        .enqueue(
            "receiver-2",
            a,
            BTreeMap::from([(digest(b"0123456789"), "resource".into())]),
        )
        .unwrap();
    assert_eq!(
        sender
            .list_filtered(0, 200, Some("receiver-2"), None)
            .unwrap()[0]
            .id,
        other.id
    );
    assert_eq!(
        sender
            .list_filtered(0, 200, Some("receiver-1"), None)
            .unwrap()
            .len(),
        200
    );
    assert_eq!(
        sender
            .list_filtered(200, 200, Some("receiver-1"), None)
            .unwrap()
            .len(),
        5
    );
    let mut ascending = Vec::new();
    let mut descending = Vec::new();
    for (reverse, ids) in [(false, &mut ascending), (true, &mut descending)] {
        let mut cursor = 0;
        loop {
            let page = sender
                .list_filtered_ordered(cursor, 100, Some("receiver-1"), Some("queued"), reverse)
                .unwrap();
            if page.is_empty() {
                break;
            }
            cursor = page.last().unwrap().id;
            ids.extend(page.into_iter().map(|job| job.id));
        }
    }
    assert_eq!(ascending.len(), 205);
    assert!(ascending.windows(2).all(|pair| pair[0] < pair[1]));
    assert_eq!(
        descending,
        ascending.iter().rev().copied().collect::<Vec<_>>()
    );
    let cursor = descending[99];
    let mut late = asset();
    late.source_id = "inserted-between-pages".into();
    sender
        .enqueue(
            "receiver-1",
            late,
            BTreeMap::from([(digest(b"0123456789"), "resource".into())]),
        )
        .unwrap();
    assert_eq!(
        sender
            .list_filtered_ordered(cursor, 200, Some("receiver-1"), Some("queued"), true)
            .unwrap()
            .into_iter()
            .map(|job| job.id)
            .collect::<Vec<_>>(),
        descending[100..]
    );
    let running = sender.claim("receiver-2", 100).unwrap().unwrap();
    sender
        .fail(&running.attempt(), Failure::Network, 100)
        .unwrap();
    assert_eq!(
        sender.list_filtered(0, 200, None, Some("waiting")).unwrap()[0].id,
        other.id
    );
    assert!(sender
        .list_filtered(0, 200, Some("receiver-1"), Some("waiting"))
        .unwrap()
        .is_empty());
}

#[test]
fn verified_connection_recovers_only_its_network_errors_without_resuming_pause() {
    let t = Temp::new();
    let mut s = Sender::open(&t.0).unwrap();
    let mut cases = Vec::new();
    for (n, failure) in [
        Failure::Network,
        Failure::Authentication,
        Failure::Integrity,
        Failure::SourceUnavailable,
        Failure::LowSpace,
    ]
    .into_iter()
    .enumerate()
    {
        let mut a = asset();
        a.source_id = format!("route-{n}");
        let sources = BTreeMap::from([(a.resources[0].sha256.clone(), "fixture".into())]);
        let job = s.enqueue("receiver-1", a, sources).unwrap();
        let running = s.claim("receiver-1", 0).unwrap().unwrap();
        assert_eq!(job.id, running.id);
        s.acknowledge(&running.attempt(), &status(&running, false))
            .unwrap();
        s.fail(&running.attempt(), failure, 10000).unwrap();
        cases.push(s.job(job.id).unwrap());
    }
    let other = s
        .enqueue(
            "receiver-2",
            asset(),
            BTreeMap::from([(asset().resources[0].sha256.clone(), "fixture".into())]),
        )
        .unwrap();
    let running = s.claim("receiver-2", 0).unwrap().unwrap();
    s.fail(&running.attempt(), Failure::Authentication, 10000)
        .unwrap();
    s.pause_job(cases[0].id).unwrap();
    s.set_paused(true).unwrap();
    assert_eq!(s.recover_connection("receiver-1").unwrap(), 1);
    assert!(s.paused().unwrap());
    assert!(s.claim("receiver-1", i64::MAX).unwrap().is_none());
    assert_eq!(s.job(cases[0].id).unwrap().state, JobState::Paused);
    let auth = s.job(cases[1].id).unwrap();
    assert_eq!(auth.state, JobState::Queued);
    assert_eq!(auth.confirmed_bytes, 5);
    assert!(auth.generation > cases[1].generation);
    assert_eq!(s.job(other.id).unwrap().state, JobState::Failed);
    for old in &cases[2..] {
        assert_eq!(s.job(old.id).unwrap().state, old.state);
    }
    assert_eq!(s.recover_connection("receiver-1").unwrap(), 0);
}

#[test]
fn four_user_categories_cover_pending_gallery_before_pagination() {
    let t = Temp::new();
    let mut sender = Sender::open(&t.0).unwrap();
    let mut received_ids = Vec::new();
    for (index, processing) in [
        ProcessingState::Pending,
        ProcessingState::Complete,
        ProcessingState::Failed,
        ProcessingState::NotRequested,
    ]
    .into_iter()
    .enumerate()
    {
        let mut a = asset();
        a.source_id = format!("category-{index}");
        if index < 3 {
            a.metadata
                .insert("source_ref".into(), "folder:synthetic".into());
        }
        let sources = BTreeMap::from([(
            a.resources[0].sha256.clone(),
            "opaque-native-resource-reference".into(),
        )]);
        let job = sender.enqueue("receiver-1", a, sources).unwrap();
        let claimed = sender.claim("receiver-1", 0).unwrap().unwrap();
        assert_eq!(claimed.id, job.id);
        let mut receipt = status(&claimed, true);
        receipt.processing = processing;
        sender.acknowledge(&claimed.attempt(), &receipt).unwrap();
        received_ids.push(job.id);
    }
    let mut a = asset();
    a.source_id = "queued-category".into();
    let queued = sender
        .enqueue(
            "receiver-1",
            a,
            BTreeMap::from([(
                digest(b"0123456789"),
                "opaque-native-resource-reference".into(),
            )]),
        )
        .unwrap();
    let query = |state| JobQuery {
        after: 0,
        after_value: None,
        limit: 1,
        receiver: Some("receiver-1"),
        state: Some(state),
        sort: "added",
        descending: true,
    };
    let first = sender.browse(query("active")).unwrap();
    assert_eq!(
        first.iter().map(|j| j.id).collect::<Vec<_>>(),
        vec![queued.id]
    );
    let mut continuation = query("active");
    continuation.after = first[0].id;
    continuation.after_value = first[0].sort_value;
    let second = sender.browse(continuation).unwrap();
    assert_eq!(
        second.iter().map(|j| j.id).collect::<Vec<_>>(),
        vec![received_ids[3]],
        "Unconfirmed legacy gallery rows are unfinished, not saved"
    );
    continuation.after = second[0].id;
    continuation.after_value = second[0].sort_value;
    assert_eq!(
        sender.browse(continuation).unwrap()[0].id,
        received_ids[0],
        "Filtering precedes pagination across complete and failed rows"
    );
    assert_eq!(
        sender.browse(query("attention")).unwrap()[0].id,
        received_ids[2]
    );
    assert_eq!(
        sender.browse(query("saved")).unwrap()[0].id,
        received_ids[1]
    );
    assert_eq!(
        sender
            .browse_source(query("active"), Some("folder:synthetic"))
            .unwrap()[0]
            .id,
        received_ids[0]
    );
    let summary = sender.summary("receiver-1").unwrap();
    assert_eq!(summary["total"], 5);
    assert_eq!(summary["received"], 4);
    assert_eq!(summary["published"], 1);
    assert_eq!(summary["publication_failed"], 1);
    drop(sender);
    let sender = Sender::open(&t.0).unwrap();
    assert_eq!(sender.browse(continuation).unwrap()[0].id, received_ids[0]);
}

#[test]
fn publication_time_is_real_persisted_and_not_a_receipt_date() {
    let t = Temp::new();
    let mut s = Sender::open(&t.0).unwrap();
    let j = add(&mut s);
    let running = s.claim("receiver-1", 0).unwrap().unwrap();
    let mut receipt = status(&running, true);
    receipt.processing = ProcessingState::Pending;
    s.acknowledge(&running.attempt(), &receipt).unwrap();
    assert_eq!(s.publication_time(j.id).unwrap(), None);
    receipt.processing = ProcessingState::Complete;
    s.observe_processing(j.id, &receipt, 2).unwrap();
    let observed = s.publication_time(j.id).unwrap().unwrap();
    assert!(observed > 0);
    s.observe_processing(j.id, &receipt, 3).unwrap();
    assert_eq!(s.publication_time(j.id).unwrap(), Some(observed));
    drop(s);
    assert_eq!(
        Sender::open(&t.0).unwrap().publication_time(j.id).unwrap(),
        Some(observed)
    );
}

#[test]
fn historical_publication_without_a_date_stays_unknown_when_observed_again() {
    let t = Temp::new();
    let mut s = Sender::open(&t.0).unwrap();
    let j = add(&mut s);
    let running = s.claim("receiver-1", 0).unwrap().unwrap();
    let mut receipt = status(&running, true);
    receipt.processing = ProcessingState::Complete;
    s.acknowledge(&running.attempt(), &receipt).unwrap();
    drop(s);
    // Simulate a complete observation recorded by a version without dates.
    let conn = rusqlite::Connection::open(t.0.join("sender.sqlite3")).unwrap();
    conn.execute("DELETE FROM publication_times", []).unwrap();
    drop(conn);
    let mut s = Sender::open(&t.0).unwrap();
    assert_eq!(s.publication_time(j.id).unwrap(), None);
    s.observe_processing(j.id, &receipt, 3).unwrap();
    assert_eq!(s.publication_time(j.id).unwrap(), None);
}

#[test]
fn historical_completion_requires_gallery_for_exact_members_and_latest_attempt() {
    let t = Temp::new();
    let mut sender = Sender::open(&t.0).unwrap();
    let maintenance_path = t.0.join("maintenance.sqlite3");
    let maintenance = rusqlite::Connection::open(&maintenance_path).unwrap();
    maintenance.execute_batch("CREATE TABLE history_members(receiver TEXT,source TEXT,revision TEXT);
        INSERT INTO history_members VALUES('receiver-1','native:42','1'),('receiver-1','missing','1'),('receiver-2','native:42','1');").unwrap();
    let job = add(&mut sender);
    let published = |sender: &Sender| {
        sender
            .history_published(&maintenance_path, "receiver-1")
            .unwrap()
    };
    assert_eq!(
        published(&sender),
        0,
        "Prepared originals are not saved photos"
    );
    let running = sender.claim("receiver-1", 0).unwrap().unwrap();
    let mut receipt = status(&running, true);
    sender.acknowledge(&running.attempt(), &receipt).unwrap();
    assert_eq!(published(&sender), 0, "Receipt is not gallery publication");
    receipt.processing = ProcessingState::Pending;
    sender.observe_processing(job.id, &receipt, 0).unwrap();
    assert_eq!(published(&sender), 0);
    receipt.processing = ProcessingState::Failed;
    receipt.processing_error = Some("conversion_required".into());
    sender.observe_processing(job.id, &receipt, 1).unwrap();
    assert_eq!(published(&sender), 0);
    assert_eq!(
        sender.summary("receiver-1").unwrap()["conversion_required"],
        1
    );
    assert_eq!(
        sender.summary("receiver-2").unwrap()["conversion_required"],
        0
    );
    receipt.processing = ProcessingState::Complete;
    receipt.processing_error = None;
    sender.observe_processing(job.id, &receipt, 2).unwrap();
    assert_eq!(published(&sender), 1, "Unknown members remain unfinished");
    assert_eq!(
        sender
            .history_published(&maintenance_path, "receiver-2")
            .unwrap(),
        0
    );
    maintenance
        .execute(
            "UPDATE history_members SET revision='2' WHERE source='native:42'",
            [],
        )
        .unwrap();
    assert_eq!(
        published(&sender),
        0,
        "A previous revision cannot finish this snapshot"
    );
    maintenance
        .execute(
            "UPDATE history_members SET revision='1' WHERE source='native:42'",
            [],
        )
        .unwrap();
    let mut repeated = asset();
    repeated
        .metadata
        .insert("backupduck_rebackup_id".into(), "repeat-history".into());
    sender
        .enqueue(
            "receiver-1",
            repeated,
            BTreeMap::from([(digest(b"0123456789"), "fixture".into())]),
        )
        .unwrap();
    assert_eq!(
        published(&sender),
        0,
        "A previous attempt cannot finish the latest repeat"
    );
}

#[test]
fn conversion_summary_counts_all_observed_failures_with_receiver_and_source_scope() {
    let t = Temp::new();
    let mut sender = Sender::open(&t.0).unwrap();
    let mut observe = |receiver: &str, source: &str, id: usize, processing: ProcessingState| {
        let mut a = asset();
        a.source_id = format!("photo-{id}");
        a.metadata.insert("source_ref".into(), source.into());
        sender
            .enqueue(
                receiver,
                a,
                BTreeMap::from([(digest(b"0123456789"), "fixture".into())]),
            )
            .unwrap();
        let running = sender.claim(receiver, 0).unwrap().unwrap();
        let mut receipt = status(&running, true);
        receipt.processing = processing;
        receipt.processing_error = Some("conversion_required".into());
        sender.acknowledge(&running.attempt(), &receipt).unwrap();
    };
    for id in 0..205 {
        observe("receiver-1", "library", id, ProcessingState::Failed);
    }
    observe("receiver-1", "folder", 205, ProcessingState::Failed);
    observe("receiver-2", "library", 206, ProcessingState::Failed);
    // An old error string does not turn a nonfailed observation into a failure.
    observe("receiver-1", "library", 207, ProcessingState::Pending);
    observe("receiver-1", "library", 208, ProcessingState::Complete);
    observe("receiver-1", "library", 209, ProcessingState::NotRequested);
    let summary = sender.summary("receiver-1").unwrap();
    assert_eq!(summary["total"], 209);
    assert_eq!(summary["received"], 209);
    assert_eq!(summary["published"], 1);
    assert_eq!(summary["publication_failed"], 206);
    assert_eq!(summary["conversion_required"], 206);
    assert_eq!(
        sender
            .summary_source("receiver-1", Some("library"))
            .unwrap()["conversion_required"],
        205,
        "The aggregate is not bounded by a displayed page of jobs"
    );
    assert_eq!(
        sender.summary_source("receiver-1", Some("folder")).unwrap()["conversion_required"],
        1
    );
    assert_eq!(
        sender.summary("receiver-2").unwrap()["conversion_required"],
        1
    );
    assert_eq!(sender.summary("unknown").unwrap()["conversion_required"], 0);
    drop(sender);
    let sender = Sender::open(&t.0).unwrap();
    assert_eq!(sender.summary("receiver-1").unwrap(), summary);
}
