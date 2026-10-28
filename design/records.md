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

On iPhone the hub pushes this page inside the Backup tab's NavigationStack.
Backup History opens `all`, the Needs You card's View action opens `attention`,
and the earlier-photos card opens `saved`. The system push/back transition
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
   grouped by the day of its latest change (Today, Yesterday, then dates), newest
   first, paged as the user scrolls. Tile marks:
   - none: in the Pixel's Photos
   - arrow: sending or waiting to send
   - clock: received by the Pixel, being saved to Photos
   - exclamation: needs you (the same items as the cards)
   - all media marks over photos are white with a soft shadow (V5); attention
     icons in cause cards and photo facts use `attentionGlyph`
3. On iPhone records use a timeline. On Mac the shared native grid (`library.md` §5) has Zoom, Filter and collapsed Search. Filter has Show (All, Needs You) and Type (All Types, Photos, Live Photos, Videos, Bursts), with no separate Needs You capsule. There is no sort menu or status guide. The header line states the scope:
   "1,284 photos backed up to Pixel 8 Pro".

**Photo detail** (the shared viewer on Apple platforms, a bottom panel on Pixel):

1. The photo, large.
2. When it was taken.
3. Two facts, each one line with a mark and, when known, a time:
   - Sent to Pixel 8 Pro · today 10:42 (or Sending… / Waiting to send / the cause)
   - In the Pixel's Photos · today 10:43 (or Saving to Photos… / the cause)

   Google Photos backup is never shown per photo: it is always unknown to
   BackupDuck, so repeating it on every detail is noise. The history page says it once, as a footer.
4. At most one action, only when the user can act: Try again, or the
   explanation of where the fix is.
5. Quiet footer: file name, size, kind (photo, Live Photo, video).

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
- Day groups use the time of the latest change, so a photo backed up today
  appears under Today even if it was taken years ago. The detail shows when it
  was taken.

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
`backup_tasks` query. Needs You groups precede latest-change day groups; an item
appears once. Stable task identities drive animated membership differences.
Marks and progress observations reconfigure the visible native cell in place,
without a grid or section reload. Refreshes retain loaded page depth and the
visible date anchor. Photo-library thumbnails use the existing media pipeline;
folder thumbnails and originals use the file pipeline and security-scoped access.
Previous/next retains the current mixed-source collection and the shared backup
information inspector, including recorded information for unavailable originals.
iPhone Backup History uses its native timeline list.
