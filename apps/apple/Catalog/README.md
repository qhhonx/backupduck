# Apple design catalogs

`BackupDuckCatalog` exists for iPhone (`apps/ios`) and Mac (`apps/macos`). Each
renders the production pages from scenario data. They are review targets only:
they are never archived or distributed. See the design catalog section of
`design/constitution.md`. The Pixel receiver catalog is described in
`apps/android/app/src/catalog/README.md`.

## How it works

### Settings bottom, About and feedback

`settings.bottom`, `settings.about` and `settings.feedback` use the current
production settings on both Apple hosts. The iPhone
bottom scenarios scroll to About; on Mac the list column keeps the footer below
its categories. Check English and Simplified Chinese, light/dark, narrow windows
and accessibility text sizes. About uses Version as the leading title and the
release version as the trailing secondary value. The author card appears only
when approved content is supplied. It links the website privacy page and
provides the source and license. Direct Mac builds show update status below the
title and open a separate update detail with status, Check for Updates and
Automatic Updates. Store builds show only the version row. Web rows use primary
text with an external arrow; pushed iPhone rows keep the system disclosure. Mac
list rows that select a detail pane have no trailing glyph. Rate BackupDuck uses
the external arrow on both hosts. The existing `settings.updates.ready` and
`settings.updates.unavailable` fixtures review the direct-update controls.

`settings.advanced.cache-failure` reviews temporary-file cleanup recovery on
both Apple hosts. Press Clear Now to show the localized storage failure in the
shared plain-text group footer, then press Clear Now again to restore the normal
explanation and reduce the size by 1 MiB. No separate Retry button
appears; thumbnail cleanup remains independent. The successful scripted response
uses `updates` to publish the new `storage_status` value before the production
model refreshes it; repeated reads before cleanup retain the original size.

The production `settings.feedback` scenario opens the user group directly when
the row is activated, with an external arrow and no one-item menu.
`settings.feedback-reserved` automatically opens the two-item native menu from
the same full-row trigger. This menu row keeps the iPhone chevron and has no
trailing glyph in the Mac list.
Choose Email to prepare a synthetic diagnostics file; inspect its Quick Look
preview before opening the mail composer. Cancel and retry without losing the
file. iPhone uses MessageUI when mail is configured; otherwise it offers mailto
and the system file share sheet with manual attachment instructions. Mac uses
NSSharingService's email composer. Neither path sends automatically. Mail setup,
attachment delivery and external destinations need separate system acceptance.

### Mac status menu (A0, A11)

Choose the `menu.backing-up`, `menu.paused`, `menu.caught-up`, `menu.offline`
or `menu.saving` scenario from the Mac catalog's Backup section. These inherit
the hub fixtures; receipt is never described as saving to Photos. They also
launch directly with `-scenario menu.backing-up`. To review another existing
hub fixture's menu items, add `-status-menu items` to its launch arguments.
The review page lists the production menu items and opens the same items in a
system menu from the template-icon button. Open BackupDuck, Settings and Quit
are inert in this review; Pause uses the synthetic core only. The application
menu Settings item (⌘,) uses the same command as production and opens the
single Catalog main window at Settings, including after minimize or close. In the app,
Settings and Command-comma navigate to Settings in the main window.
Repeat with `-appearance light` / `dark` and `-AppleLanguages '(zh-Hans)'`.
Check the disabled first line, the single Pause/Resume item, separators, shortcuts
and the static activity symbol; the idle icon uses the exported duck template.

### Apple notification preferences and Mac Overview routes

`settings.notifications.not-determined`, `.denied` and `.authorized` render the
shared notification preference with injected system authorization. Allow first
opens `DuckSheetLayout`; its confirmation simulates one system request. Denied
records the app-specific settings URL, and authorized edits an in-memory switch.
These fixtures never ask for system permission or open System Settings.
Both Apple catalogs render these states. The iPhone catalog accepts
`-measure-rows` to write native visible cell frames and simulated permission
counters to `Documents/catalog-row-measurements.json`; `-large-text` uses the
largest standard Dynamic Type size without changing device settings.

`notifications.route.needs-you`, `.photo` and `.overview` queue a receiver-scoped
route before workspace startup. Add `-route-timing warm` and activate Simulate
notification to exercise the observer after startup. Add
`-route-receiver former-pixel` to check that an old receiver is ignored.
Photo routes carry `source_id`; aggregate conversion notices open Needs You,
and other aggregate notices open Overview. This reviews routing only, not real
system delivery or notification taps.

`hub.needs-you-navigation` opens Overview with mixed records. Needs You requests
only attention records, including subsequent pages; recent mosaic photos use
the shared viewer. `folders.viewer-received` opens the mounted Folders grid's
received-but-not-published photo with the shared A8 inspector. Receipt has its
recorded time; publication has no invented completion or time.

Mac `-snapshot` captures the parent window while a sheet is attached. Each PNG
has adjacent notification-state JSON, core-command JSONL and unscripted-command
text for inspecting the synthetic boundary.

### One photo's information (A8)

Launch `-scenario photo.info -photo-info panel` on iPhone, or
`-scenario photo.info -photo-info inspector` on Mac. Both use the production
viewer and information component with a catalog-only synthetic asset; PhotoKit
access is unnecessary. `-photo-info fallback` opens the unavailable-source
presentation. Use `photo.info-failed` for the single transfer Retry action, or
`photo.info-unknown-times` to verify that missing event times stay absent.
The Mac inspector's toolbar toggle and View → Show Info (⌘I) remain active.

The sender model takes everything outside the app process from
`BackupEnvironment` (`apps/apple/Shared/BackupEnvironment.swift`):

| Provider | App | Catalog |
| --- | --- | --- |
| `core` | `NativeCore`, the linked Rust library | `ScenarioCore`, which answers from the scenario |
| `credentials` | `SystemKeychain` | `ScenarioCredentials`, kept in memory |
| `discoversReceivers` | Bonjour on | off |
| `usesPhotoLibrary` | PhotoKit thumbnails and change observers | off, so the catalog never reads real photos or prompts; on only in iPhone library scenarios |
| `requestPhotoAccess` | The system photo prompt | granted, without a prompt |
| `sampleThumbnail` | none | optional local pool photos with procedural landscape fallback (`SampleImages.swift`); off in library scenarios |
| `libraryCount` | PhotoKit's asset count | 12,384 |

Each catalog installs its providers at launch. `Scenario.makeModel` then creates
a new `BackupModel` in a temporary folder for every scenario run, so the
production model and pages run unchanged:

- **iPhone** shows the page in the production tab chrome (`IOSAppTab`). The info
  button opens the scenario sheet.
- **Mac** shows the production `MacWorkspace` window at the scenario's
  destination. The controls at the bottom right open the scenario details,
  restart the scenario or return to the list.

Restarting a scenario replays it from launch. Closing it stops the model.

A core command that the scenario does not script fails with
`catalog_unscripted`. The scenario details list these commands. Script them
before reviewing a page, so that a page never shows a state that nobody
specified.

## Scenario files

Both catalogs read the same JSON files in `Scenarios/`:

```json
{
  "id": "receiver.offline",
  "page": "settings",
  "step": "devices",
  "title": "Paired, receiver not reachable",
  "extends": "base-paired",
  "pairing": { "version": 2, "receiver_id": "…", "endpoint": "https://192.0.2.20:8484", "certificate": "…", "token": "…" },
  "files": { "photo-library-changes.json": { "enabled": true, "receiverID": "…", "pending": [] } },
  "core": {
    "check_pairing": { "error": "network" },
    "open_sender": [ { "error": "storage" }, { "value": null } ],
    "history_status": { "value": null, "delay": 2 }
  },
  "expect": [ "What the reviewer should see." ],
  "actions": [ { "action": "Tap Retry", "result": "What happens next." } ]
}
```

- `page` is a root destination: `library`, `backup` or `settings`,
  `connect` for the connect sheet on its own (Mac: the code for the Pixel to
  scan; iPhone: the scanner), or `onboarding` for first run, with `step` naming the screen to start on
  (`welcome`, `install`, `connect`, `connected`, `photos`, `choose`, `first`). A
  file without `page` is a base that other scenarios extend.
- `extends` names another scenario. The base's `core` answers and `files` are
  merged with the child's, and the child wins. Other fields are replaced.
- `core` maps a command's `op` to an answer: either `value` (any JSON) or `error`
  (a core error code), with an optional `delay` in seconds. In a list, answers
  are used in order and the last one repeats. Use a list for continuity: fail,
  then recover.
- An answer may carry `when`, a map of command fields such as
  `{"state": "attention"}`. Answers with `when` are chosen by matching the
  command, not in order, and an answer without `when` in the same list is the
  fallback. The records page asks `backup_tasks` per category this way.
- `records` (with `page: "backup"`) opens the hub's backup history on iPhone and
  the history destination on Mac.
- `files` are written into the model's folder before it opens. They hold host
  state such as photo discovery.
- `expect` and `actions` state what the state means and what each action does.
  A screenshot that renders does not prove that it means the right thing.

Use synthetic data only: documentation addresses (`192.0.2.0/24`), invented
names and no real identifiers.

## Running

Build in Release, the same configuration used to judge motion:

```bash
xcodebuild -project apps/ios/BackupDuck.xcodeproj -scheme BackupDuckCatalog -configuration Release -destination 'platform=iOS Simulator,name=iPhone 18 Pro' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

```bash
xcodebuild -project apps/macos/BackupDuck.xcodeproj -scheme BackupDuckCatalog -configuration Release build
```

Both catalogs accept `-scenario <id>`, which opens one scenario directly. The Mac
catalog also accepts `-appearance dark|light` and `-snapshot <path>`. With
`-snapshot`, it writes its window to a PNG after `-snapshot-delay` seconds
(default 9), writes the unscripted commands next to the image, and quits. This
needs no screen recording permission. The image does not show system materials
such as the sidebar selection; judge those in the live window.

The Mac catalog is compiled as the App Store variant (`BACKUPDUCK_APP_STORE`), so
it needs no Sparkle framework. Its update settings show the store note.

## Coverage

- **Settings** and **Connect** have scenarios on both catalogs. The five
  `receiver.*` IDs are retained: online, offline, recovering and unpaired states
  open Settings › Devices; authentication rejection opens the current Connect
  flow (the iPhone reconnect explanation). Their base inheritance and scripted
  connection facts remain unchanged.
- **Backup** (iPhone) has `hub.*` scenarios for every hub state: caught up,
  still saving to Photos, backing up with earlier photos, paused, not paired, and
  each problem card (Pixel unreachable, rejected, Pixel full, iPhone full, photo
  access off, Live Photos that need conversion). `photo_access` (`full`,
  `limited`, `denied`, `undetermined`) sets what the hub reads as photo access.
- **Backup history** has `records.*` scenarios: with problems of every cause
  across several days, with nothing to fix, and empty.
- **Library** (iPhone only) has `library.*` scenarios and `hub.library`. They
  set `library` (and optionally `view`: `notBackedUp`, `needsYou`, `recent`),
  which reads the Simulator's photo library and answers `received_sources`,
  `source_states`, `library_source_states`, `backup_tasks`, `backup_summary` and `jobs` from its real
  photo identifiers (`LibraryScenario.swift`): the newest few still arriving,
  most older ones received (including pending, failed and unknown publication),
  a few needing the user, 30 received in the last
  week. Run them on a Simulator that holds only a synthetic library: create one,
  add generated images with `xcrun simctl addmedia`, and grant photo access with
  `xcrun simctl privacy <device> grant photos app.backupduck.catalog`. The Mac
  catalog skips library scenarios, because on a Mac they would read the
  reviewer's own Photos library.
- A scenario with `now_ms` has its `*_ms` and `sort_value` timestamps shifted by
  the time since that moment, so relative dates (Today, Yesterday) hold on any
  review day.
- **First run** (iPhone) has `onboarding.*` scenarios. `onboarding.first` plays
  the first-photo flight once its scripted summary reports a saved photo.
  `onboarding.photos` and `onboarding.scope` cover the permission explanation
  and backup decisions. `onboarding.first-photo-sending`,
  `onboarding.first-photo-slow-unreachable`, `onboarding.first-photo-slow-limited`,
  `onboarding.first-photo-none`, `onboarding.first-photo-failed` and
  `onboarding.first-photo-landed` use the production waiting/recovery projection.
  Slow scenarios seed a start time more than 20 seconds ago; sending never
  invents byte progress or runs the flight before observed publication.
  `onboarding.resume-mid-flow` retains its isolated first-run defaults across
  termination and relaunch. Advance from Photos to scope, change the switch,
  then relaunch the same scenario to verify both step and decision.
  `onboarding.background-landing` also retains intent to check the deferred
  hub invitation and its once-only dismissal. `-onboarding-session <name>`
  selects a separate fixture record without removing an existing one.
  Other first-run scenarios start with fresh presentation intent each launch.

Both catalogs always use current production pages. `-proposed` is accepted as
an ignored compatibility argument; the Design picker has been removed. Mac Photo Library browsing uses `library.synthetic`;
`library.system-background` reviews its no-access container. Every Mac scenario
keeps PhotoKit disabled, including permission actions and models mounted behind
other destinations. iOS library comparisons still use the existing synthetic
Simulator photo library. In the Simulator, the pairing sheet shows the
camera-unavailable state.

Duck poses and step marks come from `Illustrations.xcassets`, generated by
`scripts/export-illustrations.py` from `assets/illustrations`.


## Optional local photo pool

Both Apple catalogs accept `-mediaDir <absolute path>` at launch. Point it at the
shared, git-ignored `build/catalog-media/` directory; by default no pool is used.
For example, from the repository root:

```bash
xcrun simctl launch booted app.backupduck.catalog -scenario hub.backing-up -mediaDir "$PWD/build/catalog-media"
open -n <catalog-build>/BackupDuckCatalog.app --args -scenario folders.sections -mediaDir "$PWD/build/catalog-media"
```

The Simulator reads this host directory directly. Restart the catalog after
changing the pool or launch arguments. Library scenarios that use the Simulator's
Photos library continue to use PhotoKit and ignore the pool.

`manifest.json` has a `photos` array in stable order. Each entry names a
pool-relative `file`, an ISO `taken` date and optional `hero` metadata:

```json
{"photos":[{"file":"photos/0000.jpg","taken":"2026-10-20T18:00:00","hero":true}]}
```

Mapping matches the Android catalog: start an unsigned 64-bit hash at
`1469598103934665603`; for each UTF-8 byte, XOR the byte, then multiply by
`1099511628211` with wrapping overflow. The unsigned remainder by the entry count
selects the photo in manifest order. The input is the photo's source identifier
(`asset.source_id`, or `FolderPhoto.source_id`), without a scenario prefix or a
folder row-key prefix. `hero` does not change mapping. Thumbnails, hub/history
mosaics and folder viewer images therefore keep the same photo for the same
identifier across platforms and sizes.

Manifest dates fill absent capture metadata after relative scenario timestamps
have shifted. Explicit scenario capture dates and receipt/publication times stay
intact. Generated folder fixtures use the mapped capture date when available.
Dates without an offset use the current local time zone.

ImageIO downsamples thumbnails to at most 512 pixels and folder viewer images to
at most 2048 pixels, applying image orientation. Nearby decode sizes share cache
buckets; caches are keyed by pool file and size, with separate 16 MiB thumbnail,
32 MiB detail and 4 MiB procedural-image limits. Native collection virtualization,
selection and image identity remain unchanged.

A missing, empty or invalid manifest uses the procedural generator. An unreadable
individual image falls back for that identifier. Omit `-mediaDir` to restore
procedural images. Pool paths must stay within the supplied directory.

The stock photos are CC0; local license records live in `build/promo-040/licenses`.
Keep the pool, manifest and license records local and ignored. Never add them to
tracked resources or bundle them in an app.

### Backup scope and Mac updates (A2, A6)

`settings.scope.types`, `settings.scope.albums`, `settings.scope.search`,
`settings.scope.empty`, `settings.scope.unavailable`, `settings.scope.denied`
and `settings.scope.browser` use the production editor with isolated preferences
and 500 synthetic album records. Scope scenarios start in the redesigned pages.
Types use library vocabulary; both lists apply edits immediately. The album
summary estimates the sum of selected album sizes (albums may overlap), remains
independent of search, and withholds the photo estimate for unavailable choices.
iPhone pushes a searchable system list; Mac uses the settings detail and its
native search field. From a row's context menu or accessibility action, View
Album opens the production browser with system title/back navigation. Return
must preserve search, selection and position. These fixtures do not read Photos;
the browser shows the native no-access state. Review the actual grid separately
on a synthetic Photos library with access granted.

`settings.about` opens About directly; its version row has no update controls
in the Mac catalog's store configuration. `settings.about-menu` starts at another detail;
use the application's About command, then repeat from another category or
workspace destination. This uses the production About navigation handler.
`settings.updates.ready` and `settings.updates.unavailable` are Mac-only previews
of the direct-distribution version row and its update destination in the
production About Form. Their isolated
switch applies immediately; Check disables through a synthetic driver without
starting Sparkle, a network request or an installation. The real updater retains
its existing native windows and action executor. Repeat with light/dark, narrow
windows and Chinese; iPhone also supports the catalog's large-text controls.

### Owner review: fixed choices, covers and surfaces

`settings.scope.types` shows A6's small inline checklist without search or a
selection summary. `settings.scope.albums`, `.search` and `.unavailable` show
500 virtualized choices with synthetic cover assets and neutral missing-cover
tiles, using the production thumbnail pipeline. Toggle and scroll to review
identity retention and cancellation; use large text and long localizations.

Every `activity.*` preview includes the production Lock Screen, compact and
minimal contents, with A12's proportional, single-weight symbols and state colors.
`library.system-background` opens the real Mac no-access library container
without reading PhotoKit; `library.all` covers the iPhone populated grid
and calendar transitions in a synthetic simulator library.

`photo.info-light` and `photo.info-dark` open the production iPhone drawer with
an explicit panel appearance for edge review. Check the full bottom edge and
home indicator, scroll to the final field, then close and reopen. The media viewer follows the selected system appearance. On Mac use `-appearance light` or
`-appearance dark` to review the existing trailing inspector.


### Selected backup (D4)

`selection.direct`, `.repeat` and `.failure` exercise the production native
toolbar control with synthetic selection/submission inputs on iPhone and Mac.
They do not access PhotoKit or register real work. Check the anchored repeat
confirmation, Cancel, in-place Added to Backup, and retained selection on failure.

`library.selection-direct`, `-repeat`, `-received` and `-failure` exercise the
real PhotoKit selection/registration route against scripted core answers on the
iOS Simulator's existing synthetic library. Receipt-only items in `-received`
are not repeated or described as saved. The repeat scenario confirms only photos
with a matching saved observation. No scenario exports originals during submission.
`folders.all-not-backed-up` also covers direct submission and selection ending.
Registration is distinct from preparation, transfer and Photos publication;
progress belongs to Backup / Overview. Native rendering and device acceptance
remain separate from these fixtures and build checks.

The iPhone/iPad library uses the photo-only flight over a stationary grid, with
its current tile hidden until return lands. Browsing long press opens the system
menu with a full-aspect cached preview at every density; tapping it uses the same
flight. Select mode retains range selection and Reduce Motion retains its fallback.

### Reserved Settings content

`settings.about` and `settings.feedback` use production content: missing author
text, feedback email and App Store app ID remove their reserved UI completely.
`settings.about-reserved` and `settings.feedback-reserved` inject design-only
placeholders on iPhone and Mac. The former shows the author card; the latter
opens the feedback menu with both actions and shows Rate BackupDuck. The review
URL is formed from the placeholder app ID. The placeholder email uses the
reserved `.invalid` domain. These scenarios do not configure production content.

The iOS-only `photo.viewer-light`, `photo.viewer-dark`, `photo.viewer-immersive`,
`photo.viewer-received`, `photo.viewer-backing-up`, `photo.viewer-not-backed-up`,
`photo.viewer-failed`, `photo.viewer-info` and `photo.viewer-state-change` scenarios use the production viewer
and a thirteen-photo synthetic collection focused on its middle item, without
PhotoKit access. Light/dark scenarios set the enclosing presentation's appearance
and the native navigation owner. The info scenario invokes the title's actual
system button to open the shared A8 panel; tapping again closes it.

Review one system back button and a principal title capsule with exactly two
lines: the relative weekday for the last seven days (otherwise the full date),
then the time. The title slot reserves the native wide capsule geometry; a
trailing system More button balances Back. More contains Show in Backup History when a recorded job exists
and the same supported durable Back Up or Retry action, with no other commands. Title and Info toggle
the shared A8 panel, including title-toggle closing after top chrome fades.
The fixed system toolbar contains exactly two circular system buttons: Share
leading and Info trailing. Info fills while its panel is open. State is a quiet
mark on Info, retained while open: no mark once in the Pixel's Photos, an accent
dot when not backed up or received but not published, and an attention dot on
failure. Only real partial core acknowledgement draws a thin progress ring
around the glyph. Waiting has an accent dot, never estimated progress.
System symbol appear/disappear and replace effects own mark/glyph changes;
Reduce Motion uses cross-fades. Progress interpolates continuously without
custom keyframes. Info's accessibility label includes the state and recorded
percentage, or just Info when normal. The backup facts card and More expose the
same supported durable Back Up or Retry action. History is hidden without a
recorded job; Show in Backup History scrolls to that photo's history entry.
Receipt does not establish Photos publication or cloud upload. Synthetic
registration and retry record queued facts; production keeps durable selected
intent and core retry.

`photo.viewer-state-change` starts without a job, then changes synthetic core
answers after the viewer settles: not backed up, running without confirmed
bytes, 10–90% confirmed bytes, then confirmed Photos publication over about four
seconds. The fixture does not directly set the viewer's glyph or progress.
`-viewer-info` opens the production panel in any viewer fixture, including failed
and not-backed-up states.

The filmstrip occupies its own region directly above the toolbar, outside the
photo. Information fades it away, moves/crops the photo into the upper region,
and fades top chrome. The square-edged information surface continues directly under the photo with
no grabber. Three rounded inset groups contain capture date, weekday and time
on one line with the file name below, independent backup facts with their
recorded times and the history row, then file details. Its scroll viewport ends
above the fixed toolbar, so the final metadata field remains reachable. Drag down, Info or title closes the panel; there is no close
button. Immersion fades all chrome and the light canvas to black without
refitting the browsing photo. These scenarios are source/build fixtures,
not device or motion acceptance.

For an iOS Simulator library comparison, a viewer scenario also accepts
`-viewer-asset <PhotoKit local identifier>`. This reads an existing fixture and
its browsing context only if Photos access is already authorized; it never
requests access or changes the library. Omit the argument for the synthetic
collection. Appearance and information/immersion still come from the scenario.

Viewer captures accept `-appearance light|dark` without changing device settings.
For the information scroll endpoint, combine `photo.viewer-info` with
`-viewer-info-bottom`; this positions the production information scroll view at
its bottom after opening and retains the fixed native toolbar.


### Mac photo viewer chrome

`mac.viewer-light`, `mac.viewer-dark`, `mac.viewer-inspector`,
`mac.viewer-failed`, `mac.viewer-not-backed-up` and `mac.viewer-backing-up`
open thirteen synthetic photos in the production workspace without PhotoKit
library access. Pass `-scenario <id> -appearance light|dark` and
optionally `-snapshot <absolute.png> -snapshot-delay 4`.

The sidebar stays mounted and the canvas uses the system window background.
The native toolbar contains Back, a centered date with time and collection
position, Share and Info. Info, Command-I and View > Show Info share one
window-scoped inspector value, retained while browsing. The information layout
orders capture date/name, recorded backup facts with Back Up or Retry and
conditional history navigation, then file details; it has no close button.
The Info mark is absent after confirmed publication, accent for unbacked/waiting
states, attention for failure, and a ring only for partial confirmed core bytes.
The backing-up fixture supplies 1,920,000 of 4,800,000 confirmed bytes (40%).
System symbol replacement/disappearance effects become cross-fades with Reduce
Motion. Left/Right page, Escape/Back return to the current item, and a single
click never hides the Mac chrome. History and Folders inherit the same native
window presentation, toolbar and A8 information structure. The library's
existing tile flight and paging/zoom owners are retained.

The fitted media viewport has `DuckSpacing.large` on every edge. The library's
flight probe measures that same inset viewport, including when the inspector
changes its width. Named browsing toolbar items keep the native Folders search
field distinct from the viewer controls; the browser retains its query.

`folders.viewer` starts with the `Mountains` query and a selected unsaved photo.
It opens the first result through the mounted production grid, after the browsing
toolbar has appeared. Add `-folder-viewer-state browse` to stay in browsing.
Back restores the query and selection. `mac.viewer-light -viewer-entry history`
opens the recorded-source fallback over History with its browsing toolbar hidden.
For interactive captures, add `-snapshot-mode manual` to the usual snapshot
arguments, perform the native Accessibility actions, then activate the Catalog's
Snapshot button. The same `-snapshot-delay` runs after that action.

### Mac synthetic-source isolation and Folders toolbar

The Mac catalog always disables PhotoKit before creating any model; scenario
selection cannot enable it. Authorization queries/requests, change observers,
metadata fetches, background preparation and image-manager construction respect
that source boundary. `library.synthetic` browses 90 in-memory sample assets
through the production grid; `library.system-background` retains the no-access
fixture. Neither reads the Mac photo library. iOS library comparison scenarios
retain their existing simulator source.

Folders uses the native navigation View item, independent Add Folder and
conditional Back Up Selected items, and system `.searchable` toolbar placement.
The viewer removes every browsing item; returning preserves the browser's query,
selection and scroll state. `-window-width <points>` sizes only the catalog
window for captures. Widths below the production minimum of 900 points (down to
640) additionally exercise native toolbar overflow. Search remains a system
search item, reachable from Edit > Search and Command-F.

First-run marks follow V6: the welcome list shares a 36-point square column with
optically sized silhouettes, and each later page keeps the same three-mark row
above the scrolling content. Only its current mark uses a brand color; inactive
marks use the native tertiary text role. The row exposes one localized step count. The
`-reduce-transparency` iOS catalog argument injects the shared mark fallback
environment for repeatable review without changing a device setting. In that
mode inactive marks use the stronger neutral secondary text role.
The welcome duck and naturally wrapping headline are centred. The left-aligned
step list is centred as a whole, wrapping within the available width when needed.

First-photo fixtures share a leading title directly below the step marks, a
centred decorative flight, and one factual status with at most one supporting
sentence. Known blocking causes replace the sending message immediately; slow
recovery actions retain their 20-second gate. Receipt and publication remain
separate. The flight is hidden from accessibility because the adjacent text
owns the fact. Sending is shown only for observed running work.
The flight uses symmetric SF Symbol device slots (`iphone` and `smartphone`),
recorded device names and a localized Pixel Photos destination label. Its photo
uses the production asset thumbnail; Catalog supplies the synthetic asset.
`onboarding.first-photo-preparing` and `onboarding.first-photo-save-failed`
cover preparation and failed publication. `onboarding.first-photo-flight`
provides a timed publication transition; `-reduce-motion` injects the flight's
immediate arrival path without changing system settings.

### iPhone selection review

`selection.review.selected`, `.open`, `.deselected` and `.feedback` use the
production calendar grid, review sheet and shared selected-backup feedback.
Twelve photos span twelve months; deselection keeps the original review tiles.
Pass `-mediaDir <absolute path>` to use the local sample pool, and
`-appearance light|dark` for app-only appearance. `.repeat` and `.failure`
exercise confirmation and submission recovery. Submission is synthetic;
these scenarios never export originals or register backup work.

### Apple diagnostics and records

`diagnostics.root`, `.empty`, `.failed`, `.export-success`, `.export-failure`
and `.export-sheet` open the shared production diagnostics in the Mac Settings
secondary Settings pane or as a pushed iPhone Settings page. Launch with
`-appearance light` (or `dark`). Recent activity is read-only and limited to six
latest events, newest first and grouped by day. Known codes use plain localized
titles; unknown codes display “Other activity”. There are no log, entry or retention pages.
Exports write the complete synthetic core JSON, including unknown fields;
saving/sharing uses the system interface. The failed-export scenario fails once,
then the ordinary export row retries with a fresh snapshot. Send Feedback uses
the same export service; its reserved email option is hidden without an address.
Persisted retention overrides migrate to 14 days without initiating cache
maintenance or photo preparation.

`records.toolbar-attention` opens five attention items on Mac;
`records.toolbar-all` opens the shared history on either Apple platform. Mac
uses the window title/subtitle and shared native zoom capsule; pause belongs
to Overview. The cloud-backup footer appears once per records surface.

The diagnostics export-success start position simulates completed system sharing;
export-sheet opens the real system sheet. The export row retries a fresh snapshot
after failure. Retention is fixed at 14 days; there is no retention destination.

Mac snapshot runs activate the current key window before capturing it. Quit
each Catalog run before starting another instance with the same bundle identity.

Parallel display-headline clauses occupy separate centred lines in every language.
The localized `onboarding_title` supplies explicit line breaks; native `Text`
wraps an overlong clause inside its own paragraph. Review Chinese and English
welcome in light and dark. No width-dependent clause layout or invisible break
characters are used. Mac currently does not show this welcome headline.
