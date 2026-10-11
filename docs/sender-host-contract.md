# Shared sender and native host contract

The shared Rust engine is the authority for preparation and transfer state.
Native hosts supply platform access and execution without inventing a second
queue, concurrency policy or success model.

| Responsibility | Authority | Native adaptation |
| --- | --- | --- |
| Asset/request identity, revision and receiver ownership | Rust core/native/sender | Stable media identifiers, revisions and resource access |
| Preparation order, retry and completion | Rust native maintenance | Export originals and report access, capacity or source errors |
| Transfer claims, concurrency and attempt generations | Rust sender | Execute claimed requests through the appropriate OS runtime |
| Pause, retry and durable byte confirmation | Rust sender/native | Lifecycle events and typed execution results |
| Receipt and receiver processing observations | Rust sender/native | Render confirmed facts and observe results |
| Permissions, credentials and OS scheduling | Native host | Platform APIs and explicit capability limits |

## Execution adapters

Apple hosts execute immutable Rust-planned requests with OS-managed URLSession
and reconcile platform tasks after restart. A Rust network future is not expected
to survive iOS suspension. Foreground-capable hosts can use `run_sender_batch`;
claim eligibility and compatibility fallback remain shared policy.

## Durable preparation

`register_preparations` stores request identity, receiver, revision, capture time
and repeat intent. `source_preparations` returns eligible work; `pending_sources`
provides the Apple-compatible view. `source_result` records completion or failure;
`retry_sources` restores the selected receiver's preparation work.

Hosts persist access descriptions before core registration and reconcile the
handoff by stable identity. Independent databases are not a cross-store atomic
transaction. Replay cannot revive completed work or redirect it to another target.
Metadata-only submission does not wait for original export inside a dialog.

## Source membership

Existing-library scans bind immutable snapshots to receiver and run identity.
Pause/resume preserves that binding. Replaying an acknowledged batch must retain
its exact membership rather than include newly discovered media. Missing snapshots
must not be silently rebuilt from the current library.

New-media discovery uses PhotoKit tokens, MediaStore generations or filesystem
snapshots as platform evidence. Enable/disable boundaries and receiver changes
must preserve their original context. Capture time is metadata, not a substitute
for discovery membership. Unknown boundaries remain unknown.

## State and UI

Preparation and transfer are separate stages. The UI distinguishes queued work,
byte receipt, phone-gallery publication and unknown cloud upload. Counts and
queries filter before pagination. Result observation must not block behind
original export. Background updates preserve list identity and selection.

This contract applies to future hosts as well as current Apple hosts. Android and
Windows sender completion, background execution and cross-device coverage must
be established independently; a shared API or matching prototype is not proof.
