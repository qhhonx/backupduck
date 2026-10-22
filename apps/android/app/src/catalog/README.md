# Pixel receiver design catalog

The `catalog` build type (`app.backupduck.catalog`, label "Duck Catalog")
renders the production receiver pages from scenario data. It is a review target
only and is never distributed. See the design catalog section of
`design/constitution.md`. The Apple catalogs are described in
`apps/apple/Catalog/README.md`.

## How it works

The receiver UI takes these from outside the activity:

| Provider | App | Catalog |
| --- | --- | --- |
| `NativeBridge.transport` | The linked Rust library | `CatalogRuntime`, which answers from the scenario |
| `ReceiverEnvironment.startService` / `stopService` | Start or stop `ReceiverService` | Play the scenario's `service` snapshots or publish `stopped` |
| `ReceiverEnvironment.checksUpdates` | On | Off |
| `ReceiverEnvironment.previewImage` | Unset: published pictures come from the copy in the Pixel's Photos | `CatalogMedia`, an optional local photo pool with `SyntheticPhotos` fallback, drawn where the app would read a copy in Photos |
| `ReceiverEnvironment.now` | The system clock | The scenario's `now_ms`, when set |
| `ReceiverEnvironment.scanOverride` | Unset: scanning opens the camera | The scenario's `scan` result, when set |
| `ReceiverState` | Written by `ReceiverService` | Set from the scenario's `snapshot` |

The catalog manifest removes `ReceiverService`, the boot restarter and the
accessibility service, and moves the launcher to `CatalogActivity`. The catalog
therefore never opens a receiver port, never restarts on boot and does not
affect a production receiver on the same device.

`CatalogActivity` lists the scenarios. `--ez proposed true`, or "Design" in
the ⓘ options, shows the redesign, built from the shared components in
`DuckLook.kt`: `ReceiverHub` on the receive page, Received photos
(`ReceivedPhotosPage`, design/records.md) on the transfers page, the redesigned
settings page, and Storage (`StorageScreen`) for the `storage` page. The
`pixel.photos-*` scenarios cover Received photos with problems from two
senders, with nothing to fix, and empty. Every `pixel.*` receive scenario also
covers a hub state (receiving, all saved, all received with some not saved,
space running low, waiting, no device, stopped, paused, space full, too hot, no
Wi‑Fi, other problem), and `pixel.storage*` covers Storage. Opening one resets the catalog app's own
preferences, seeds the scenario's preferences and snapshot, and starts the
production `MainActivity` at the scenario's page. The ⓘ button in a reserved bottom strip outside the page
shows the scenario details and the unscripted core commands. It also restarts
the scenario, switches between dark and light, or closes the page.

## Scenario files

Scenarios are JSON files in `assets/scenarios/`. They use the same rules as the
Apple scenarios (`id`, `page`, `title`, `extends`, `core`, `expect`, `actions`),
except that `core` delays are written as `delay_ms`. These fields are specific
to the receiver:

- `page` is a bottom navigation destination: `receive`, `transfers`, `storage`
  or `settings`, or `onboarding` for first run (`ReceiverOnboardingActivity`),
  with `step` naming the screen to start on (`welcome`, `running`, `code`,
  `connected`, `gphotos`, `space`).
- `prefs` maps a preference file to its values. For example,
  `receiver_lifecycle.enabled` and `manual_pause` decide whether the receiver
  is on or paused.
- `snapshot` holds the published `ReceiverSnapshot` fields (`phase`, `error`,
  `published`, `received`, `total`, `failed`, `thermal_held`,
  `temperature_deci_celsius`, …).
- `service` lists the snapshots to play when the page starts receiving, each
  after `delay_ms`. Only a scenario that starts with receiving off should have
  one. The app also asks for the service whenever receiving is on, and replaying
  it would overwrite the scenario's state.
- `pairing` is the synthetic pairing code that a ready receiver shows.
- `surface` opens a sheet or page over `page`: `pairing` (the connect
  screen), `connect-mac` or `devices`.
- `scan` is what the camera reads when a page scans a code (for example a
  synthetic Mac code), after a short pause. Without it the real camera opens.
- `storage` fixes the device readings the hub and Storage show:
  `total_bytes`, `free_bytes` and `photos_bytes` (BackupDuck's files in the
  Pixel's Photos). Without it they come from the device.
- `now_ms` fixes the clock that decides Today and Yesterday on Received
  photos. Its times are written for the test Pixel's time zone
  (America/New_York).

Device readings on the receive page (battery temperature, storage and battery
level) and the storage capacity come from the device itself unless the scenario
sets `storage`.

## Running

```bash
./gradlew assembleCatalog
```

```bash
adb install -r app/build/outputs/apk/catalog/app-catalog.apk
```

```bash
adb shell am start -n app.backupduck.catalog/app.backupduck.CatalogActivity --es scenario pixel.receiving --es appearance dark
```

Add `--ez proposed true` for the redesigned pages and `--es language zh-CN` for
Chinese. Re-identify the device before installing. The catalog installs beside the
production receiver and never touches its data. The pairing code sheet sets
`FLAG_SECURE`, so screenshots of it are blank. Use `uiautomator dump` to check
its content.

Duck poses and step marks are VectorDrawables (`duck_*`, `mark_*`) generated by
`scripts/export-illustrations.py`.

## Storage composition contract

`StorageScreen` uses `lookContentSection` and `LookSectionMetrics` for every
section after its summary: the token-based section gap belongs outside the
section, so hiding the kept-files section also hides its gap. `lookFootnote`
places supporting notes below the group with the shared top gap and horizontal
inset. Cards and rows continue to own their inner padding and icon column.

Free up space automatically is always one group with three rows: free up after
saving to Photos, system Smart Storage, and experimental automatic cleanup.
Each uses a monochrome leading icon and one short action phrase. Normal row
support does not change with the switch or a recorded completion; a failure
replaces only the affected row's support with its cause and recovery action.
The automatic section has one cloud-retention footnote, followed by the last
freed amount and date on its own line only when both facts are recorded. Google Photos decides
what can be removed; that explanation lives in Help's freeing-space section.

Temporary-file rows show only their name and measured size. Their single
footnote names the measured amount saved in Photos that can be freed, and is
omitted when zero or unknown. Free up space now has one cloud-retention sentence
and the Google Photos action. Check all four Storage scenarios at 412 dp in
English and Chinese for orphaned words/characters as well as clipping. The shared
row, footnote and consent components balance lines using the native text layout
strategy, including enlarged text. The Google Photos action follows the same
wrapping strategy.
Measured-zero usage legend entries are omitted; unknown readings retain a dash.

Review `pixel.storage`, `pixel.storage-on`, `pixel.storage-cleanup-failed` and
`pixel.cleanup-consent` in both languages and appearances, at ordinary and
enlarged text sizes. Check the group footnotes, the next heading, recovery text,
and scrolling the Free up space now action fully above the bottom inset.
Settings and Connected devices use the same section-header spacing; Advanced
has one row-only group and no footnote/next-section combination.

## Optional local photo pool

The catalog can use the shared, git-ignored `build/catalog-media/` pool. From the
repository root, copy it into the **catalog package's** external files directory:

```bash
adb push build/catalog-media /sdcard/Android/data/app.backupduck.catalog/files/
```

For a specific device, add `-s <serial>` after `adb`. Install and open the catalog
first if its external files directory does not yet exist. This path is exclusively
for `app.backupduck.catalog`; never push into the production `app.backupduck` package.
Restart the scenario after copying or changing the pool.

The app reads `getExternalFilesDir(null)/catalog-media/manifest.json`. Its `photos`
array contains a pool-relative `file`, an ISO `taken` date and a `hero` flag:

```json
{"photos":[{"file":"photos/0000.jpg","taken":"2026-10-20T18:00:00","hero":true}]}
```

A fixed 64-bit UTF-8 hash of each photo identifier selects an index in manifest
order. The same identifier always selects the same photo across scenarios and
thumbnail/viewer sizes. `hero` is optional metadata; it does not change mapping.
Manifest dates fill missing capture dates in history answers; explicit scenario
dates and receipt/publication times remain intact. Dates without an offset use the
device's time zone.

Decoding runs on the existing bounded image workers, downsampled for the requested
size with a 2048-pixel maximum edge and a 16 MiB pool cache. Synthetic fallback has
a separate 4 MiB cache. The production loading, cancellation and stable tile
identity remain in charge. A missing, empty or invalid manifest uses procedural
landscapes; an unreadable individual photo falls back for that item. Removing the
pool and restarting the scenario restores procedural images everywhere.

## Received-original previews

The production image loader falls back to `receiver_preview` for received items
whose published copy cannot be loaded, including failed and pending saves. Its
two bounded IO workers retain cancellation, stable identity and a 16 MiB bitmap
cache. Disposable paths purged before opening are requested once more. Missing,
unsupported or failed previews leave neutral media icons without error text;
preview availability never changes receipt or publication facts.

Problem cards show up to three affected photos between the cause and its single
action. A nonempty group reserves a 48 dp row immediately; an empty group reserves
no row. Loading replaces pixels inside those slots without resizing the card.
Offscreen/recycled cells and dismissed viewers cancel image work.

Loading and unavailable previews use the surface-container-highest role in both
appearances. Loading tiles show neither a glyph nor a spinner; unavailable tiles
show a centered photo glyph in on-surface-variant.

The problem scenarios script `receiver_preview` with `status: available`.
`CatalogMedia` materializes a disposable JPEG with a maximum edge of 512 pixels
under the catalog's cache directory, using the same ID-to-pool mapping (or
synthetic fallback) as the timeline and viewer. `pixel.photos-previews-unavailable`
and `pixel.photos-previews-delayed` cover neutral placeholders and late results.
The base scenario scripts unavailable previews, so unrelated scenarios stay
explicit about this capability.

The stock images are CC0; local license records are in `build/promo-040/licenses`.
Keep images, manifests and license records local and ignored. Never add them to
tracked resources or package them in the APK.

## Receiver preference and help pages

These scenarios use production Material pages and dialogs (A2/A4/A5, I8):

- `pixel.settings`: Settings bottom has Help & feedback, the separate About row
  and centered Diagnostics · Advanced settings links (诊断信息 · 高级设置). Every
  preference row centers its monochrome icon with the complete text block; the
  footer has 48 dp touch targets.
- `pixel.about`: the production pushed About page has one Version row with the
  package version in its title and a settled Up to date fixture underneath.
  It opens the existing update page, which contains status, the check/download
  action and the automatic-check switch, with no installed-version line.
  Privacy, source repository and website rows remain. No bundled license viewer
  exists in this host.
- `pixel.feedback`: opens Settings scrolled to Help & feedback without launching
  an external app. With no configured mailbox, tapping Send Feedback still opens
  the existing user group directly; the settings subtitle offers only that group.
- `pixel.about-reserved` and `pixel.feedback-reserved`: `show_reserved: true`
  supplies a titled, localized author placeholder card and an `example.invalid` mailbox
  for design review. Production uses the two optional values in
  `ReservedSettingsContent`; null omits the author card or email action entirely.
  The reserved email flow exports a visible diagnostics document before composing
  a draft with that attachment and the configured recipient. Cancellation/failure
  preserves the page and exported document. `receiver_logs` is synthetic here.
- `pixel.help`: searchable task/problem index; `pixel.help-connection`,
  `pixel.help-results`, `pixel.help-storage`, `pixel.help-background` and
  `pixel.help-recovery`: the existing read-only receiver articles.
- `pixel.conversion` and `pixel.conversion-on`: the persisted format-conversion
  switch, off and on, on a pushed page.
- `pixel.browser`, `pixel.browser-off`, `pixel.browser-failed` and
  `pixel.browser-edit-failed`: address,
  access code, switch, edit/reset/sign-out dialogs and read failure/recovery.
  All addresses and codes are synthetic. The failed scenario succeeds on retry.
- `pixel.updates`, `pixel.updates-available` and `pixel.updates-failed`: current,
  available and failed explicit update checks. The catalog supplies these
  results without network access and disables update downloads/installation.

All use `page: settings` and `surface` to open the production destination,
except the single-option feedback preview, which shows its Settings entry.
The optional `updates` object accepts `state: current|available|failed` and
`delay_ms` for an explicit update check. Current fixtures also seed the shared
settled observation so About never waits for an automatic check. Review each in light/dark, English/Chinese,
normal/large text, and with both toolbar and system Back. A compiled scenario is
not native visual or physical-device acceptance.

## Library chrome A/B (D1)

`pixel.photos-ab-current` and `pixel.photos-ab-native` share the same problem,
receipt and publication fixtures. `--es libraryChrome current|native` overrides
that scenario's choice. MainActivity also accepts the extra in debug builds;
ordinary production launches always retain current behavior. This is temporary
comparison infrastructure, not a preference or an approved default migration.

```bash
adb shell am start -S -n app.backupduck.catalog/app.backupduck.CatalogActivity --es scenario pixel.photos-ab-current --es libraryChrome current
adb shell am start -S -n app.backupduck.catalog/app.backupduck.CatalogActivity --es scenario pixel.photos-ab-native --es libraryChrome native
```

The native branch uses AndroidX SelectionTracker with stable media ID keys and
AppCompat overlay ActionMode, styled by the Material 3 theme. The contextual bar
covers the top app bar without changing the grid bounds or scroll offset.
View requires one item; Retry applies only to retryable
publication failures; Share uses verified published copies or isolated synthetic
catalog JPEGs. A missing copy leaves the selection and an actionable failure in
the contextual bar. Each cause grid owns its selection separately. Long press
starts selection without opening the viewer; taps toggle while selection is active.
Back exits selection. View preserves selection on return.
Selected native tiles inset by the small spacing token and clip to the control
corner radius. A top-start primary circle carries an on-primary check; other
tiles show an outlined circle while selection is active. Leaving selection
restores the original image bounds without changing thumbnail identity.

The viewer is an Activity destination using Android shared-element transitions,
with the source tile's actual ImageView and a stable transition name per media ID.
The launch reasserts the tile name and preserves Android's captured outgoing
mapping; the source callback resolves a new tile only on reentry. The viewer
theme explicitly enables Activity transitions and disables window animations.
Only the toolbar and information panel fade, never an ancestor of the photo.
Entry is postponed only until the fitted poster's first laid-out frame; a retained
tile poster prevents a blank frame and stays unchanged during the flight. With a
poster, the full-size request starts after entry settles, so decoding cannot gate
entry. Without one, the first available rendition releases entry; failure removes
the shared mapping. Loading is cancelled on return and destruction.
At return start, the viewer adopts the source window's status/navigation icon
appearance, including dark-mode and animation-disabled returns, before its dark
canvas fades away over the grid.
The source grid remains mounted. Return sends the displayed media ID, scrolls its
tile into view if needed and postpones reentry until its thumbnail is laid out
(with a bounded wait). A removed/unavailable tile uses a short snapshot fade.
Animator duration scale zero removes both shared-element motion and fallback fades.
Photos opened from a separate dialog window keep that grid and selection but
use the platform activity fallback (the tile is outside the source Activity
window). The current Dialog and cause-sheet dismissal remain unchanged in the current
branch. Both destinations use the same docked information content (A8).
Both variants hand the displayed tile bitmap directly to the viewer, independently
of cache eviction or animation settings, and retain it until full-image decode
succeeds. The current variant still opens the viewer after a long press. Review
that interaction with deliberately slow decode: the photo must remain visible
from the first viewer frame, including when full-image loading fails.

Native review still needs Release recordings: start at a mid-library tile,
long-press, add/remove a selection, view and reverse to the same tile; repeat in
a cause group. Check a held/cancelled long press, Back during image loading,
missing media, Retry/Share failure, paging during background updates, rotation,
light/dark, large text, TalkBack and disabled system animations. Build success
does not establish motion or device acceptance.

## Grayscale preview regression

The optional media pool maps `catalog-1981` to `photos/0528.jpg`, a grayscale
street scene with a gray ICC profile. On the review device, decoding its pixels
was correct, but scaling the bitmap with the decoder's unknown RGB profile before
JPEG export produced an almost-white preview. `CatalogMedia` requests sRGB at
decode time so the bounded scaling/export path retains luminance. The pool,
ID mapping, publication facts and production media loader are unchanged.

A standalone device graphics probe (no app installation) reproduced the full
512-by-769 decode, 340-by-512 scaling, JPEG round trip and hardware draw. The
unconverted preview had 99.95% near-white pixels; the sRGB preview had 3.27%,
with mean luminance 85.83 instead of 254.88. These are decoder/draw observations,
not visual acceptance of the new settings pages. Local generated evidence is in
`apps/android/build/reports/settings-feedback/` and is not source material.

### Automatic cleanup (D2)

Storage is the canonical automatic-cleanup switch. First run and the hub's
low-space card open that same destination; opening Storage acknowledges its
feature-discovery mark without enabling cleanup. Technical setup, account
binding, probe and progress pages are under Diagnostics.

- `pixel.storage`: automatic cleanup off, system Smart Storage on.
- `pixel.storage-on`: on, with a synthetic recorded 2.3 GB completion on October 20 in the section footnote.
- `pixel.storage-cleanup-failed`: changed-page cause and one inline recovery action.
- `pixel.cleanup-consent`: shared application-consent sheet, three disclosures,
  experiment note, Not now and Go to settings.

`storage.smart_storage` and `storage.cleanup_access` replace system readings in
Catalog only. Production checks actual accessibility access on return from
Settings; the consent itself never grants system access. Recorded completion
bytes come only from a recognized completion amount; unknown amounts stay
unknown. Binding and the cleanup state machine retain their existing fences.

## Layout and recreation regressions

Scenario controls reserve a separate bottom strip; they never cover the page's
navigation title or content. Non-onboarding fixtures seed first-run completion,
including `pixel.devices-none`, so an empty peer list stays on Connected devices.
Theme recreation retains FragmentManager-owned destinations without dismissing
them during Activity destruction. Review direct dark launches and the Catalog
Dark / light option while a pushed destination is open.

Settings discovery marks have a token-sized trailing slot. Shared preference
rows preserve explicitly supplied trailing dimensions; text retains the remaining
width and grows vertically. Review `pixel.settings` and `pixel.settings-stopped`
with the Storage row visible in both languages and appearances.

The Chinese photo-scope summary puts source/count and saved-to-Photos on separate
lines and keeps the two characters of Photos together with a word joiner. Review `pixel.transfers` and `pixel.transfers-failed` in light/dark.
The current viewer selects system-bar icon contrast from the actual canvas color,
including a light dialog canvas. This does not change its photo or navigation
behavior. Preview cancellation through Android's signal is an expected discarded
result, including when it arrives before or after decoding.
