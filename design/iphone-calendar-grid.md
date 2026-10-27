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
indexes moves out through Years → Months → All, or reverses that hierarchy. As in
Photos, the cards do not follow the fingers: a pinch past a small threshold
triggers the ordinary level change once per gesture, anchored on the card under
the fingers.
All-grid pinch uses one/three/five columns, then gapless dense month and year
overviews at fifteen/thirty-one columns, matching Photos on iPhone. One column
shows each photo at its own aspect. Thirty-one columns is the terminal overview: a
further inward pinch only resists and does not create another year mode. A held gesture can cross several stops,
reverse without lifting and keep the same photo/focal point. These overviews
change presentation only, not asset membership, filters or backup scope.

Month layouts contain one through six actual day covers. One uses a landscape
card, two use portrait cards, three use a two-by-two hero beside two squares;
four use a wide hero above three squares. Five/six fill a three-by-three module
with a large square, a small side column and one wide or two small bottom cards.
Alternate modules/months mirror the composition. Date order follows the small
left column before a right hero in mirrored layouts. All tiles retain their
actual day ranges; native visible lookup sorts frame positions, not day identities.

Dense month and year overviews (15 and 31 columns) do not use one collection
cell per photo: a Time Profiler capture showed UIKit cell creation and reuse for
about two thousand cells per screen dominating the main thread while scrolling.
They draw strips of eight rows into bitmap layers instead (level of detail), on a
background serial queue: each strip's bitmap is filled once from cached pixels
and each arriving thumbnail draws only its own tile; the main thread adopts at
most one image per strip per frame. Strips abut on whole device pixels and tile
edges snap to bitmap pixels, so no seams appear. The collection keeps scrolling,
content size and period pills; taps and pinch anchors use geometry hit testing.
Adoption from a pinch draws the target strips synchronously from the adopted
pixels. Dense preheat is throttled and limited to half a screen ahead.
The original aspect option preserves fitting without changing membership.
Display-option zoom actions keep their menu open and can be repeated, as in
Photos; each step starts from the density being settled toward, and the menu
does not carry density-dependent enabled state that would require rebuilding a
presented menu.
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
centered material surface beside the compact native Library button. Prefer
public API. Private UIKit state may be used when public API cannot express the
behavior, after a standalone probe app has verified it on the target iOS release.
Guard every access (`responds(to:)`, KVO registration inside an ObjC `@try`),
keep a deterministic fallback, and re-verify on each iOS release. Selectors
that UIKit restricts to approved apps (for example `UITabBar._isMinimized`)
are unusable. The bar's actual minimization state owns period controls, rather
than collection offsets, idle timers or an accessory environment.
A regular UITabAccessory reserves a second glass row and is unsuitable here.
The floating tab bar's visual provider reports `currentMorphTarget` (0 expanded,
2 minimized) one or two frames before the morph; the controller observes it with
KVO after confirming the ivar holds an object that answers the getter. Entry waits
130 ms, until the platter has formed its circle, then materializes the glass, rises
14 pt and fades in on a 300 ms spring without bounce. Exit dematerializes in place
within 80 ms, before the expanding platter reaches the surface. Glass effect
changes ignore animation delays, so entry waits explicitly. Without the signal,
iOS 26+ uses the pre-26 browsing chrome and keeps minimization disabled. The surface stays in the tab controller's view, outside the
tab bar's own container. It keeps stable bounds while animating its transform.
Native `onScrollUp` does not restore at the newest edge, where Photos restores;
reaching that edge in All fades the period first, then briefly sets minimization
to never so the system animates the restore. The compact Library button only
expands native navigation and hides period controls. Morph observation never
initiates a scroll. Reselecting the already expanded Library tab animates to the
newest edge of the current level.
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
photos move individually while the outgoing level scales away from the viewer
(toward All) or recedes (toward Years) and the incoming level settles from the
opposite side. Motion starts at once, at full speed, on a critically damped
spring (stiffness 400, damping 40; about 90% complete in 0.3 s), matching
recordings of all four Photos switches; destination pixels sharpen in place
rather than delaying the start. Each moving photo carries both cells'
decorations at native size (period label, top shadow, badges): the source's fade
out while the destination's fade in, so the last frame equals the revealed cell.
Glass period headings materialize their effect and text with the motion, because
an ancestor's fading alpha does not fade glass. The navigation bar and subtitle
fade rather than appearing or disappearing at either end.
When year/month cover pixels differ inside the same period, one cover changes
size and crossfades its actual images. The bounded source snapshot masks matched
photos to prevent duplicates. Cancellation/interruption releases overlays and
restores visible cells; Reduce Motion uses an immediate state change.

All-grid pinch uses a live stage of virtualized tile layers rather than viewport
bitmaps or per-cell collection reflow. Each density keeps its own immutable
geometry; all faces share one on-screen lattice pitch, aligned on the focal photo
at the same in-tile fraction, so a density change crossfades contents while gaps
stay crisp. Tiles read the image cache and fill in as requests complete, at the
destination pixel tier; a late image never leaves a painted-blank tile. While a
face is smaller than its resting width, materialize the neighboring chronological
slots beyond each row's resting crop, with cancellation and reuse. Its logical
column count must not clip the animated viewport into empty side strips.
Choose each destination's leading row phase around the focal photo, keep it
stable through reversals, and adopt that same phase in the collection. Only the
remaining sub-cell horizontal alignment settles on release; an entire column
must not slide across the screen to restore a zero-leading-slot layout.
Ordinary faces use the collection's shared video-duration, Live Photo, selection
and backup-state decorations laid out at native cell size, then transformed
with the whole cell throughout motion. Font size, padding, corners and icon
strokes scale together; visibility follows the native density, not a changing
on-screen width threshold. Dense faces omit
these badges as their resting cells do. The stage and collection agree on badge
visibility, placement and selected-photo opacity before handoff. Pitch is
the starting pitch times the finger-distance ratio after a dead zone of about 13%
of the touch-down distance (at least 20 pt), with light resistance beyond one
column and almost none beyond the terminal 31-column overview, where a deep band
would expose canvas around the mosaic. A new adjacent preview needs deliberate travel; an established pair
reverses after about 1.5% size change from the current leg's extreme. Absolute
size alone does not select the photo mixture. Continued travel can reach further
stops without lifting. Photo blending runs independently of finger movement:
ordinary grids use a roughly 1.2 s full transition with a slow incoming start,
and dense overviews about 0.85 s. Reversal preserves the current visible mixture
and traverses its remaining phase rather than restarting a full fade. Layer
compositing preserves the mixture when its direction changes; late target pixels
can briefly defer the fade without removing the outgoing content. All faces clip
their images to the gap of the face being shown, scaled with the lattice and
switched in one frame when the preview changes, as in Photos: dividers never thin
below a pixel or blink line by line while photos crossfade. Tile edges snap to
device pixels from the lattice, so every divider in a frame has one pixel width
and adjacent dense tiles never show seams; minification uses mipmaps.

The date subtitle follows the nearest natural pitch, independently of the photo
fade. Release commits the current preview target rather than rounding the size;
an unrecognized deliberate short pinch still steps once. During the held gesture,
shrinking content retains the source layout's newest-edge scale constraint;
a mid-library focal point stays fixed until it reaches that constraint. The
incoming layout may end above the viewport bottom during the photo crossfade.
Do not move the shared focus as blend weights change to fill that space.
Cancellation restores the initial density and offset. Release is critically
damped (omega 12.5, fitted to Photos release recordings), bounds carried velocity
to prevent target overshoot, finishes any remaining photo blend within the settle
rather than holding a settled pose for a long held-gesture fade, and adopts the
native collection beneath the stage only when motion and blending finish. Adoption transfers the exact displayed images, placeholder
and badge state into visible cells before issuing replacement loads, retains the
same target geometry, and keeps the stage above one native display commit. A
late smaller preview cannot replace adopted pixels. This retention is bounded by
the visible tiles, not global cache survival. Additional scrolling edge effects
and the custom header gradient are disabled; system bars keep their materials.
A new pinch interrupts settlement in place; other
interruptions finish at the committed density. These are visible-motion
approximations, not claims about private framework parameters. Panning is
suspended while pinching; translating fingers cannot drag a canvas.

The focused visible calendar cover may play a muted looping video. The poster
is rarely the first frame, so the video dissolves over it once it has pixels
instead of cutting to a different frame. Years rotate
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

Pinch holds the two-touch focal photo and measures distance only from live
touches. Source-timestamped recordings of Photos on the iOS 27 simulator inform
the dead zone, preview threshold, crossfade and settle; they do not establish
proprietary internals.

Thumbnail targets use 64-pixel buckets matching cell display pixels, capped at
1024. Requests from 353 to 460 pixels (three iPhone columns) use 352: PhotoKit
cuts those from its stored small rendition, while slightly larger requests decode
the original (a measured cliff reported by other PhotoKit grids; verify per
device and release). Dense cells request 64/128-pixel images, not large photo previews. A separate
16 MiB, 64-pixel memory fallback permits immediate reuse across size changes;
the normal cache retains the requested size tier. Dense transition layers retain
their own small images rather than pinning a previously cached large bitmap in
every tiny tile; sharper return images remain separately bounded. These caches
are cleared together on policy changes. Nearby PhotoKit preheat is capped at 3072 small or 48 larger assets. A rebuildable
rendition disk cache retains asset/revision/pixel/crop keys, defaults to 1 GiB
(256 MiB to 4 GiB), expires old entries and shares usage, budget and clear actions
with cache settings. Settings shows usage and budget in the same binary units.
It never owns originals or queued transfer files. Foreground decoding runs outside
the cache actor; background encoding has bounded concurrency and retained bytes.
Reads never wait for the directory index: it is built in the background for budget
accounting, so a large cache cannot delay the first thumbnails after launch.
Small mosaic renditions (128 pixels or less) come straight from PhotoKit, whose
own small renditions are faster than a JPEG round trip; they skip the disk layer
and render-queue redraw, and use a wider bound of 96 active (24 speculative)
requests, while larger renditions keep 24 active and four speculative.

Decoded thumbnail tables follow the Fast Image Cache approach. Each table is one
memory-mapped file of fixed-size square slots holding already decoded,
64-byte-row-aligned BGRX pixels; a hit returns a `CGImage` that points into the
mapping, with no PhotoKit request, decode or copy. Slots are found by hashing the
asset identifier and revision over an eight-slot probe window; a slot header
stores the key tag and a recency tick, and is cleared while its pixels are
written, so a torn write reads as a miss. Slot sizes follow this device rather
than one model: the tile pixels of the widest grid the device shows (portrait
width on iPhone, long edge on iPad) at 31 and 15 columns, rounded up to 16
pixels. The overview table serves the 31-column mosaic and is filled for the
whole library in the background from local renditions, newest first, after the
library is published; the detail table keeps recently delivered 15-column
thumbnails. Both count toward the thumbnail cache budget (at most 50% and 20%;
renditions use the rest). At its limit a table only replaces the least recently
used entry in a probe window, and lowering the budget below a table's usage
starts that table over. Dense strips look tables up on their render queue and
resolve only misses on the main thread, and nearby PhotoKit preheat skips mosaic
tiles the overview table already holds: faulting their assets and touching
PhotoKit's preheat table had cost about 40% of main-thread time while scrolling
the 31-column mosaic on device. Larger cropped cells show a table entry,
upscaled, until their own rendition arrives; such soft placeholders do not
dismiss the sharper launch cover. The launch cover is disabled
(`usesLaunchSnapshot`): launch relies on table placeholders alone.

Launch path: the library model reads photo authorization synchronously at
creation, so the first frame builds the grid instead of the permission
placeholder; app init starts the default sorted fetch on a background task with
the library's change token, and the first reload adopts it unless the token has
advanced by the time the model's observer is registered. Cells create their
video layer only for a playing cover and share resolved symbols and colors.
Measured on a physical iPhone with a large library (Release, warm): grid view
on screen at about 155 ms, first cells with stored pixels at about 205 ms and
first sharp disk thumbnails at about 300 ms after process start, against about
410 ms for the first cells before. `-no-launch-prewarm` disables the early fetch
for comparison; the first library connection itself costs about 65 ms. `-no-thumbnail-table` disables the tables for
side-by-side measurement.
Disk reads, native acquisition and display preparation share bounded admission;
a cache hit cannot start an unbounded cover-decode burst. Pixels reach the UI
before background writeback finishes. Native slots then become available while
a separate 32 MiB/512-job combined admission budget retains writes and active
loads, preventing a fast producer from silently dropping reusable covers.
Visible requests overtake speculative warmup, which is bounded separately. A visible subscriber promotes a shared speculative owner without
starting a second load. Speculation does not initiate cloud acquisition.
Coalesced owners cancel independently, and clear invalidates late writes.
Cloud-only assets without local pixels still require the preview network policy.

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

Library changes arrive continuously while iCloud syncs. An identical rebuild is
ignored; a change during any motion waits for it to end. Applying a change keeps
cached pixels and the focused photo's screen position, or stays at the newest
edge; history indexed before the oldest edge keeps every existing row's
composition. The loading subtitle appears only before the first items exist.
Launch publishes the newest 600 items (first screen plus one pinch into the
month overview) before indexing the remaining library. When the app leaves the
foreground, the newest edge of the remembered density is rendered from cached
pixels and stored as a rebuildable launch snapshot with its density and window
size; the next launch shows it in the first frame and fades it once real cells
hold their images, so the canvas never flashes before photos arrive. Thumbnail
clearing removes it. Single-object PhotoKit access is slow on large device
libraries, so resolved assets stay in a bounded cache and dense strips and pinch
faces resolve their assets with one bulk fetch. That first slice is read with
one bulk PhotoKit fetch: enumerating a partial range
faulted objects individually on device (about 0.5 ms each). An opt-in launch
argument, `-launch-trace`, prints startup milestones for device diagnosis. The
next launch opens at three columns after one or three, and at five after five
columns, the dense overviews or a calendar level, as in Photos.

Stage tiles are pooled and keyed by tile index per face; leaving the viewport
cancels a tile's request. Faces that finish fading out are discarded with their
requests. Dense overview pills stay at reading size while the mosaic scales.

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

Period exit begins with the native expansion event and entry waits for the next
minimization. Full navigation and period controls must not overlap.

PhotoKit owns rendition generation and preview consent. Rebuildable iPhone
thumbnails also use a local disk layer keyed by asset revision, pixel tier and
crop mode. Small cells request only their own tier. A 64-pixel cached rendition
may bridge a larger request, but never fulfills that larger tier. Writes and
reads run away from the main actor. The disk layer defaults to 1 GiB, uses least
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
and [Nuke caching](https://kean-docs.github.io/nuke/documentation/nuke/caching/);
the decoded tables follow [Fast Image Cache](https://github.com/path/FastImageCache).
The app retains PhotoKit loading rather than adding a network-image pipeline.


## Motion and cache regression tools

The [repeatable experiment tools](../scripts/benchmarks/README.md) compare committed
and candidate pipelines and track original recording timestamps. Fit grid position,
size, autonomous blend and period entry/exit separately. Held gestures are not free
spring samples. Native period visibility follows compact-control visibility/expansion events and
presented icon coordinates. A measured animation clock starts with these native
events: title opacity can remain 1 behind a clipping mask and then change abruptly,
so it must not gate entry until after the icon shrinks. This is transition timing,
not an idle timeout. Interrupted transitions cancel without
running an obsolete commit completion. Test rapid hierarchy changes and metadata
replacement, preserve the real animated scroll-to-latest behavior, and prepare
local destination pixel tiers before cover travel with a bounded unavailable-media
fallback. Complete runtime navigation and source-frame review independently of
synthetic timing benchmarks.

Selection header actions use separate native material groups for filter, backup
and close. Transparent navigation gaps and the date strip own touch input while
selecting; an unavailable backup action must not pass taps to media beneath it.
Native scroll-to-top is suspended during selection so header taps cannot change
the collection anchor. Ordinary browsing retains system scroll-to-top.

Dense canvas strips retain their published bitmap independently of thumbnail
cache eviction. Starting another pinch seeds its source from those displayed
pixels, and adoption keeps the animation cover until replacement visible strips
have committed. Synchronous image callbacks follow context creation; recycled
strip publications are generation-specific. Gapless dense faces transform a
shared content node and refresh tile membership only at viewport boundaries.
Period captions remain at reading size; ordinary dividers retain pixel snapping.
