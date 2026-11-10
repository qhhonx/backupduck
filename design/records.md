# Records and photo detail

## 1. The user's question

An ordinary user opens records to learn one of three things:

1. **Is this photo backed up?** About one photo they have in mind.
2. **What is not backed up, and what do I do?** Only when something went wrong.
3. **Is it working?** Seeing recent photos arrive is the reassurance.

They never need: file names as the main label, four status filters, sort
orders, a status glossary, task counts in the thousands, or words such as
receipt, original, receiver, processing or task.

## 2. Information rules

- **Photos, not files.** Records are a photo timeline. File names, sizes and
  formats move to the bottom of the detail.
- **Problems grouped by cause.** One card per cause with a count and one action,
  as the hub does, instead of one row per failed file.
- **Status on the photo.** A tile is unmarked when the photo is in the Pixel's
  Photos; otherwise a small mark says sending, saving or needs you.
- **The three facts in the detail** (P3), each with its time when known.

## 3. Structure

**Records page** (opened from the hub; the Mac lists it in the sidebar):

On iPhone the hub pushes this page inside the Backup tab's native navigation stack.
Backup History opens `all`, and the Needs You card's View action opens `attention`.
The earlier-photo card has no record shortcut: `saved` contains all confirmed
photos for the receiver, not the frozen membership of an earlier-photo run.
The earlier-photo completion notification may still open `saved` explicitly.
The system push/back transition
retains the Backup tab. Recently backed up and Needs You live only here; the
Photos tab offers All and Not backed up. Hub attention and History Needs You
use the same core attention jobs and preparations. Waiting for an original is active;
preparation failures needing a person are attention. Under limited access,
unfetchable library identifiers are ignored and their source-unavailable
preparations are dismissed on the next observation. Under full access, a photo
deleted before it was backed up closes its preparation through the core (a
`source_removed` diagnostics event), because nothing is left to send; it leaves
Needs You and the timeline. Other full-access failures stay actionable, and Try
again prepares a photo without a transfer again rather than doing nothing. A
backed-up photo deleted from this device stays in the timeline as a quiet record
without a cover; its viewer explains the deletion and toggles chrome on a tap
anywhere.


1. **Needs you** (only when something does): one card per cause, in this order:
   - Live Photos that cannot be saved to Photos as they are. Kept on the Pixel.
     Action: View.
   - Photos that did not arrive complete. Action: Try again.
   - Photos whose original is not available on this device. Action: View.
   - Photos the Pixel could not save to Photos for another reason. Action: View
     (the fix is on the Pixel).
2. **Timeline**: every backed-up or in-progress photo as a thumbnail grid,
   paged as the user scrolls. iPhone and Pixel show the latest change first
   and group by day (Today, Yesterday, then dates). The Mac timeline runs from
   oldest to newest by the latest record update. It opens at the newest edge
   at the bottom and loads older pages above the visible records while keeping
   the viewport in place. Needs You keeps cause priority and opens at the top.
   Tile marks:
   - none: in the Pixel's Photos
   - arrow: sending or waiting to send
   - clock: received by the Pixel, being saved to Photos
   - exclamation: needs you (the same items as the cards)
   - all media marks over photos are white with a soft shadow (V5); attention
     icons in cause cards and photo facts use `attentionGlyph`
3. On iPhone records use a timeline. On Mac the shared native grid
   (`library.md` section 5) has Zoom, Filter and collapsed Search. Filter has
   Show (All, Needs You) and Type (All Types, Photos, Live Photos, Videos,
   Bursts), with no separate Needs You capsule. There is no sort menu or status
   guide. The native title is Backup History. Its subtitle contains only the
   visible record-update date, explicitly labeled Updated; selection replaces
   it with one selected-item count. The grid has no inline day headings or
   floating date capsules. Cause headings remain ordinary flow content and
   never become date captions. Below the final photo row, the shared footer
   shows the exact current collection total, then the known receiving device
   in secondary text. Missing media types use an item
   count; incomplete locally filtered results omit the total. These counts
   describe records, not confirmed publication or cloud backup.

**Photo detail** (the shared viewer on Apple platforms, a bottom panel on Pixel):

1. The photo, large.
2. When it was taken.
3. Two facts, each one line with a mark and, when known, a time:
   - Sent to Pixel 8 Pro · today 10:42 (or Sending… / Waiting to send / the cause)
   - In the Pixel's Photos · today 10:43 (or Saving to Photos… / the cause)

   Google Photos backup is never shown per photo: it is always unknown to
   BackupDuck, so repeating it on every detail is noise. On Mac, backup help
   carries this guidance instead of a permanent browsing footer.
   Apple fact rows retain a supporting-text slot of at least one semantic line
   as a status note or recorded time appears and disappears. Empty slots have no
   spoken content. Wrapped text and larger text sizes can grow the slot; no
   fixed height clips it, and missing times remain unknown.
4. At most one action, only when the user can act: Try again, or the
   explanation of where the fix is.
5. Quiet footer: file name, size, kind (photo, Live Photo, video).

Pixel recently received tiles and the Photos timeline use the same receipt-preview,
center-crop, loading/unavailable presentation, duration and status-mark component.
Recently received includes fully received originals that are still being saved or
need attention; it does not imply gallery publication. Status changes update the
existing tile without clearing an available picture. An unavailable grid preview
shows its type once in the center and retains any known duration without a second
type glyph. Available thumbnails use one fixed-size corner type glyph.

An unavailable video in the Pixel viewer has one centered, intrinsic-size type
placeholder and no central play action. The existing Photos action remains
available under its normal publication rules. Paging, reset and gesture handling
never scale or zoom this placeholder; fitted media keeps native zoom ownership.

**Pixel**: the same page as "Received photos", with the sending device on each
day group when there is more than one, and "Needs you" limited to what the Pixel
can act on (could not save to Photos, Live Photos that need conversion). The
detail's first fact reads "Received from Lin's iPhone".

## 4. Copy

English below; the zh-Hans strings (`records_*` keys in
`Localizable.strings`) follow `copy-glossary.zh.md`, using 存进 for "saved to".

| Place | en |
| --- | --- |
| Page title | Backup History |
| Scope line | %2$@ photos backed up to %1$@ |
| Needs-you header | Needs You |
| Live Photo card | %@ Live Photos can't be saved to the Pixel's Photos as they are · kept safely on the Pixel |
| Incomplete card | %@ photos didn't arrive complete |
| Original card | %@ photos' originals aren't available right now |
| Pixel-side card | %@ photos couldn't be saved to the Pixel's Photos · retry on the Pixel |
| Detail fact 1 | Sent to %@ |
| Detail fact 2 | In the Pixel's Photos |
| Detail fact 3 | Google Photos: BackupDuck can't see whether it's backed up |

## 5. Timeline rules

- Records are not a second hub. Current progress stays on the hub; the
  timeline only marks tiles.
- Problem cards group by cause and are computed from the attention items the
  core returns (bounded by its page size). A count above the page size reads
  "200+".
- Timeline order and its date labels use the time of the latest change, so a
  photo backed up today appears at Today even if it was taken years ago. On Mac
  that date is explicitly an update in the native subtitle. The viewer shows
  the recorded capture date separately; missing capture dates remain unknown.

## Pixel records

- **No thumbnails on Pixel problem cards.** Photos that could not be saved, and
  Live Photos that need conversion, have no copy in the Pixel's Photos, and the
  core cannot yet return a preview of a received original by ID. Each card
  keeps the count, the cause, one line and one action. Tiles for such photos
  show a type icon instead of a picture.
- **Card actions.** Live Photos: View (a sheet of just those photos). Could not
  save: Try again for every failed save; Live Photos fail again unless format
  conversion is on.
- **Detail action.** Try again for a failed save; Open in Photos only once the
  copy in Photos is found.
- **Copies removed from this Pixel.** Google Photos' Free up space, or the
  user, can delete BackupDuck's copies from the Pixel's Photos after they were
  saved. Saved photos beyond the copies still indexed in Photos are "no longer
  on this Pixel". The scope line and the hub note then say how many ("1,002
  photos · 997 no longer on this Pixel"); they never claim where the photos
  went, because BackupDuck cannot see Google Photos' cloud. The viewer shows a
  non-actionable "No longer on this Pixel" pill, hides Share, keeps Google
  Photos (which opens the app), and adds a detail fact: "If it was backed up to
  Google Photos, the original is there."
- **Receipt thumbnails.** After saving to Photos, the Pixel keeps one private
  320-pixel WebP picture per photo (about 10 KB) so removed photos stay
  browsable. Photos without a receipt picture get one when first shown while their copy
  is present. The picture is never evidence of any copy. Photos
  removed before they had one show the type icon. Completed photo and video
  requests show the receipt picture first. When it is smaller than the requested
  pixel size, tiles up to 640 pixels in both dimensions then use the system media
  thumbnail, cross-fading over the short 120 ms status-replacement duration
  (immediate with animations disabled). Larger viewer requests decode the copy;
  original image decoding or video frame extraction is also the fallback when
  the system thumbnail fails. Removed copies keep their receipt picture without
  a second stage. Both renditions share a memory cache sized to one eighth of
  the app memory class, with a 32 MB minimum. Resolved copy locations are retained
  until processing changes or a read fails. The grid prefetches the next row;
  cancellation remains owned by the requesting view.
- **Video duration.** Pixel timeline and problem-detail grids show a known
  duration immediately left of the video glyph at the top trailing corner;
  selection remains top leading and processing state remains bottom trailing.
  Use the caption style, semibold white text with a soft shadow and no pill over
  photos; unavailable previews use the secondary-text role on the solid surface.
  The clock rounds real positive milliseconds to the nearest second. Below one
  hour it uses `m:ss`; from one to 99 hours it uses `1h02` (hours and minutes,
  omitting seconds); from 100 hours it uses `100h` (hours only). Detail and the
  tile's accessibility description retain the full recorded duration, including
  fractional seconds. Selection does not hide, move or shrink the duration.
  Unknown durations keep the existing video glyph without
  inventing `0:00`. Duration and its accessibility description load independently
  of thumbnail cache hits or decoding failures, with at most two concurrent
  independent duration reads and cancellation owned by each visible cell. A private
  display-metadata table retains positive durations by core asset ID across
  restarts and gallery-copy removal, with a 20,000-record cap and oldest-use
  eviction; a bounded memory cache holds 256 observations. Missing observations
  retry on a later binding after state changes or a short expiry. Publication schedules an optional
  index read without waiting or accumulating a backlog. No original-resource
  scan, frame extraction or location lookup runs for grid durations. Old failed
  publications without a readable indexed copy remain unknown. Retained or
  evicted duration metadata says nothing about playback, publication or cloud
  availability; an evicted duration can be recovered only from a present copy.
- **Scope line.** "1,284 photos · 1,277 in the Pixel's Photos"; it names the
  sending device only when one device sent everything shown.
- **Ordering.** The core pages a fixed read snapshot by latest recorded state
  change, newest first, with descending stable row ID as the tie-breaker. The
  Pixel groups this order by local day across every page; problem cards keep
  their position above the timeline. A refresh atomically replaces the loaded
  prefix from a new snapshot, so concurrent arrivals, retries and outcomes
  cannot duplicate or skip items in a paging pass. Expired cursors restart the
  loaded prefix rather than mixing snapshots. Records without a known
  change time form a final unknown-date group. The arrival-ordered operation
  remains available for existing hosts.

### Apple original preparation failures

Only absent PhotoKit resources and Photos errors `networkAccessRequired`,
`identifierNotFound`, `missingResource` and `notEnoughSpace` use the original
unavailable cause. Transient network, timeout, interruption and public cloud
throttling errors retain active preparation membership and retry through the
core's pending-source backoff. Other failures retain a retry action without
claiming the original is missing. Diagnostic events record error domain, code
and the public Photos case, excluding descriptions, paths and userInfo.

Mac folder-backed history tiles use the existing file thumbnail pipeline.
History and Overview open the file-backed viewer with its source scope, collection
and shared previous/next controls. An absent source retains recorded information
and the unavailable placeholder.

### Missing iPhone sources

A recorded photo whose source was deleted from this iPhone opens the ordinary
viewer with information collapsed. Its image area says Deleted from this iPhone.
Only a core job with received state and complete gallery processing adds The
backup on your Pixel is still there. Info continues to expose the recorded
facts; receipt alone cannot supply that reassurance.

### Recent activity on Apple

Diagnostics reads its local activity snapshot when the page appears, without
waiting for a foreground scene value to propagate through navigation. Returning
to the foreground refreshes it. Recent Activity shows up to six recognized
events, or its existing empty text after an empty or unrecognized snapshot;
unknown event codes remain available in diagnostic exports. Cursor identity is
independent of observation timestamps and event deduplication.

## Mac engine and continuity

Mac Backup History remains a cross-source page backed by the existing paged
`backup_tasks` query. It includes Photo Library and folder records; the Folders
parent browser is a separate aggregate of added folder media only. Needs You cause groups precede the continuous
latest-change timeline; an item appears once. Cause headings stay in the
document flow without date-capsule styling or pinning. Stable task identities
drive animated membership differences.
Marks and progress observations reconfigure the visible native cell in place,
without a grid or section reload. Refreshes retain loaded page depth and the
visible date anchor. Photo-library thumbnails use the existing media pipeline;
folder thumbnails and originals use the file pipeline and security-scoped access.
Previous/next retains the current mixed-source collection and the shared backup
information inspector, including recorded information for unavailable originals.

Mac Overview recent photos is a bounded native collection of at most eight
photos in two rows, using the same cells, gaps, media marks and missing-source
fallbacks as the full grids. It has no nested scrolling, totals footer, density
controls or multiple selection. A single click opens the shared viewer from the
visible photo. Opening retains the source cell's frame and displayed rendition;
returning resolves the current photo by stable identity in that same collection.
The collection can contain Photo Library and folder photos together; paging
must not discard the other source type. Recorded facts remain available when a
local source cannot be opened. Receipt and phone-gallery publication retain
separate marks and wording, including in this recent-photo collection.

iPhone Backup History use a virtualized UIKit collection with the same
media cell and decorations as the photo library and selected-photo review.
The history adapter supplies stable recorded task identity, latest-change day
groups, backup marks and paged membership; access to a source only enriches its
thumbnail and media metadata. Missing sources retain their record and fallback
viewer. Live Photo marks stay at the top leading corner and known video duration
at the bottom trailing corner, with the same small-tile visibility and selection rules.
An unknown video duration uses the shared video glyph without inventing a time.
Scope, problem cards and the cloud note remain supporting content around the
timeline. State observations retain the loaded page depth and visible anchor;
opening, paging and returning from the shared native viewer retain the timeline.
The first lookup remains loading until it resolves; an empty state requires a
completed lookup. A retained hidden timeline still receives state updates, with
membership changes applied without animation until it becomes visible. A link
to a record follows its source if preparation becomes a transfer and selects
only after the matching item has been found.
