# Apple media interaction contract

**Revision status:** the HTML reference and local build 53 failed interaction
acceptance. The following describes that implementation, not an approved
experience. See the [native revision study](native-media-preview/README.md) and
[source-backed requirements](native-media-preview/source-study.md) before
continuing implementation. Custom consent exceptions, button-only thumbnails, mixed
modal coordinators and fixed calendar easing must be reconsidered together.

This contract and [interactive reference](apple-media-interactions.html) refine
the Apple library extension. Use synthetic fixtures for public references.

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
48/52 pt row minima and insets.

Backup scope has two summary rows: media types and albums. Both open a separate
editor; the parent never expands an unbounded album list. Type names and icons
match the library filter vocabulary. Photos, Live Photos, videos and bursts are
disjoint selectable categories in both browsing and backup scope. The All
filter includes every category. Album selection has search, user albums with any previously specified system choices,
selection count, local cover thumbnails, unavailable selections and a clear
All albums switch. Enabling it clears individual choices; choosing an album disables it. Disabling it with no choices remains an empty restricted scope, never an implicit expansion to all albums. Unavailable retained IDs remain restrictive. iPhone uses three reusable cover columns and an item-count
unit. Media-cell selection follows the shared bottom-trailing badge contract.

Type and album dimensions intersect; changes apply to new discovery and the next
existing-library snapshot, not queued jobs. Manual selection remains authoritative.

## Viewer

Media is the dominant surface: black canvas, aspect-fit image, compact overlay
date/time header and icon controls. A tap hides/reveals chrome. The viewer is
read-only: do not copy Apple/Google editing, deletion or cloud-backup controls
that BackupDuck does not implement.

iPhone uses native continuous page scrolling with a narrow gap. During a drag,
the current and adjacent media remain visible and move with the finger. A short
drag returns to the same page; a committed drag settles before loading the next
neighbours. Keep at most the current page and two neighbours. Do not clear the
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
The media node remains live through the return flight. Its asset aspect ratio is
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
strip's current geometry before recentering. Still/Live Photo entry and media
return animate the live node's uniform scale and local rectangular crop on the
same timing owner. Video entry retains a poster cover while AVKit initializes
behind it; drag and return keep the player attached. Downward scaling keeps the original grabbed point under the finger;
after downward intent is established, horizontal and reversed vertical motion
remain continuous until commit or cancellation. Information restores readable
controls after magnification has hidden them.

Media pages have a synchronous native surface with asset-derived fitted bounds,
even before a poster arrives. Seed entry from the displayed source thumbnail;
an evicted cache must not disable the flight. A grid thumbnail is a centre crop:
inside the full-aspect surface it occupies its true centred region (aspect fit),
never a magnified fill, so the full-aspect image that replaces it only adds the
sides. The viewer first requests the device's small full-aspect rendition
locally (no network; it exists even for iCloud-only originals) and entry waits at
most five frames for it. Any full-aspect image replaces a crop, because a crop
alone leaves empty bands, worst for panoramas whose original is still downloading. Photo, Live Photo and video content
update inside that same surface. AVKit stays below its poster until its first
frame is ready; loading cannot replace the flying node or reset its transform.
Freeze the fitted layout during entry, downward drag and return, then resume
normal zoom/layout ownership when an interaction is cancelled or settles.

The media's lower trailing corner owns one compact ring for loading. Render
determinate progress only when the media provider reports it; otherwise use an
indeterminate arc (static with Reduce Motion). Keep date/time stable and omit
parallel header loading text, spinners and linear progress. A small local cloud
or retry symbol replaces the ring when action is required. This does not remove
automatic PhotoKit cloud loading and system access restrictions.

Information tracking moves the photo and the panel together. Choose the open
height from the fitted photo and a bounded top viewport, then project drag
velocity to settle or cancel. Fade chrome continuously with panel travel.
Selected-item detail disables information from both upward gestures and
accessibility actions. Its Done action uses the same prominent circular check
treatment as selected review. Filmstrip emphasis comes from geometry alone;
do not draw a white selection border.

Mac uses a large dark media stage, keyboard/trackpad navigation, unobtrusive edge
arrows and an information sidebar. It shares media loading and metadata, while
retaining desktop window and keyboard conventions. Paging animations move the
media; controls stay fixed. Show real loading/recovery in a bounded overlay.

## Grid density and calendar

Calendar grouping and density are related but distinct. All photos is a stable
ungrouped view; Days and Months group every actual asset without inventing
curated summaries. At phone width, Days starts at three columns and Months at
seven; pinching can move through three/five/seven/nine columns. Do not make
Months merely a renamed five-column day grid.

Anchor a density change to the asset under the pinch midpoint, including its
relative location within the tile. Interpolate tile geometry and content offset
together on every gesture frame. Keep the anchor at its relative horizontal and vertical position while the
fingers move. A transient horizontal translation preserves that focus; release
restores the column edges while preserving the vertical scroll context. Content
boundaries limit the vertical anchor. Keep assets by stable ID, suppress tiny media
badges, and refresh high-quality targets after settling. Date headings fade
between grouping modes; they must not abruptly shift the entire viewport.

Gesture progress is linear in the finger's scale. On release, settle to the
nearest density over 320 ms with a normalized critically damped response
(1 - (1 + 7t) exp(-7t)). Cancellation settles over 300 ms; menu changes use
420 ms. These are BackupDuck's reproducible parameters, not a claim to know
proprietary Apple/Google curves from recordings. Mac layout changes retain
the anchor principle and use the same shared release spring; trackpad magnification also updates while moving.
Reduce Motion replaces spatial interpolation with immediate anchored adoption.

## Acceptance

Inspect start/middle/end frames, reversal and cancellation, not just final text.
Check horizontal paging before and after zoom, portrait/landscape media, video
controls, cloud availability/retry, metadata expansion, large album lists,
Mac row edges, dates at grouping boundaries and mid-library pinch anchors.
Use both legacy and current iOS native windows and a real Mac window. Tests and
reference screenshots do not prove real iCloud availability or physical gestures.

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
The map has a Capture Location heading and a pin with no duplicate visible title.
