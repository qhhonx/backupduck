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

All-grid density is independent: one/three/five/ten/twenty/thirty columns.
Menu Zoom In/Out and pinch alter density without changing hierarchy or filters.
Above five columns, tapping an item first expands around that item. The original
aspect option requests an uncropped fit thumbnail and changes row geometry,
without changing identity or membership. Tiny mosaics use image-only cells,
omit badges, and request a smaller bounded thumbnail target.

## Chrome

The newest capture edge is the default resting position. Under the Library title,
show the actual filtered total at that edge; while browsing older items show the
visible capture interval. Do not manufacture iCloud sync status from transfer
or thumbnail observations. Filters live in the named native options menu; Select
is a distinct trailing action. Years and Months relinquish the Library heading
and expose their period headings within the content.

On supported iPhones, the chronological collection is registered with the native
TabBar controller and uses `onScrollUp` because its newest edge is bottom aligned.
The system owns minimization, the compact Library button and expansion; do not
replace that shape change with whole-bar hiding. Years/Months/All is attached as
`UITabAccessory` content only in its inline environment, then detached after the
native bar expansion settles. Full navigation must not acquire a second accessory row.
A compact native Library button can expand navigation without moving photos.
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

A cover transition resolves the destination by the actual asset's member range,
uses a bounded visible-scene snapshot plus the selected cover, and releases both
on completion or interruption. Native property animators settle the hierarchy.
Menu/gesture density transitions retain a current geometry snapshot, update
collection attributes and content offset together, retain the initial pinch focal point,
and settle the column edges at release. The destination's first-row slot offset
keeps the touched asset near its current column, instead of translating the entire
grid offscreen when column remainders change. Every real asset retains its identity
and membership; no placeholder assets are inserted. Gesture cancellation restores its start
density; a remaining single finger does not replace the final two-finger center.
Pinch suspends collection panning; translating both fingers cannot drag a canvas.
Loaded pixels survive density settling, and unchanged cell classes are not reloaded.
A second finger cancels range selection and restores its baseline before pinch.
Content boundaries constrain vertical anchoring. Reduced Motion adopts
the destination and anchor immediately.

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
