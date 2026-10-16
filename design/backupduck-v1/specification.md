# Visual and interaction foundations

The 0.3.0 interface baseline covers Apple senders and the Android receiver.
The `backupduck-v1` directory is a stable token/prototype source path, not an
application release number. Current component rules override historical mockups.

## Visual language

Use warm neutral surfaces, blue primary actions and restrained duck-yellow brand
accents. Semantic success, attention and failure colors require text and icons.
Yellow decorates brand/empty-state illustrations, a labeled storage category,
or a quiet unseen-feature discovery mark;
it does not stand in for operational status.

Colors come from `tokens.json`. Native hosts use system fonts and platform icons.
Mobile body/supporting text generally uses 16/13; desktop uses 14/12. Counts and
progress use monospaced digits. Spacing follows 4/8/12/16/24/32. Wrapped text and
accessibility sizes grow naturally rather than being clipped.

Preference-row minima are 52 pt on iPhone and 48 pt on Mac, through shared
platform metrics. Android interactive targets are at least 48 dp. These are
platform density contracts, not interchangeable CSS pixels. See
[component rules](../ui-content-rules.md) for section geometry and alignment.

## Platform surfaces

Apple navigation, toolbars and standard overlays use native system materials.
Content, file rows, errors and progress stay solid. Reduced transparency, enhanced
contrast and unsupported systems use opaque fallbacks with the same information.
Android and browser interfaces use solid surfaces without real-time blur.
Prototype CSS is illustrative; it does not implement native material optics.

Phone senders use Library, Backup, Receiver and Settings navigation. Mac sources
include the system Photos library and folders. The receiver uses Receive,
Transfers, Storage and Settings. Browser management uses overview/history/storage
and settings. System permission, camera, picker, sharing and installation UI
remain actual platform interfaces.

## Actions and information

A task context has one primary action. Keep selection count and backup actions
visible outside an unbounded scrolling list. Show the count once. Use switches
for persistent Boolean settings; use checkboxes for selecting independent items.
Secondary actions and low-frequency menus do not compete with primary work.

Automatic discovery, an existing-media scan and pausing the current queue are
separate controls. Selection confirmation persists intent and closes on successful
registration; originals prepare in the persistent task workflow. Cancellation
preserves the parent context. Failure preserves drafts, selection and a recovery
path. Help is read-only and has one consistent entry from Settings.

Shared settings groups are Device identity, Display and language, Local storage,
Diagnostics, and Help and About. Update controls belong in About on platforms
with an in-app updater. iOS uses its distribution channel rather than an invented
in-app update workflow. Desktop layout may use columns; phone layout stays linear.

## Task semantics

| State | Confirmed fact | Recovery or next step |
| --- | --- | --- |
| Queued/preparing | Durable work exists; transfer is incomplete | Inspect tasks; pause or retry as applicable |
| Receiving | Actual byte transfer is in progress | Show verified progress where available |
| Received | Original resources are durable and verified on receiver | Wait for or inspect gallery processing |
| Saved | Phone-gallery publication succeeded | Cloud status remains independent |
| Failed | The named stage failed | Preserve originals and expose specific retry |
| Thermal hold | Receiver protection holds admission | Show actual temperature/protection conditions |
| Offline/source unavailable | Device or source access is unavailable | Preserve configuration and pending work |

Never infer cloud upload from receipt or gallery publication. Missing times,
source dates, temperature and storage remain unknown; receipt time must not
replace capture time. Overview, rows, detail and status controls use the same
mapping. Retry submission is not success. Preparation is not byte transfer.

## Files, previews and persistence

Library browsing uses local media first. PhotoKit may load iCloud previews automatically under system Photos access and network policy. Browsing remains separate from backup authorization. Selection, sorting, pagination, expanded folders and scroll
positions survive background state updates. Native grids/lists are virtualized
with stable identities and bounded thumbnail work.

Folder include rules select supported media, while exclusion rules take priority.
Rules are relative to the source. Saved rules do not modify original files;
missing volumes retain source configuration and offer recovery. Existing-media
scope freezes a run; automatic discovery handles subsequent changes.

Brand derivatives preserve the original AppIcon shape. Native menu/status marks
use transparent monochrome masks rather than full launch tiles or redrawn logos.
See [brand resources](../../assets/brand-notes.md).

## Verification boundary

Prototypes and synthetic references are not native or physical-device acceptance.
Follow [UI change checks](../iteration-checklist.md), compare actual rendered
windows and retain explicit scope for performance, accessibility and real media
verification. Never publish personal acceptance logs as design specifications.
