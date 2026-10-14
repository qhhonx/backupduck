# iPhone calendar browsing

This contract supersedes the phone All/Days/Months density coupling in older
media prototypes. Desktop calendar behavior remains separate. The focused
[native reference](native-grid-preview/README.md) uses only generated media.

## Hierarchy and density

Years, Months and All are browsing levels, not different thumbnail counts.
Years show one actual dated cover per year. Months group actual day covers into
mosaics under month headings. A cover opens the next level at that cover's asset;
a month day cover opens All at the corresponding capture day. Covers are chosen
by deterministic capture ordering; they do not claim Apple's private curation.
All preserves every accessible presentation item, including burst grouping.

Two browsing paths remain independent. The period control opens curated-layout
indexes: year cover cards, month day mosaics and All. Pinch inside these cover
indexes moves out through Years → Months → All, or reverses that hierarchy.
All-grid pinch uses one/three/five columns, then dense month and year overviews
at ten/twenty columns. Twenty columns is the terminal overview: a further inward
pinch does not create another year mode. A held gesture can cross several stops,
reverse without lifting and keep the same photo/focal point. These overviews
change presentation only, not asset membership, filters or backup scope.

Month layouts contain one through six actual day covers. One uses a landscape
card, two use portrait cards, three use a two-by-two hero beside two squares;
four use a wide hero above three squares. Five/six fill a three-by-three module
with a large square, a small side column and one wide or two small bottom cards.
Alternate modules/months mirror the composition. Date order follows the small
left column before a right hero in mirrored layouts. All tiles retain their
actual day ranges; native visible lookup sorts frame positions, not day identities.

The original aspect option preserves fitting without changing membership.
Dense mosaics omit badges and request bounded smaller thumbnails.

## Chrome

The newest capture edge is the default resting position. Under the Library title,
show the actual filtered total at that edge; while browsing older items show the
visible capture interval at one/three/five columns. Dense overviews replace this
interval with period captions: bright month/quiet year, or bright year alone.
Colliding captions are suppressed with a minimum gap; only the current caption pins. Do not manufacture iCloud sync status from transfer
or thumbnail observations. Filters live in the named native options menu; Select
is a distinct trailing action. Years and Months relinquish the Library heading
and expose their period headings within the content.

On supported iPhones, the chronological collection is registered with the native
TabBar controller and uses `onScrollUp` because its newest edge is bottom aligned.
The system owns minimization, the compact Library button and expansion; do not
replace that shape change with whole-bar hiding. Years/Months/All occupies a
centered material surface beside the compact native Library button. Observe
public UIControl geometry and ancestor visibility; do not depend on private
UIKit class names or selectors. The compact icon's actual visibility owns period
controls, rather than collection offsets, idle timers or an accessory environment.
A regular UITabAccessory reserves a second glass row and is unsuitable here.
Entry rises from below while the native bar contracts; expansion fades without
moving down. The surface retains stable bounds while animating its transform.
A compact native Library button expands navigation without moving photos. A second
tap on the full Library tab animates to the newest edge of the current level.
No return-to-latest arrow is added. The subtitle's latest-edge state is independent
of the system's bar-restoration timing.

Navigation actions are native `UIBarButtonItem` values. Browsing uses a separate
Select action and filter. Selection uses the native Close and confirmed-backup actions alongside the
existing filter; update the items with the animated navigation-item API.
The system owns group materials, sizing and transitions; custom button containers
must not imitate them. The app still owns selection state, wording and menus.

A compact centered count/review control retains the app action surface while the
tab bar is hidden for selection. Zero selection displays Select Items; only selected
media have a check mark. Backup stays beside the filter in the native header. The app owns its readable material, count,
presentation timing and review destination. Legacy systems retain an interruptible
navigation/browsing/selection fallback with readable material or solid controls.
Semantic text and surface colors preserve the BackupDuck theme. Reduced
transparency and motion preserve state and location.

Selection replaces browsing controls with a count/review action and the existing
backup action. Entering selection preserves hierarchy, density and focus. Pinch
remains enabled. Cover/overview taps drill down one level without selecting;
only individual photos in one, three or five columns toggle selection. Review displays selected items only, supports deselection and
shares one selection set with the main grid. Review defaults to three columns.
Its leading browse icon opens the same native media viewer over a stable snapshot
of this review batch, in library order. It never pages into unrelated library
items. Deselecting does not remove the current page; this permits reselecting it.
Back or a downward media drag returns to the review grid's current-item frame;
Done closes the review and retains the edited main-grid selection. The viewer
uses the same entry, paging, zoom and filmstrip interactions as ordinary browsing.
Current-item selection and Deselect All update the shared selection immediately. No media deletion is added. Backup
continues through the existing confirmation and durable registration workflow.

## Motion and performance

Period-control transitions resolve visible photo IDs in both layouts. Matching
photos move individually while unmatched content fades without whole-grid scaling.
When year/month cover pixels differ inside the same period, one cover changes
size and crossfades its actual images. The bounded source snapshot masks matched
photos to prevent duplicates. Cancellation/interruption releases overlays and
restores visible cells; Reduce Motion uses an immediate state change.

Pinch uses bounded viewport snapshots rather than interpolating every cell frame.
The incoming layout is prepared once per density bracket beneath the overlay,
with its focal photo aligned to the original finger center. The source fades out
while the incoming layout scales from its enlarged state. Continuing the same
pinch changes brackets; reverse motion uses the same canonical scenes. At most
three viewport images are retained at up to 2x display resolution. At most three
pixel-only refreshes fill missing images in each visible face using its own
immutable viewport and geometry. Keep already-painted pixels even if an image
cache entry is evicted; stale callbacks cannot change another bracket or its anchor. There is no
per-frame layout/snapshot reconstruction. Release settles scale and opacity over 360 ms before exposing the actual native
collection. Cancellation crossfades back to the initial scene/context. Panning is
suspended while pinching; translating fingers cannot drag a canvas.

The focused visible calendar cover may play a muted looping video. Years rotate
among actual month representatives with a crossfade after idle time. The period
identity stays unchanged; tapping uses the currently displayed asset. Only one
cover player/request runs, stops on scroll/background/navigation/reuse, and honors
existing iCloud preview consent. Passive covers never present permission sheets.
Low Power Mode and Reduce Motion retain static posters. Cover candidates warm
with calendar metadata; no full-library image/movie prefetch occurs.

Calendar metadata and year/month geometry warm in background tasks with generation
checks. No full-library image prefetch is allowed. Native visible-rectangle lookup,
cell reuse, cancellation and bounded image/geometry caches remain mandatory.
Selection range gestures retain a baseline, reverse without retoggling outside
items, and scroll near viewport edges. Changing authorization/membership cancels
obsolete work. Queue-state badges come from the existing source-state projection.

## Checks

Compare system Photos through actual original-speed simulator interaction, then
inspect the workbench and production host separately. Check cover-to-cover and
cover-to-All anchoring, menu and reversed pinch, dense grids, aspect fitting,
period boundaries, selected-only review, range selection, old/current systems,
light/dark and larger type. Include a genuine mid-library test: a downward drag
moves into history from the newest resting edge. Wait for the actual settled density before asserting final coordinates: display-link
animation is not tracked by XCTest idleness. Tests do not establish exact
proprietary animation curves or physical-device performance.

## Navigation contrast and thumbnails

Photos remain visible behind the transparent native header. A translucent dark
edge gradient supports white title and semibold white subtitle; it never paints
an opaque canvas over media. The bottom inset follows the native safe area plus
6 pt, without reserving a second toolbar row. Phone display options use square
cells; original-aspect presentation remains a separate desktop capability.

Pinch holds the two-touch focal photo and uses only the last valid two-touch scale
at release. Once the adjacent layout is visible, release adopts that direction;
crossing additional stops has a separate reveal threshold to avoid overshooting.
Snapshot layer anchors include both source and destination focal coordinates,
and the live collection adopts the same destination before reveal. Release uses
a critically damped native spring over 360 ms; held progress directly tracks scale.

Thumbnail targets use 64-pixel buckets matching cell display pixels, capped at
1024. Dense cells request 64/128-pixel images, not large photo previews. A separate
16 MiB, 64-pixel memory fallback permits immediate reuse across size changes;
the normal cache retains the requested size tier. Both remain bounded and are
cleared together on policy changes. Nearby PhotoKit preheat is capped at 256
small or 48 larger assets. No persistent disk cache is introduced. Cloud-only
assets without local pixels still require the existing preview network policy.

Startup loading shares the existing title/subtitle region. Permission and empty
states retain their recovery controls. The native collection and header remain
mounted while metadata arrives; no separate centered loading page is introduced.

Snapshot rendering uses explicit chronological viewport rectangles, tile IDs and
cached pixels, rather than flushing a hidden collection's pending screen updates.
Destination clamping uses the adopted geometry height. Preheat the destination's
visible/nearby window at its own pixel tier before fading it in. Fast-format
PhotoKit results are terminal even when marked degraded; release their request
slots and cache that small tier without waiting for a second callback.

Gesture direction accumulates from the last meaningful scale sample, rather than
comparing only adjacent display callbacks. Slow motion must reach the same stop
at high and low callback cadences. Reset direction at each new gesture and consume
the recognized first pose even when release follows without a changed event.

Each viewport scene records which actual photo IDs already have pixels. Late
arrivals fill only missing IDs over that scene's prior image, without replacing
already-visible photos with empty cells or changing their overlays. Active bracket
requests survive a further density crossing; repeated reversals have a bounded
request pool, cancelled when the gesture ends or is interrupted.

## Cover sampling and local renditions

Months show one mosaic with at most six sampled day covers. Each sampled cover
owns the contiguous member interval it represents, preserving date navigation
and every asset even when the month contains more than six capture days.
Period buttons invalidate the adopted layout and publish its content size before
clamping the chosen asset's destination offset, just as density pinch does. A
button chain retains that asset until a manual scroll or another cover choice;
end-clamped cards do not redefine the focus as a previous year.
The initial loading header adopts media contrast when metadata arrives, without
waiting for a later scroll/resize. Its supporting label uses the title's actual
leading edge. All-grid content does not add a footer-sized blank padding.

Native bottom controls are observed through public presentation-layer opacity
and control geometry, not their already-updated model alpha. Period exit begins
when compact navigation is reselected, and stays suppressed until full navigation
has appeared. Full navigation and period controls must not overlap.

PhotoKit owns rendition generation and preview consent. Rebuildable iPhone
thumbnails also use a local disk layer keyed by asset revision, pixel tier and
crop mode. Small cells request only their own tier. A 64-pixel cached rendition
may bridge a larger request, but never fulfills that larger tier. Writes and
reads run away from the main actor. The disk layer defaults to 256 MB, uses least
recently accessed eviction and 30-day expiry, and skips writes near low disk
capacity. Cache settings expose its size, limit and clearing separately from
backup preparation. Clearing invalidates late writes and the memory layer;
original media and pending transfer files remain under their existing owners.

A distant return-to-latest keeps the outgoing viewport while warming the target
and then fades to that target, rather than traversing thousands of unseen rows.
Dense preheating scales with visible tile count within a bounded window.
These policies reduce repeat-load latency; no cache can guarantee that unseen
cloud-only media already has a local rendition.

References evaluated for layering and loader ownership:
[SDWebImage Photos plugin](https://github.com/SDWebImage/SDWebImagePhotosPlugin)
and [Nuke caching](https://kean-docs.github.io/nuke/documentation/nuke/caching/).
The app retains PhotoKit loading rather than adding a network-image pipeline.
