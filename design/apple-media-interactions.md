# Apple media interaction contract

## Consent and settings

PhotoKit may load iCloud previews automatically within system Photos access and
network policy. There is no separate app preview switch or consent sheet. Loading
remains on the current media ring; unavailable media offers retry. This permission
to browse does not register a backup, request originals for transfer, or change
backup scope. Visible requests receive the bounded cloud slots; off-screen
speculation remains local.

Every persistent Boolean uses the shared preference row: label on the leading
edge and a switch on the trailing edge. Never rely on the platform's automatic
Toggle layout inside an unconstrained card. Mac and iPhone retain their existing
41/52 pt row minima and insets.

Backup scope has two summary rows: media types and albums. Both open a separate
editor; the parent never expands an unbounded album list. Type names and icons
match the library filter vocabulary. Photos, Live Photos, videos and bursts are
disjoint selectable categories in both browsing and backup scope. The All
filter includes every category. Album selection has search, user albums with any previously specified system choices,
selection count, local cover thumbnails, unavailable selections and a clear
All albums switch. Enabling it clears individual choices; choosing an album disables it. Disabling it with no choices remains an empty restricted scope, never an implicit expansion to all albums. Unavailable retained IDs remain restrictive. iPhone uses three reusable cover columns and an item-count
unit. Media-cell selection follows the shared bottom-trailing badge contract.
A cover tap or click chooses; the long-press or secondary-click menu opens the
album read-only in the shared library grid, and Back restores the picker as it
was. The system pickers have no album-level choice: PhotoKit's picker opens an
album on tap and selects individual items inside it, so there is no system
gesture to reuse for choosing a whole album.

Type and album dimensions intersect; changes apply to new discovery and the next
existing-library snapshot, not queued jobs. Manual selection remains authoritative.

## Viewer

Media is the dominant surface: aspect-fit image on the system background (white
in light appearance, black in dark), as in the system photo library. A tap hides
or reveals the chrome and turns the background black while hidden. The chrome is
the system's (A8 in `platform-expression.md`) and composed as the system photo
library composes it: back, a date-and-time title capsule that opens the
information panel, and More at the top; Share and Info at the bottom, as the
system's read-only viewers place them. The photo's backup state rides on Info
and is quiet when normal: no mark once the photo is in the Pixel's Photos, a
small accent dot while it is not there yet, the `attentionGlyph` colour when it failed,
and a progress ring only with real progress. Back Up and Retry live in the
panel's backup card and in More. Marks change with the system's symbol effects. The information panel has no close button; it closes by dragging down,
by Info or by the title. The filmstrip shows only while browsing. The viewer is read-only: do not copy
Apple/Google editing, deletion or cloud-backup controls that BackupDuck does not
implement.

iPhone uses native continuous page scrolling with a narrow gap. During a drag,
the current and adjacent media remain visible and move with the finger. A short
drag returns to the same page; a committed drag settles before loading the next
neighbours. Keep at most the current page and its two adjacent native pages; prepare
two local neighbours in each direction with bounded model retention. Do not clear the
current poster when higher quality arrives. Zoom/pan owns horizontal movement
above fit scale. Horizontal paging must not hijack the video timeline or Live
Photo press-to-play. Native deceleration handles paging; do not approximate it
with an onEnded image replacement.

The fitted viewport is the full screen beneath overlay controls, so hiding
chrome or magnifying does not move the fitted photo's centre. The pager uses a
40 pt inter-photo gap and native paging deceleration; this is a reproducible
implementation choice rather than a proprietary curve claim. First/last slots
are hidden and scroll bounds bounce at the real endpoint instead of revealing
duplicate photos. A single-item review cannot page to a second copy.

On iPhone an upward drag opens an information drawer in the same viewport, moving
the media into the remaining space. The photo remains visible. Use capture date,
filename/type/dimensions, camera/exposure fields and an optional map for actual
location. Missing EXIF is omitted. Location uses existing asset metadata and
never asks for device-location permission; the map loads when the information panel opens. Dragging the drawer down closes it;
a downward drag on fitted media moves only the actual media rectangle and dismisses the viewer.
The live media remains attached to its page while a snapshot makes the return
flight. Its asset aspect ratio is
stable from the initial poster through high-quality replacement; hosting safe
areas cannot change the fitted rectangle at the transition handoff. Page identity,
neighbour rotation and the new centre offset are adopted in one update at settle.
Direct thumbnail scrubbing uses uniform compact spacing; the current item
expands with side space after deceleration. Reversal restores the
original state. Zoomed media pans instead of dismissing.

Distinguish page-driven motion from direct thumbnail scrubbing. During page
motion, the two adjacent thumbnail widths and surrounding space interpolate
continuously with fractional page progress, including reversal. Direct strip
dragging uses uniform 20 pt thumbnails at a 23 pt pitch, preserving the touched
position while compacting. Settled thumbnails are 30 pt tall; the current width
uses the asset aspect with bounded expansion. Page commitment must preserve the
strip's current geometry before recentering. Entry and media return animate a flying image or snapshot's uniform scale and
local rectangular crop on the same timing owner. Video entry retains a poster cover while AVKit initializes
behind it; drag and return keep the player attached. Downward scaling keeps the original grabbed point under the finger;
after downward intent is established, horizontal and reversed vertical motion
remain continuous until commit or cancellation. Information restores readable
controls after magnification has hidden them.

Media pages have a synchronous native surface with asset-derived fitted bounds,
even before a poster arrives. Seed entry from the displayed source thumbnail;
an evicted cache must not disable the flight. A grid thumbnail is a centre crop:
inside the native page's full-aspect surface it occupies its true centred region (aspect fit),
never a magnified fill, so the full-aspect image that replaces it only adds the
sides. The viewer first requests the device's small full-aspect rendition
locally without network. Entry waits up to five frames for a full-aspect
rendition, or up to twenty frames while no picture is available. Any full-aspect image replaces a crop, because a crop
alone leaves empty bands, worst for panoramas whose original is still downloading. Photo, Live Photo and video content
update inside that same surface. AVKit stays below its poster until its first
frame is ready; loading cannot replace the flying snapshot or reset its transform.
The flying image or snapshot retains its fitted geometry while loading
continues in the attached media page.

The media's lower trailing corner owns one compact loading indicator; selected
review places it at the leading corner beside the separate selection mark.
On iPhone, local rendition loading retains the poster without a ring; a download
shows determinate progress only when the media provider reports it. Keep
date/time stable and omit parallel header loading text, spinners and linear
progress. A small local cloud symbol offers the available cloud action; a failed
explicit download retains the poster and exposes Retry. This does not remove
automatic PhotoKit cloud loading and system access restrictions.

Information tracking moves the photo and the panel together. The open height is 54% of the viewport; project drag velocity to settle or
cancel. Fade chrome continuously with panel travel.
Selected-item detail disables information from both upward gestures and
accessibility actions. Its Done action uses the same prominent circular check
treatment as selected review. Filmstrip emphasis comes from geometry alone;
do not draw a white selection border.

Mac uses the system window background, keyboard/trackpad navigation,
unobtrusive edge arrows and an information sidebar. It shares media loading and metadata, while
retaining desktop window and keyboard conventions. Paging animations move the
media; controls stay fixed. Show real loading/recovery in a bounded overlay.

## Grid density and calendar

The [iPhone calendar grid](iphone-calendar-grid.md) defines Years, Months and
All, independent density stops, focal anchoring, reversal, release and native
adoption. The [Mac Photos library](library.md#7-mac-photos-library) defines the
Mac cover hierarchy and independent All Photos size. Both retain stable asset
identity, bounded virtualized media work and immediate anchored adoption under
Reduce Motion.

## Media and settings requirements

Single-column photo cells request uncropped renditions. Their aspect-fill crop and
viewer return flight must represent the same part of the asset; do not substitute
a square rendition at the handoff. Selected video duration reserves space before
the bottom-trailing selection badge. The selection toolbar names its backup action.
Metadata uses concise field labels, including Resolution; Live Photo still-image
size remains explicitly distinguished from the combined resource size.

Cache settings distinguish browsing thumbnails from temporary backup files and
the device free-space reserve. Byte values share the same trailing value and
menu-indicator slots. Thumbnail clearing shows a stable in-row busy indicator,
refreshes measured usage on completion, and reports deletion failure. Browsing
may subsequently generate new thumbnails; clearing does not delete originals.

A larger local-rendition miss must attempt PhotoKit's tiny local rendition before
its visible cloud upgrade. Deliver these pixels immediately, keep cache tiers
separate, and re-arm cancelled cell work when UIKit displays that cell again.
Single-column crops retain available fallback pixels while requesting uncropped
renditions; an aspect mismatch is not a reason to leave a populated asset blank.
Progressive detail callbacks cannot replace sharper source pixels with a smaller
rendition. Unavailable backup controls absorb their toolbar touch region, even
when native transparent navigation would otherwise pass taps to the grid.
Information values wrap fully; accessibility sizes place values below their keys.
The map uses a Capture Location accessibility label and a pin with no duplicate
visible title.

### Explicit viewer downloads

Opening or paging to one asset explicitly permits PhotoKit network access for
that asset's display image, video or Live Photo. Keep the available poster on
screen while the existing small media progress indicator reports downloading;
replace it when the display media arrives. Adjacent-page posters remain
local-only; visible grid thumbnails follow the bounded automatic preview
network policy. A failed download retains the poster and shows
`library_preview_icloud_failed` with Retry on both Apple hosts.

An authorized library with no matches for its media filter or backup view uses
`LibraryPlaceholder.filterEmpty`: No Photos Match, Try another filter, and Show
All Photos. That action resets both choices. Access and genuinely empty-library
states retain their own placeholders.
