# Folder backup on Mac

Folder sources are a desktop capability. The iOS app continues to use PhotoKit;
there is no folder picker, watcher or folder-source Rust dependency in its build.

## Use

1. Open **Folders**, then **Add Folder…**. Select a folder on the Mac,
   an external drive or an SD card. Subfolders are included.
2. Choose everything (the existing counted photos and new photos) or only photos
   added from now on. The count and size appear when counting finishes.
3. New photos follow the global **Auto Backup** preference. Existing photos can
   be included later with **Back Up Remaining Photos** or **Back Up Selected**.
   Selection registers durable receiver- and revision-scoped intent immediately.
   Global pause still applies; these actions do not resume paused transfers.
4. Browse recent photos by folder, or choose **All Photos** in capture-date order.
   Search finds indexed file and subfolder names. The four backup filters use
   core facts: All, Not Backed Up, Needs You and Recently Backed Up (seven days).
   Double-click a photo to open its viewer window and information inspector.

Manage folders in **Settings › Folders**. Stopping a folder stops future checks
and preparation; it does not cancel prepared transfers or delete originals or
anything on the Pixel. A verified receipt and saving to the Pixel's Photos are
independent facts; neither confirms Google Photos cloud backup.

## Automatic checks and external drives

FSEvents provides debounced file-change hints on its own dispatch queue. Affected
parent directories are rescanned recursively; overlapping hints are coalesced.
Dropped events and root changes cause a full check. App startup, drive mount and
wake also cause a full check. A periodic full scan repairs missed notifications;
if the native stream cannot start, periodic checking runs more frequently.

This works while the application is running, including with its window closed.
Quitting the application stops work; relaunch catches up. Offline or inaccessible
sources retain their inventory and receipts. They are not interpreted as deleted
remote files. Read-only security-scoped bookmarks restore access across launches.

## Media and dates

The initial format allowlist is JPEG, HEIC/HEIF, PNG, GIF, WebP, TIFF, MOV, MP4 and
M4V. The receiver can impose further format limits. Non-media files, hidden items,
symbolic links and nested Unix mount points are not traversed. RAW files and
arbitrary document backup are not supported.

An exported Apple Live Photo can be grouped when its photo and MOV have the same
basename and matching Apple pairing identifiers. Same-name files alone are never
proof of a motion pair. Motion resources use the existing atomic asset protocol
and receiver packaging. Folder exports without recoverable burst relationships
are transferred as individual files; their original bytes remain unchanged.

ImageIO and AVFoundation read embedded capture dates on Mac. EXIF UTC offsets are
applied when available; timezone-free EXIF dates use the Mac's local timezone.
Missing capture dates fall back to the file modification time, with `date_source`
recorded in task metadata. Original metadata is never edited by the source adapter.
Folder hierarchy is not mapped to Google Photos albums.

## Storage and identity

`backupduck-folder-source` owns a SQLite inventory, bounded directory work queue,
stability window, source identity and per-receiver submission records. Scans do
not hash or copy the full library. Only current eligible assets are copied into
owned staging, checked against their indexed revision and identity, then hashed
and passed to the existing Rust queue. Large assets wait when staging allowance is
insufficient; temporary deferral lets other assets proceed. Increase the shared
cache budget if a single asset is larger than it. Failed media inspection can be
reviewed in the source page and retried with **Back Up Existing Files**.

On Unix, file identity uses the inode within the registered source/volume;
renames within the source do not alone require retransmission. Content changes
produce new revisions. Repeating Back Up retains actual receiver submission
records and skips unchanged files already queued or received. It removes only the
initial exclusion baseline and retries skipped media; it does not force re-upload.
Changing receivers permits a separate backup to the new target. Hard links to the same file share this identity. Across
sources, semantic/photo similarity deduplication is not promised.

Sources never become cache-owned paths. Existing cache reclamation removes only
app-owned verified staging. Folder deletion never propagates to the receiver.
Existing PhotoKit source IDs, revisions and receipts are unchanged.

## Build boundary and validation

Mac enables `backupduck-native/folder-source`; it is disabled by default. iOS and
Android builds explicitly disable default features, and enabling this feature for
mobile targets is a compile error. `scripts/check-folder-isolation.py` verifies
mobile dependency trees. Platform-independent transfer and queue crates do not
depend on the folder scanner.

Validation includes bounded/incremental/subtree scans, restart, rename, offline
sources, baseline-only import, permanent/temporary skips, safe path containment,
real TLS motion-resource transfer, repeat submission, staging reclamation, native
EXIF timezone handling, real FSEvents and mobile build isolation. Physical external
hardware and a 12 TB dataset still require user testing; synthetic tests do not
establish their performance or Google Photos cloud completion.

## Browse facts and unsupported formats

Folder sections show the original name, location and one core-backed sentence,
ordered by unavailable drive, attention, in-flight count/size, remaining photos
and saved-to-Photos count. Disconnected folders retain their inventory and are
dimmed; returning drives resume through the existing watcher/check mechanism.

Unsupported photo-like formats are persisted by extension separately from the
supported inventory. RAW camera extensions and unsupported image formats count;
ordinary documents do not. Counts survive restart, scoped checks and drive
removal. An info popover explains the formats and offers Show in Finder.

The section menu offers Back Up Remaining Photos, Show in Finder, Folder
Settings and Stop Backing Up This Folder. Command/Shift selection uses the
native collection. The browser displays bounded recent samples per folder;
All Photos and search page the full indexed inventory. Thumbnail work uses the
existing bounded, cancellable file-thumbnail pipeline and the library cells.

Media inspection failures remain revision-scoped core facts. Selecting an
unbacked photo records its retry intent without widening an excluded initial
baseline. Retry preserves receiver ownership, stability checks, capacity limits,
existing receipts and queued work. Failed submission preserves the selection.

The menu-bar status item already exists (`MenuBarExtra` / `MacStatusMenu`). It
shows transfer status and offers open-window, pause/resume, settings, update and
quit actions. Closing the window leaves the app running; quitting stops it.

## List display preferences

Mac Settings → Backup → List appearance contains **Show photo and video
thumbnails**, enabled by default. This applies to transfer/file lists and compact
transfer previews; it does not disable the photo library grid. Turning it off
cancels visible-row thumbnail requests and uses media icons. File previews use
Quick Look Thumbnailing, with at most four active requests, at most 128 pending
requests and a 32 MiB / 256-item in-memory cache. Requests are cancelled when rows
leave the screen. The cache is keyed by source, current path, indexed revision and
size; source files are never cropped or rewritten. System thumbnail generation
still performs disk reads and decoding, especially for videos and cold caches.

Folder-transfer previews look up the task's recorded identity through the folder
inventory, including tasks created before this update and renames discovered by
later scans. The primary asset is selected explicitly for Live Photos. Missing,
changed, removed or inaccessible originals fall back to icons; no cached staging
file is retained merely for a preview. Symbolic links are not followed.

The Folders photo grid is independent of the list-thumbnail preference. Each
view/filter retains its scroll position and selection. Indexed capture dates
come from ImageIO/AVFoundation with an explicit file-modification fallback;
metadata reads do not register transfer work or alter original files.

## Folder rules

Settings › Folders contains each folder's **File Rules** sheet. Its two native
token fields are **Skip these** and **Only back up these (empty means
everything)**. Each token is a pattern matched against indexed paths with case
sensitivity. A folder token ending in `/`, such as `Drafts/`, includes all its
descendants.
An empty include list accepts all supported media; matching any exclude wins.
`*` and `?` do not cross `/`; `**` crosses directories (including zero levels),
with character classes and brace alternatives supported. Examples:
`**/*.{jpg,JPG,png}` includes those formats at all levels; `Trips/**` excludes
all descendants of Trips. Leading absolute paths and `..` components are rejected.
Patterns are compiled by the Rust globset library, not a custom matcher.

Rules are applied before media inventory insertion. Excluded directories may
still be traversed to discover eligible descendants; rules do not promise to
eliminate enumeration costs. The file list reflects the accepted inventory,
while failed-file history remains available separately until retried or ignored.
Saving valid rules hides the previous inventory until a requested full scan
rebuilds it. Invalid rules preserve the current inventory and configuration.
Receiver receipts, source identities and initial baselines are preserved.
Newly included files without a baseline/receipt are eligible if backup is enabled.
Rules cannot enable unsupported formats or alter already queued transfers.

Native preparation rechecks both rules and user dismissals for every resource.
An exported Live Photo is grouped only if both photo and video are eligible;
otherwise its allowed component is processed individually. Filtering cannot
silently include an excluded companion. Configuration and user dismissals
survive restart and stay isolated to their source.

The rules sheet explains that changes apply to later checks and do not alter
photos already in the Pixel's Photos. Invalid input remains available for
correction. File rules do not enable unsupported formats.
