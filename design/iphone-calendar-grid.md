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
replace that shape change with whole-bar hiding. Years/Months/All is attached as
`UITabAccessory` content only in its inline environment, then detached after the
native bar expansion settles. Full navigation must not acquire a second accessory row.
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
backup action. Review displays selected items only, supports deselection and
shares one selection set with the main grid. No media deletion is added. Backup
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
three viewport images are retained at up to 2x display resolution. One early
poster refresh is permitted; there is no per-frame layout/snapshot reconstruction.
Release settles scale and opacity over 280 ms before exposing the actual native
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
