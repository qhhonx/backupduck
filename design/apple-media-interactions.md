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

Cloud thumbnails must not interrupt passive scrolling with a permission prompt.
Ask after an explicit attempt to open unavailable media. Use `DuckSheetLayout`
for application consent: heading, one short explanation, a neutral cancellation
action and one primary action. System Photos permission stays system-owned.
Only the active preview presents this sheet. Closing it leaves consent undecided;
declining is persisted. A permission UI must not accidentally enable backup.

Every persistent Boolean uses the shared preference row: label on the leading
edge and a switch on the trailing edge. Never rely on the platform's automatic
Toggle layout inside an unconstrained card. Mac and iPhone retain their existing
48/52 pt row minima and insets.

Backup scope has two summary rows: media types and albums. Both open a separate
editor; the parent never expands an unbounded album list. Type names and icons
match the library filter vocabulary. Photos, Live Photos, videos and bursts are
disjoint selectable categories in both browsing and backup scope. The All
filter includes every category. Album selection has search, user/system sections,
selection count, local cover thumbnails, unavailable selections and a clear
All albums option. Selection is checkmarks, not a switch per album.

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
The thumbnail strip uses uniform compact spacing while moving; the current item
expands with side space after deceleration. Reversal restores the
original state. Zoomed media pans instead of dismissing.

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
the vertical anchor principle and use the same response over 260 ms; trackpad magnification also updates while moving.
Reduce Motion replaces spatial interpolation with immediate anchored adoption.

## Acceptance

Inspect start/middle/end frames, reversal and cancellation, not just final text.
Check horizontal paging before and after zoom, portrait/landscape media, video
controls, cloud consent refusal/retry, metadata expansion, large album lists,
Mac row edges, dates at grouping boundaries and mid-library pinch anchors.
Use both legacy and current iOS native windows and a real Mac window. Tests and
reference screenshots do not prove real iCloud availability or physical gestures.
