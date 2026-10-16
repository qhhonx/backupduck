# 0.4.0 — build 87

iPhone and iPad library

- Browse Years, Months and All Photos as in Photos, with one pinch core for
  every zoom step and level change, matched-photo motion between levels, and
  gapless month and year overviews with period labels.
- Open the library faster: the photo list starts loading while the app
  launches, and decoded thumbnails stored in memory-mapped tables fill the dense
  overviews without blank tiles or dropped frames.
- Keep browsing steady while iCloud updates the library, and reopen at the
  density last browsed.
- Show photos and videos in one native viewer with information (camera, lens,
  location, file and video length), Live Photo and burst browsing, a
  media-local loading indicator, and review of the current selection.
- Use the system bar transition and equal-size controls when entering and
  leaving selection.

Mac library

- Rebuild the Photos library around the same zoom core: Years, Months and All
  Photos with matched-photo level changes, six zoom stops including month and
  year overview mosaics, floating month headings and period pills.
- Select as in Photos: an outline around the photo, original aspect with the
  outline on the photo, marquee selection from any gap, and Left/Right that
  continue across rows, with Shift to extend.
- Open media in the window toolbar with an immersive mode, instant key paging,
  animated swipes (including over videos) and a return to the photo's cell.
- Scroll every density without dropped frames in Release measurements, and
  reopen at the grid density last browsed.

Both Apple apps

- Choose backup scope by media type and by album, with album covers in a grid
  and an All Albums switch.
- Manage browsing thumbnails in Settings: usage, a limit (1 GB by default, up to
  4 GB) and clearing, shown in the same binary units as the other caches.
- Load iCloud previews automatically; the separate browsing consent setting is
  removed. Browsing never registers preparation or backup work.
- Share sheet headers, loading and failure states across detail, activity-log
  and Help sheets.
- Offer the Mac app through TestFlight in addition to the direct download.
- Link the Telegram feedback group from Settings, above About, in TestFlight
  builds only.

The Android receiver is unchanged apart from its version.

Release metadata: version 0.4.0, build 87. Application identities, signing and
update feeds are unchanged from 0.3.0; see [upgrade compatibility](upgrading.md).
TestFlight availability is separate from the Mac and Android release.

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
