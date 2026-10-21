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
production `MainActivity` at the scenario's page. The ⓘ button over the page
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
