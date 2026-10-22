# Apple design catalogs

`BackupDuckCatalog` exists for iPhone (`apps/ios`) and Mac (`apps/macos`). Each
renders the production pages from scenario data. They are review targets only:
they are never archived or distributed. See the design catalog section of
`design/constitution.md`. The Pixel receiver catalog is described in
`apps/android/app/src/catalog/README.md`.

## How it works

### Settings bottom, About and feedback

`settings.bottom`, `settings.about` and `settings.feedback` use the redesigned
production settings on both Apple hosts, without needing `-proposed`. The iPhone
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
are inert in this review; Pause uses the synthetic core only. In the app,
Settings and Command-comma navigate to Settings in the main window.
Repeat with `-appearance light` / `dark` and `-AppleLanguages '(zh-Hans)'`.
Check the disabled first line, the single Pause/Resume item, separators, shortcuts
and the static activity symbol; the idle icon uses the exported duck template.

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
  "page": "receiver",
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

- `page` is a root destination: `library`, `backup`, `receiver` or `settings`,
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

- **Receiver** and **Settings** have scenarios on both catalogs.
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

The info sheet's Design picker switches between the current page and the
proposed redesign (`IOSHub`, `IOSSettings`, `MacSettings`); `-proposed` starts
on the proposed design. The Library tab shows a placeholder, and other Mac
sidebar destinations render without scenarios. The Library needs a synthetic
photo source in place of PhotoKit. Actions that request system permissions
(camera, photos) still reach the system. In the Simulator, the pairing sheet
shows the camera-unavailable state.

Duck poses and step marks come from `Illustrations.xcassets`, generated by
`scripts/export-illustrations.py` from `assets/illustrations`.


## Optional local photo pool

Both Apple catalogs accept `-mediaDir <absolute path>` at launch. Point it at the
shared, git-ignored `build/catalog-media/` directory; by default no pool is used.
For example, from the repository root:

```bash
xcrun simctl launch booted app.backupduck.catalog -scenario hub.backing-up -proposed -mediaDir "$PWD/build/catalog-media"
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

### Reserved Settings content

`settings.about` and `settings.feedback` use production content: missing author
text, feedback email and App Store app ID remove their reserved UI completely.
`settings.about-reserved` and `settings.feedback-reserved` inject design-only
placeholders on iPhone and Mac. The former shows the author card; the latter
opens the feedback menu with both actions and shows Rate BackupDuck. The review
URL is formed from the placeholder app ID. The placeholder email uses the
reserved `.invalid` domain. These scenarios do not configure production content.
