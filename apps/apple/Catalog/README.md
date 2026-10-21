# Apple design catalogs

`BackupDuckCatalog` exists for iPhone (`apps/ios`) and Mac (`apps/macos`). Each
renders the production pages from scenario data. They are review targets only:
they are never archived or distributed. See the design catalog section of
`design/constitution.md`. The Pixel receiver catalog is described in
`apps/android/app/src/catalog/README.md`.

## How it works

The sender model takes everything outside the app process from
`BackupEnvironment` (`apps/apple/Shared/BackupEnvironment.swift`):

| Provider | App | Catalog |
| --- | --- | --- |
| `core` | `NativeCore`, the linked Rust library | `ScenarioCore`, which answers from the scenario |
| `credentials` | `SystemKeychain` | `ScenarioCredentials`, kept in memory |
| `discoversReceivers` | Bonjour on | off |
| `usesPhotoLibrary` | PhotoKit thumbnails and change observers | off, so the catalog never reads real photos or prompts; on only in iPhone library scenarios |
| `requestPhotoAccess` | The system photo prompt | granted, without a prompt |
| `sampleThumbnail` | none | synthetic landscapes drawn from the photo identifier (`SampleImages.swift`); off in library scenarios |
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
