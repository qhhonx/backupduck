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
and is quiet when normal: receipt confirmation and gallery-saving waits leave
it unmarked, as do original preparation, queue scheduling, retry and pause.
A small accent dot identifies an unbacked photo outside active work;
the `attentionGlyph` colour marks failure, and a
progress ring appears only with real partial transfer progress. A native request
returning to the queue after all media bytes are acknowledged stays a receipt
wait; it does not restart the ring or dot. Back Up and Retry live in the
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

Video entry keeps AVKit in its normal render tree beneath the poster. The poster
releases its pixels only when the native player has a displayable frame and the
opening flight has released ownership. Player controls and input become available
at that handoff; the entire player is never faded to prepare its first frame.

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
Sources that own thumbnail visibility keep the actual thumbnail hidden while
the viewer owns it. Return snapshots retain that source's native empty surface
and clipping; a geometric patch must not leave sampled thumbnail pixels around
the vacancy. A sheet return keeps the source sheet’s native corner clipping on
every grid snapshot. Its navigation controls retain the source bar’s vertical
position throughout entry, return and cancellation. The viewer has its own native
navigation controller presented above the source. The source keeps its navigation
stack, bars, tabs and native material unchanged below it; a source sheet retains
its bounds and corner clipping. Flying media stays below the filmstrip and native
bars; the strip participates continuously in entry and return. Selected-detail marks stay hidden while media
flies and return only with the settled live page. Cancelling a return keeps source ownership with the open viewer.
During entry, the native destination bars and their material remain live at
natural opacity. A single source composition dissolves above the destination;
matching media copies in the two planes share one image, crop and native timing
owner so the moving photo stays opaque. Entry does not capture destination glass
or switch its material at completion. The source cover is installed before any
destination layout can expose pixels and retains source-sheet clipping.
During interactive return, chrome follows drag progress and the release
animation with the backdrop. Floating system groups use bounded, transparent
native snapshots while live bars are hidden; cancellation resumes the native
controls atomically. Return capture preparation keeps the previously visible
surface on screen and excludes media content, so fading controls cannot retain
a second photo or dark strip.
Hidden chrome
stays hidden through reversal and release; cancellation restores the viewer's
previous chrome state. The source's visible native controls regain input when
the transition completes. Native presentation retains the media root and its
flying snapshot throughout the interaction.
The source grid retains its effective content insets and thumbnail positions
throughout the viewer handoff, including cancellation. Its grid, navigation and
tab materials remain one native composition below the viewer. They are revealed
continuously by the viewer backdrop, including the photos underneath floating
tabs; container snapshots must not replace those photos with an empty backing.
Source controls remain below the flying image and cannot receive input until the
source becomes active. Cancellation retains the viewer's native placement, media
viewport and input ownership. Native presentation owns status-bar routing; the
viewer keeps that ownership until completion. The source retains its viewport and
effective insets until its bars have completed their handoff, then resumes native
safe-area adjustments. Grid content accounts for safe areas once.
Album browsing uses a transparent native navigation background with system
floating controls and scroll-edge legibility; it adds no full-width material bar
over the media.
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
On both platforms, local rendition loading retains the poster without a ring;
when no poster exists, an indeterminate indicator occupies the same corner.
A provider-reported download fraction, including zero, immediately uses that
same indicator as determinate progress until the actual request finishes. Keep
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
Fitted full-aspect detail previews are another thumbnail resolution. Viewed
previews share the grid cache's user-selected disk budget, usage and clearing
across Photos, recent photos and history, including after relaunch. Identity
includes the asset revision, fitted pixel dimensions and stable display policy;
cropped grid images and original/zoom resources are distinct. Decoded memory
has a separate bounded fast tier, released under memory pressure without
removing durable previews. Speculative neighbours do not write or promote
viewed previews. Cached display pixels preserve native color space, component
precision, orientation, alpha and HDR headroom; representations that cannot be
preserved losslessly use the native media loader rather than an SDR cache copy.
Every read and publication validates current photo access and asset revision.
On Mac, the fitted target follows the native viewer's viewport and display
profile. The stored image retains its full aspect ratio rather than the grid's
square crop. Returning through another entry or after relaunch uses the same
identity, budget, expiry and clear action. File-backed folder, recent-photo and
history previews use the same viewport policy and lossless storage; source
identity, indexed revision and the current file snapshot guard reuse. Source
access is rechecked before a cached preview is shown. A changed rendition must not replace
an already displayed image with lower color fidelity.

Both Apple hosts retain displayed decoded-table pixels through slot reuse and
cache clearing. A mapped image owns a slot lease and the mapping lifetime;
writers skip held slots instead of copying every hit on the UI thread. Clearing
invalidates the common storage epoch before deletion; work queued under an older
epoch cannot publish a table entry or detail preview afterward. Directory
accounting and clearing include managed files from older configurations while
preserving unrelated files and symbolic-link targets.

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

Mac detail titles use an existing place name when one is available; the subtitle
then shows the full capture date and time including seconds and the compact
current/total position. Without a place name, the full date and time is the
title and the position is the subtitle. Missing dates remain unknown. Coordinates
alone do not supply a place name.

Mac photo-library, folder, history and album viewers share one native flight
lifecycle. Entry retains the clicked cell's displayed image until the viewer's
attached native image view has installed pixels and supplies its fitted image
bounds. A square source crop gives way to the destination rendition even for
the same asset. Each rendition keeps its own aspect ratio and true centred region
within the full composition; flying a cropped square into a portrait or panorama
never stretches its pixels. Grid, flight and settled detail use the same native
bitmap representation and dynamic-range policy. The landing rendition remains
fixed through the flight; later quality upgrades crossfade in place after the
native handoff. Renditions use source-over blending with an opaque destination
beneath the fading source, so opaque media never becomes translucent while the
window background independently fades. Core Animation completion restores native media visibility and
removes the flight cover in the same transaction; a queued SwiftUI opacity
update or elapsed delay does not establish readiness. Return uses the current item's displayed
media and actual visible cell. Missing endpoints and Reduce Motion retain the
non-spatial fallback, without inventing a cell rectangle.

Mac's native page controller keeps stable lightweight positions in the source
grid's displayed order across successive swipes. Its directory follows the grid's
actual asset identities, not the backing fetch's sort order. Right-arrow and a
leftward media drag reveal the next displayed grid item; native trackpad paging
uses those same positions. A photo-library or album fetch adapter reverses its
newest-first backing index to match the grid, while explicit folder, History and
recent-photo collections preserve their supplied displayed order.
Only neighbouring media are prepared. Horizontal wheel and trackpad input retain
native phase and momentum ownership; a time gate cannot discard a renewed swipe.
Phase-less horizontal mouse-wheel notches change the native selected page directly.
Folders, History and recent-photo collections expose their complete ordered
positions to that native strip, including mixed photo-library, file-backed and
unavailable items. Media adapters only render a page; they do not replace a
one-item viewer when a swipe ends. Trackpad start, partial drag, reversal and
settlement keep the same native directory and adjacent live pages.
Decoded file media and its active request belong to the bounded viewer session,
keyed by source identity and revision. Recycling a native page controller keeps
its prepared pixels through settlement; it cannot briefly replace them with a
loading surface. Only the current item and adjacent items retain file access.

Each Mac workspace window owns one native floating Info utility panel and one
explicit visibility choice. It shows the active grid selection or viewer photo
without resizing or refitting the photo viewport. Paging, returning to a grid,
and switching sidebar positions update its information in place; they never
close or reopen it. Returning from detail selects the current photo before the
grid adopts the information target. A position without a selected photo shows
selection guidance in the same open window. Only an explicit Info toggle, the
native close button, or closing the owning workspace closes it. The panel uses
native window chrome and follows the system's application-deactivation behavior.
Inactive or retiring content cannot overwrite the active target. One persistent
hosting controller owns information content independently of a viewer's lifetime.

For a given photo, grid and detail use the same source-specific information
component, backup/retry policy, repeat confirmation and history action. These
actions register the existing durable intent; inspecting alone starts no backup
or playback. Missing originals use the same recorded facts and available recovery
action from either entry point. Receipt and gallery publication remain separate.
Only the selected page may request cloud media; neighbouring preparation remains
local.

Retained Mac workspace grids keep their native viewports mounted and ready while another
destination is visible. Workspace compositing owns destination visibility and hit testing;
background activity must not enqueue a separate native hide or reveal that can expose an
empty frame when the person returns. Source membership changes still follow native readiness.

### Mac grid information

The Photo Library, folder, history, recent-backup and album photo grids expose
Info in the native toolbar and through Show Info (Command-I). Selecting a photo
is sufficient; inspecting it does not open a viewer or change the selection,
scroll position or zoom. The same window-scoped native utility panel follows
the active grid selection in place. A single photo uses the shared metadata and
backup-fact layout for its source; unavailable originals retain recorded facts.
Multiple selection shows the selected count and asks for one photo for details,
without attributing one item's dates or backup facts to the entire selection.

Info remains available in a populated grid without a selected photo. The panel
then explains that selecting a photo shows its information, and follows the next
selection in place. Clearing selection retains the open panel and its explanation.
The active workspace owns the Info toolbar item and its position within the
symbol group; retained source grids supply only the current inspection target.
Calendar period covers do not stand for a selected photo. All positions share
the workspace's existing Info window and explicit open choice. Retiring a grid
or viewer only withdraws its information target, leaving selection guidance when
no successor has a selected photo. Command-I also closes the utility panel when
it owns keyboard focus. Inspection never starts media playback or backup.

### Mac file-backed grid cache

Folder, recent-photo and history grids share one file-backed rendition pipeline.
Durable disk renditions are the primary reuse tier; decoded memory is a bounded
hot tier and is not required for reuse after scrolling or relaunch. Cache identity
includes the source, relative file identity, indexed revision and discrete pixel
size. A sufficient equal or larger disk tier completes without reopening the
original. Smaller tiers may cover the cell while a sharper tier loads. Stills and
video renditions use the same identity, lossless codec, accounting and clear epoch.

Disk lookup has independent bounded concurrency from original decoding and native
thumbnail generation. Identical in-flight requests share one operation; cancelling
one subscriber preserves other subscribers, and abandoned native generation is
cancelled. Display is not delayed for persistence. Publication is separately
bounded and obeys the shared thumbnail budget and clear epoch. Cache misses retain
source authorization, path validation and native media loading; unavailable sources
may retain already indexed cached covers. Grid crops fill their cells consistently
through loading rather than switching between padded and unpadded renditions.
