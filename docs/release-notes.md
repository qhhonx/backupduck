# 0.3.0 — build 86

- Open straight into the library: the photo list starts loading while the app
  launches, the first frame no longer passes through the permission screen, and
  grid cells are cheaper to create.

# 0.3.0 — build 85

- Open the library without the saved launch picture: the first screen now fills
  from stored thumbnails as soon as the library is indexed.

# 0.3.0 — build 84

- Keep small decoded thumbnails in memory-mapped tables sized for this device's
  month and year grids, filled in the background from local renditions, so the
  densest overviews scroll without blank tiles or dropped frames. Larger grids
  show these soft thumbnails until each sharp one arrives instead of empty cells.
- Count the decoded tables toward the thumbnail cache limit, which now defaults
  to 1 GB and offers up to 4 GB, and show usage and limit in the same units.

# 0.3.0 — build 83

- Rework the Mac Photos library around independent Years, Months and All Photos
  browsing, oldest to newest and resting at the newest edge as in Photos, with
  native window toolbar controls, discrete zoom steps and animated level changes.
- Open media inside the current window, retain filtered and selected contexts,
  add a bounded thumbnail strip, and return to the current photo in the grid.
- Use desktop single-click, Command/Shift selection, double-click and keyboard
  preview conventions; share progressive previews, media information and durable
  selected-backup submission with the Apple media pipeline.
- Show the whole photo immediately when opening an iCloud original that is still
  downloading, using the device's small full-aspect copy, instead of a small
  square crop with empty bands (most visible on panoramas).

# 0.3.0 — build 82

- Keep a photo's framing fixed while it opens from the library grid: the grid's
  square thumbnail sits at its true place in the photo instead of filling it, so
  the arriving full image no longer appears to stretch sideways.

# 0.3.0 — build 81

- Preserve the dense mosaic's published pixels when a renewed pinch starts after
  thumbnail-cache eviction. Keep the animation cover until visible replacement
  strips publish instead of exposing a partly drawn canvas.
- Initialize strip contexts before synchronous image callbacks and isolate
  publication scheduling across recycled strip generations.
- Scale gapless dense faces through a shared node, refreshing tile membership at
  viewport boundaries while preserving unscaled captions and ordinary dividers.

# 0.3.0 — build 80

- Share vertically centred sheet headers across detail, activity-log and desktop
  Help sheets, retaining wrapping titles and platform-sized close targets.
- Make original-preparation and source-photo detail footer actions fill their
  iPhone column, matching other phone sheets; keep desktop actions compact and
  trailing aligned. Preserve fixed chrome in busy, error and retry states.

# 0.3.0 — build 79

- Allow PhotoKit to load iCloud previews automatically; remove the separate
  browsing network setting and application consent prompt.
- Keep available cropped fallback pixels in single-column browsing, request the
  uncropped target before density adoption, and retain sharper source posters
  through progressive detail loading.
- Recover cancelled cell requests when they reappear. If a larger local thumbnail
  is unavailable, try PhotoKit's small local rendition before its bounded cloud
  upgrade; never cache that fallback as the larger rendition.
- Separate the selection header actions into independent native material groups.
  Keep unavailable backup actions visibly disabled, absorb header-region taps and
  suspend native scroll-to-top during selection to preserve the photo anchor.
- Wrap complete lens information and hide the redundant map-pin title beneath
  the capture-location heading.

# 0.3.0 — build 78

- Preserve uncropped single-column photos through detail return, separate selected
  video duration from its selection badge, and name the selected backup action.
- Use consistent information labels and show the iCloud preview explanation when
  enabling the setting, with cancellation preserving the previous consent.
- Use an All Albums switch with an explicit empty restricted scope. Choosing an
  album disables All; enabling All clears individual choices.
- Clarify browsing thumbnails, temporary backup files and device space settings.
  Align cache values and menus, and show thumbnail clearing progress and failures.
- Center standalone loading states, name the settings being read, and expose
  initialization failure recovery instead of leaving cache settings waiting.

# 0.3.0 — build 77

- Keep native detail pages and displayed source posters available before image
  loading, and prepare the small entry pose before revealing the media.
- Retain video posters until the first actual playback frame is ready. Keep
  media geometry fixed through entry, downward drag and return to the grid.
- Replace redundant header loading text, spinner and linear progress with one
  media-local loading ring and compact recovery state.
- Match selected-detail Done styling, remove filmstrip selection borders, and
  disable information gestures and actions in selected-item detail.
- Move ordinary detail media and information together into an aspect-aware top
  viewport, with continuous fading of the viewer controls.

# 0.3.0 — build 76

- Keep iPhone detail media in a stable full-screen viewport under its controls,
  with a narrow inter-photo paging gap and bounded first/last-page bouncing.
- Drive filmstrip emphasis and position continuously from page progress, while
  direct scrubbing retains its own compact position and stable selected batch.
- Use the same live media transform and crop for entering and leaving detail;
  keep a dragged photo anchored under the finger while shrinking.
- Hide viewer chrome during magnification and restore it when opening information.

# 0.3.0 — build 75

- Show the last newest-edge library screen in the first launch frame and fade to
  live cells when their images are ready, instead of a blank canvas flash.
- Resolve dense overview and pinch assets with bulk PhotoKit fetches and a
  bounded asset cache, removing per-asset materialization stalls on large libraries.
- Make pinching in Years and Months trigger one level change, as Photos does,
  instead of a finger-following zoom.

# 0.3.0 — build 74

- Index the newest library items with one bulk PhotoKit fetch at launch. On a
  large iPhone library the first thumbnails now appear in about 0.4 s
  after process start, instead of about 1.0–1.5 s.

# 0.3.0 — build 73

- Draw the iPhone dense month and year overviews as bitmap strips instead of
  thousands of cells, removing the scrolling stalls measured in profiles.
- Keep the library zoom menu open so zoom in and out can be repeated.
- Carry period labels, top shadows and badges with moving photos in Years,
  Months and All switches, fade glass period headings and the navigation bar,
  and start the switch immediately on a spring matched to Photos.
- Request three-column thumbnails at PhotoKit's fast stored-rendition size.

# 0.3.0 — build 72

- Switch iPhone library dividers in one frame with the previewed density and
  snap them to device pixels, as Photos does, instead of thinning them while
  photos crossfade. Finish the remaining crossfade within the release settle.
- Keep browsing undisturbed while iCloud updates the library: identical rebuilds
  are ignored, changes wait for running motion and preserve cached thumbnails
  and the focused photo's position.
- Show the newest photos sooner at launch, serve dense overview thumbnails
  directly from Photos with wider concurrency, and stop waiting for the disk
  cache index before the first thumbnails.
- Reopen the library at three or five columns according to the last browsing
  density, and reduce the terminal year-overview stretch.

# 0.3.0 — build 71

- Keep compact Library taps limited to native tab expansion. Return to newest
  only when reselecting the already expanded Library tab.
- Scale complete cell decorations with the photo and clip all fading faces to
  one continuously changing gap, avoiding separators that appear only at the end.
- Transfer displayed images directly to native cells across cache eviction and
  delayed fallback callbacks. Adopt the same geometry beneath a one-commit cover.
- Remove additional library edge shadows that changed when hiding the collection.

# 0.3.0 — build 70

- Preserve vertical focus during held library photo crossfades. Allow the
  incoming overview to end above the viewport bottom rather than shifting the
  anchor as its opacity changes. Retain the side-coverage and row-phase fixes
  and shared animated media badges from build 69.

# 0.3.0 — build 69

- Fill the full iPhone pinch viewport with neighboring row slots while layouts
  shrink, and retain the focal photo's destination row phase through reversal
  and settlement to avoid whole-column sideways travel.
- Share video-duration, Live Photo, selection and backup-state decorations
  between ordinary grid cells and animated tiles so collection adoption does
  not introduce missing badges.

# 0.3.0 — build 68

- Prepare iPhone thumbnail pixels away from the UI thread and prioritize visible
  images over speculative layout warmup. Keep native loading independent of
  bounded disk writeback, and bound disk-hit decoding as well as acquisition.
- Retain small images for dense transition tiles separately from sharper return
  images. Preserve shared request cancellation, preview ordering, cache revisions
  and late-write invalidation.

# 0.3.0 — build 67

- Refine iPhone library pinch transitions with direction-aware previews,
  interruptible photo blending, independent date-range changes, live bottom-edge
  constraints and a slower, non-bouncing release. Releasing preserves the current
  preview target even before its natural thumbnail size is reached.

# 0.3.0

- Refresh the iPhone/macOS sender and Android receiver interfaces with reusable
  components, consistent settings groups, clearer actions and less repetitive
  explanatory text.
- Standardize Apple preference density and section spacing, improve Mac library
  selection controls and folder view alignment, and move update settings into About.
- Derive monochrome system icons from the original BackupDuck brand artwork.
- Register selected backup work durably before preparing originals. Preparation,
  failures and retry continue on task screens instead of blocking confirmation.
- Improve receiver-result updates and preserve selection, scrolling and filtering
  as background task states change.
- Add a one-time, duck-yellow discovery mark to the Android receiver Settings tab
  and Experiments entry. Viewing the overview clears both; cleanup stays opt-in.
- Simplify experimental Google Photos space-management setup and result screens.
  The feature remains experimental; receipt and gallery publication do not prove
  Google Photos cloud upload or a successful cleanup.
- Provide English contributor documentation and maintained design/component
  contracts. Android and Windows sender applications remain outside this release.

Release metadata: version 0.3.0, build 47. iOS TestFlight availability is separate
from the Mac and Android release. Real slow iCloud-original preparation,
automatic low-space cleanup and interrupted-cleanup recovery remain separate
verification scenarios.

Official Mac 0.2.x and Android RC.2/RC.3 installations retain their update
identities. Android RC.1 and PhotoBridge 0.1.x need the separate transition
described in [upgrade compatibility](upgrading.md). Legacy update endpoints
remain required when the primary website moves to GitHub Pages.

# 0.2.0-rc.3

- Keep the Pixel receiver on its physical Wi-Fi address when a VPN is active, including global VPN mode. Pairing retains the saved receiver identity when its address changes.
- Add a manual connection check on iPhone and Mac. Network failures keep the saved pairing; authentication failures receive separate guidance. A successful check resumes eligible transfers without changing a user pause.
- When enabling Pixel original recycling, choose new receipts only or include historical receipts. The choice persists after restarting. Historical inspection also works with receiving and automatic recycling off, shows estimated reclaimable space, and requires confirmation. Missing, changed or unverifiable gallery copies keep their originals; gallery publication is not confirmation of cloud backup.
- Keep browser management access codes across restarts and updates. Set or reset a 10-digit code and revoke browser logins on Pixel. Browsers can optionally remember a separate login for 30 days; signing out revokes that browser. Changing the code revokes all browser logins without affecting transfer pairing.
- Explain receiving-port conflicts and unavailable Wi-Fi addresses with specific recovery steps. Pairing displays the same startup failure and avoids repeated generic alerts.
- iOS TestFlight uses version 0.2.0 (build 46). Availability of the new build depends on Apple processing and beta review.

# RC 2 — BackupDuck Android signing identity (0.2.0-rc.2)

- Use a dedicated Android release certificate named BackupDuck. The old certificate is no longer used for new releases.
- Android RC.1 cannot update in place to RC.2 because its signing certificate differs. Preserve originals and receiver records before switching to a fresh installation. Photos already saved to the gallery or cloud are not actively removed by the installer.
- Keep the existing iOS/macOS identities and protocol 2. macOS RC.1 can update normally through Sparkle.

# RC 1 — 备份鸭 / BackupDuck (0.2.0-rc.1)

- Launch BackupDuck / 备份鸭 with the duck icon, a renamed repository and website, and unified app identifier `app.backupduck` on iOS, macOS and Android.
- Install the new app on every sender and Pixel receiver, grant permissions and pair again. The old app database is not migrated. Existing apps, original photos and already saved gallery/cloud copies are not removed or modified.
- Rename Rust crates, native libraries, C ABI, discovery, headers, metadata and export identifiers. Protocol 2 uses `/v2/` routes and a new bundle signature; old apps cannot communicate with the new receiver.
- Keep the existing lossless photo/video processing. Fallback delivery filenames now start with `BD_`; preserved original filenames still follow the current naming rules.
- Downloads and update checks use https://backupduck.vercel.app. iOS TestFlight uses version 0.2.0 (build 44).

# Beta 38

- Recognize JPEG, PNG and HEIC image data before Android date handling and gallery publication, even when a camera export has an incorrect filename extension. Supported HEIC Live Photos keep their original image, video and audio without compatibility conversion. Retained failed originals can be retried after updating.
- Apple senders prefer the PhotoKit resource type when declaring the media format instead of relying only on the filename extension.

# Beta 37

- Publish burst JPEGs that contain multiple standard XMP packets without recompressing the image. Each existing packet retains its unrelated metadata and receives the same burst group marker. Previously received failures can be retried on Pixel without sending the originals again.

# Beta 36

- Distinguish specific lossless burst-JPEG packaging failures, including MPF and XMP variants, while retaining every received original for retry. Receiver diagnostics and browser details now expose the failure category without exporting photo content.
- Separate the Pixel's gallery-record export from log retention and log export in Settings.

# Beta 35

- Restore lossless packaging for older iPhone Live Photos whose paired QuickTime movie starts with `wide` instead of `ftyp`. The Pixel now accepts a complete `wide` + `mdat` + `moov` container, keeping the JPEG image data and original video/audio bytes. Previously received items can be retried without retransmission or compatibility conversion.

# Beta 34

- Add a Pixel settings export for gallery publication records. It lists saved filenames, byte sizes, checksums and times without exporting photo contents or login credentials, so users can reconcile backups with any destination.
- Persist the exact published filename for new transfers so a local Chrome audit can compare Pixel receipts with the Google Photos timeline. Existing receipts are resolved from the Android media index when available.

# Beta 33

- On the Pixel receiver, pairing can now start receiving automatically. Choose the iPhone code or Mac scanner even when the receiver is stopped; the requested pairing step opens once the receiver is ready.
- Explain the pairing choices and show a useful error when the receiver cannot start, instead of leaving the pairing buttons disabled without a reason.

# Beta 32

- Show live Pixel battery temperature, charge level, free space, and BackupDuck original usage in browser management, including the existing heat-pause state and threshold.
- Keep the transfer table to file, state, capture time, and size; receive-complete time remains in item details. Use “实况” consistently in Chinese across the apps, and identify burst frames from their metadata, with a burst filter and primary-frame detail.

# Beta 31

- Simplify the Pixel browser transfer table and add a per-item detail view for sender, media type, three local timestamps, receive progress, retained-original state, and processing guidance.
- Add a status guide and receiver-side numbered pagination with 20/50/100 items per page, page selection, and direct jump. Filters apply to the full history before pagination.

# Beta 30

- Redesign the Pixel browser dashboard with a compact overview, storage status, and a transfer table that filters by state and media type.
- Show capture, receive-complete, and phone-gallery publication times when available. New receiver events record their timestamps; older records stay marked as not recorded.
- Refresh visible data automatically every eight seconds, with an on/off control and manual refresh. Loading older pages pauses list refresh to keep the table stable; the overview continues to update.

# Beta 29

- On Mac and iOS, the “Back up selected” confirmation now includes an off-by-default option to back up items already received by the current Pixel again. Pending transfers are never duplicated.
- A repeat backup creates a new gallery copy. When the Pixel still has the same verified original data, the transfer reuses it instead of uploading identical bytes again.

# Beta 28

- Add optional browser management to the Pixel receiver. From a computer on the same trusted Wi-Fi, view live receiver totals and transfer history, filter failures, and retry failed gallery processing.
- The page is off by default and uses a temporary code shown on the phone. It serves local, unencrypted HTTP while enabled; do not use it on public Wi-Fi. Gallery publication still does not confirm Google Photos cloud backup.

# Beta 27

- Add a receiver setting for Live Photo compatibility conversion, off by default. Every Live Photo first tries to retain its original image and video. Only an input the direct packager cannot handle may be converted when the setting is on.
- When conversion is off and required, keep the received originals and show “Compatibility conversion needed” in Transfers. The failed item can be retried after enabling the setting; it is not counted as published to the phone gallery.

# Beta 26

- Preserve the original video and audio when packaging supported JPG+MOV Live Photos. Four cloud samples that were static or unable to load their animation were verified to play in Google Photos on iOS after correcting only their Motion Photo container metadata and layout, with no image, video, or audio encoding.
- Keep the JPEG container fixes from beta.25: describe the MPF auxiliary image and put the video at the exact end of the file. Codec conversion remains a fallback for unsupported inputs instead of running for every JPG+MOV pair.

Mac requires Apple Silicon and macOS 14+. Android requires arm64 and Android 10+.
iOS 17+ is available from source. Existing gallery/cloud copies are not changed by updating the app. Receiver gallery publication and Google Photos cloud backup remain separate states.
