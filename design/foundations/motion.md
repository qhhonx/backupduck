# Motion and stable feedback

Motion explains cause and hierarchy. Avoid decorative loops, bouncing, breathing
brand accents and continuously spinning mascots. Receiver/media performance takes
priority on older devices. Use native transitions for standard system controls.

| Custom interaction | Duration | Treatment |
| --- | --- | --- |
| Press/highlight | 80–120 ms | Background or opacity, ease-out |
| Switch | 160 ms | Thumb displacement, cubic-bezier(0.2, 0.8, 0.2, 1) |
| Status replacement | 120 ms | Fade without changing container geometry |
| Scrim entry | 140 ms | Opacity |
| Detail/pairing entry | 220 ms | Fade and up to 12 units displacement |
| Overlay exit | 160 ms | Fade and up to 8 units displacement |
| Confirmed progress | 320 ms | Interpolate actual progress |
| Filter/sort | Immediate | Update data without moving the entire list |

Progress is a thin overlay on a stable status region. Apple cards reserve an
inset final 3 pt region aligned with their text column from construction;
value updates and the end of counting never add a layout row.
Show byte progress only during actual transfer with meaningful partial progress;
waiting, completed and unrelated preparation states do not leave an empty track.
A known folder scope uses confirmed file deliveries instead. Keep that bar
visible during the gaps between individual files.
Large text adapts the layout without clipping. Failures and important consequences
remain visible even when they require more space.

Update rows by stable identity. Image loading replaces a fixed thumbnail slot.
Preserve scrolling, selection, filters, pagination and expanded folders. Replace
status content instead of inserting transient warnings above the working list.
A retry request must not trigger a completion animation.

Respect Reduce Motion/Remove Animations and `prefers-reduced-motion`: remove
spatial motion and progress interpolation while retaining immediate feedback.
For the first-photo reward, reduced motion adopts both the landed illustration
and the completion heading/actions together once publication is observed; it
does not wait for an animation-completion callback.
Reduced transparency and contrast settings are separate and do not hide content.
Return focus to the trigger after closing an overlay; do not repeatedly interrupt
screen readers for every progress update.

Inspect transfer, pause, failure, completion and offline transitions in actual
native windows. Check long lists, narrow screens, large text and reduced motion.
Synthetic transitions do not prove physical-device frame-rate performance.

Library density changes update stable native collection attributes and the scroll
anchor together on every gesture frame. Gesture progress follows image scale;
release uses a normalized critically damped response over 320 ms, cancellation
over 300 ms, and menu changes over 420 ms. Mac changes use the same response
over 260 ms. Phone pinch retains its initial focal point during the gesture, then
settles the column edges while preserving vertical context. Date headings crossfade
when grouping changes. Never restore the anchor only after the animation ends.
Phone detail paging uses native scroll deceleration and neighbouring live views,
not an onEnded replacement. Information opens within the same media viewport.
See [Apple media interactions](../apple-media-interactions.md) for reversal,
zoom ownership, scope navigation and accessibility acceptance.

The [iPhone calendar Grid contract](../iphone-calendar-grid.md) defines independent
calendar grouping and density with a shared tile lattice.
Period controls move matching visible covers and zoom-crossfade the rest over
about 340 ms: toward All the outgoing level expands and the incoming grid settles
from slightly smaller; toward Years the outgoing level recedes. All-grid pinch
uses a live virtualized tile stage on a shared lattice: every density is drawn
at the same on-screen cell pitch around one photo. Dividers take the shown
density's scaled gap in one frame and snap to device pixels; only cell contents
crossfade while fingers rest (about 1.2 s for ordinary grids and 0.85 s for dense
overviews). A new pair needs deliberate travel; small reversals
retarget its current mixture without resetting it. Date text follows geometric
density independently of photo blending. A short dead zone precedes tracking;
the newest boundary constrains shrinking content during the gesture. Release
preserves the preview target and settles on a critically damped spring
(omega 12.5), finishing any remaining blend
within the settle, and adopts the native collection only when it ends.
Fingers drive the stage per gesture event; nothing runs a frame loop. The
crossfade is handed to Core Animation as keyframes of its own curve at each
event (a density change, a reversal, a release, or the first tile pixels
after a held fade), and the settle is one `CASpringAnimation` per density
layer (same stiffness, damping and release velocity) over a layout made once
at the target pose. A library that fits on one screen at three columns zooms
about its top-left corner at every density, with no leading empty slot, so no
density appears around the fingers and then travels to the top. During a
pinch the content top follows the header actually shown: dense overviews
have no interval line to make room for. The header's legibility backdrop and
light title appear only while photos actually lie behind the header, and
fade in or out over 250 ms.

Mac grid zoom uses the shared photo-mixture curve and critically damped
pitch/focus spring. Ordinary photo pairs retain their phase when reversed;
rapidly reaching a third density retains the existing composite. Core Animation
continues the photo blend while magnification rests, with a bounded wait for
incoming pixels. Gesture events update geometry without restarting that blend.
Gapless overview tiles share unsoftened edges during fractional scaling; their
individual edges never antialias into the background and reveal a grid of seams.
Their pitch spans the available viewport width; shared edges snap to device
pixels without accumulating a rounding remainder beside the last column.
While zooming, each overview face covers the viewport with chronological photo
copies beside its native columns, including the complete release trajectory.
These copies keep their asset identity and in-photo focus when input takes over;
they do not add rows beyond the first or last photo. Settled browsing keeps the
native column bounds.
Scrolling takes ownership before the viewport moves: a running density change
commits its chosen density and anchor, transfers retained pixels, and reveals
native browsing in the same input event. Native bounds changes, including delayed
wheel movement, update photo coverage and newest-edge intent before display.
Old release or adoption callbacks cannot
restore the previous viewport after that handoff.
Release shortens its remainder and uses the same subpixel completion thresholds
as the phone grid. Both geometry and opacity finish before native adoption.
Release layout, backing content and animation tracks are prepared together.
Core Animation starts the complete batch on its transaction timeline.
Every track holds its captured source value before that start, so a prepared
target pose cannot leak into an earlier frame. Its native
start event synchronizes the analytic input model, photo blend and totals track;
construction and submission work do not consume visible spring time. Input that
arrives before this event retains the unstarted pose, and an obsolete release's
start or completion event cannot affect its replacement. Deferred native adoption
and cleanup belong to that release too; reusing the same stage for new input
invalidates the old handoff before it can remove or update the replacement.
Repeated toolbar input retargets the existing stage from its current pose and
pitch velocity. A new magnification resolves the photo through the shown
section geometry and preserves every visible density face and caption in place
while moving the input focus. Chronological copies exposed beside a scaled
ordinary face retain the displayed copy's asset identity and in-photo fraction
when input takes over.
Toolbar zoom retains the chosen top or newest edge even when an intermediate
density fits the viewport; zero scroll offset alone does not change that intent.
The first or last photo edge supplies the matching toolbar anchor, keeping the
reading surfaces attached to their respective content edges across density faces.
For a newly introduced density, a toolbar zoom retaining the newest edge places
the last photo in the last column. Returning to an already shown face preserves
that face's row phase; an interrupted release cannot derive a new phase from an
intermediate horizontal spring position.
The native totals label remains mounted on the stage during zoom, with its
reading size and facts unchanged. Its own geometric position track follows the
content extent and rejoins the settled collection without disappearing.
Every photo face is clipped above the totals' reading margin on the same event
or native release timeline. Overview period captions stay outside this photo-only
boundary. A short library changing row count or a fitting overview changing
density cannot leave an outgoing photo tail in that reading region.
Media marks follow the visible photo edge without cutting their glyphs. A mark
fades as the remaining photo becomes too short to contain its full reading size.
Ordinary-face marks occupy an independent, native-size reading plane, outside
the photos' clipping container. Their safe region ends one x-small spacing token
above the totals and stays within the viewport. Hidden poses retain safe
coordinates, so an interpolated fade cannot pass a glyph through a clipping
edge. Position, plate geometry and glyph alignment share the totals' release
timeline; restoring native ownership preserves their final reading geometry.
Ordinary media marks and overview period captions hand off reading ownership
without painting different text over the same area. The outgoing reading family
fades away before the incoming one becomes legible; month and year overviews
follow the same rule. This handoff uses the photo mixture's existing timeline,
preserves its phase on reversal, and leaves ordinary-to-ordinary zoom unchanged.

Tile geometry springs keep ordinary gaps at 2 pt and source-cell marks at native
size. Photo-library duration text and media marks remain outside the image's
scale transform, retaining their reading size while following the photo edge.
Newly attached marks adopt bitmap scale and backing color immediately; native
handoff must not introduce an implicit glyph-size or background fade.
Dense pooled photos share a photo-only layer transform, with native-size
period-label tracks outside that transform and a fixed viewport reading margin;
fractional edges that cannot share
one transform retain tile springs. Ordinary Photo Library, folder and History
grids keep date positioning in the native window subtitle. The Folders parent
and individual folder scopes use this same flat-grid behavior, retaining each
scope's photo anchor on navigation and Back. They never introduce
inline date captions, floating date capsules or nested folder headers during
tracking, reversal or adoption. Folder notices and History cause headings are
ordinary flow content, not sticky reading overlays. Any flow text retained by a
density stage keeps its measured native size and follows document geometry
independently of the photo blend. The stage resolves its background in the
inherited appearance. Gapless overview period captions retain their separate
native-size reading tracks; the subtitle does not duplicate their periods.
Ungrouped content that fits at the largest ordinary density stays at its first
slot and zooms about its top-left corner, with no leading empty slots.

The stage starts with already displayed native pixels, including source-backed
cells. Native adoption retains those pixels before removing the stage. A visible
stage animation owns completion independently of virtualized off-screen tiles.
The exact target remains over the native update until the current viewport's
expected cells and captions match their actual identities and layout frames.
Already displayed stage pixels transfer to those replacement cells before the
cover is removed in the same transaction. Native layout and cell-ready events
resume a pending adoption; a main-queue turn alone does not establish readiness.
Unavailable thumbnails do not block adoption when the stage had no image for
them. Dense mosaics retain displayed pixels while their own renditions arrive.
A renewed gesture can take over the retained stage during pending adoption.

Cancellation restores the initial density; Reduce Motion adopts state without
spatial animation. Native bottom-bar minimization remains system-owned. The period capsule is
48 pt tall and centred between the compact native icon and its mirror
position, 12 pt from each. Outgoing native labels must
be invisible before period labels appear; expansion applies the same rule in
reverse. The bar's morph event (KVO, see `design/iphone-calendar-grid.md`)
starts the entrance 130 ms later, once the platter has formed its circle: the
capsule rises 14 pt into place while its glass materializes (0.3 s spring, no
bounce; Reduce Motion: 0.2 s, no rise). Expansion dematerializes it within
80 ms, before the expanding platter can pass beneath it. Nothing samples
presentation frames. Navigation actions retain native
sizing. Chrome before iOS 26 uses an interruptible 300 ms transition. Media detail stays
separate. Calendar cover videos are muted and only one is active; reduce motion,
low power, scrolling and background pause cover motion.

The library viewer uses a UIKit custom transition. Native grid and History
sources push the viewer on their own navigation controller, retaining the same
system navigation bar and toolbar throughout entry, return and cancellation.
Bar items use semantic identifiers: the same action may morph across states,
while unrelated source and viewer actions remain separate system transitions.
A source without an app-owned native stack presents the shared viewer container.
Sheet sources keep their native sheet frame and clipping. The viewer's vertical
pan decides before the horizontal pager and page zoom scroll; zoom returns
input to the native page scroll. System sheet recognizers remain system-owned.

The shared `MediaViewerTransition` keeps the page fixed. The source grid remains
below the viewer content, and the backdrop and filmstrip follow the photo's
property animator. The flight sits above the media stage but below the filmstrip
and system bars. Only the photo flies: a
snapshot of the fitted media moves between its tile and its fitted frame, with
one uniform transform and crop on the same property animator, and the live
media takes over at identical pixels. Bars, filmstrip and background therefore
change during the flight, and nothing appears after the photo lands. A
downward drag drives the same dismissal transition interactively: the photo
follows the finger and shrinks, the grid shows through in proportion to the
distance (240 pt for full), and release carries the finger's velocity into one
spring, to the tile or back. The player stays attached to its page. A
deliberate downward drag commits above 12 pt unless reversed; a cancelled
gesture restores the open viewer. Paging updates the settled controller and centre offset atomically.
Filmstrip geometry compacts for dragging and expands the settled item over
250 ms, with immediate adoption under Reduce Motion.

For detail paging, distinguish a user's direct filmstrip drag from the strip
following page progress: the latter continuously transfers emphasis between two
neighbouring thumbnails instead of snapping to a compact row on touch-down.
Live media entry/return uses one uniform transform and a UIView crop mask driven
by the same animator; an unrelated mask easing must not finish ahead of the
photo. Chrome overlays a stable full-screen fitted viewport. Preserve the grabbed
point while a downward drag scales the photo and allow subsequent two-axis
movement. Native scroll deceleration remains the page-settling owner. These
detail parameters are implementation approximations, not measured private APIs.

Media loading must not replace a flying node. Use a synchronously laid out native
page and retain the displayed poster until AVKit reports its first frame ready.
Offscreen preparation leaves the source tile visible until the opening snapshot
is installed. Shared presentation has its own opening state: media-local loading
is hidden throughout that transition, while native chrome keeps its normal fade.
Freeze the live page's displayed rendition during the flight and refresh it only
at the handoff. Reopening uses the shared Photos revision-aware, bounded cache
of prepared full-aspect display pixels across library, recent-photo and history entry points
before requesting another rendition. Source owners keep independent requests
and browsing state; leaving one source does not clear shared display pixels. The
display cache fits the current window and screen, retains asset revision and
color range, and uses an explicit bounded replacement order. Larger zoom
renditions remain session-owned. Local neighbour preparation cannot displace
recently viewed display pixels. Explicit cache removal, revoked access and memory
pressure invalidate shared display pixels and obsolete publishers; edited assets
use their current revision.
Suspend zoom/layout resets during a flight. One media-local ring owns loading
feedback; header dates do not turn into loading messages. Information travel
updates native photo geometry and panel geometry in the same animation owner,
with continuous chrome fading. Selected-item detail rejects information gestures
and actions, while retaining downward return and horizontal paging.

Phone calendar pinch tracks two-finger distance linearly after the dead zone;
terminal one-touch coordinates cannot replace the focal photo. Calendar period
visibility follows the native bar's presentation geometry and label visibility
in both directions; neither timers nor library scroll position own its lifecycle.

For comparable gestures, study original-speed recordings and densely sample the
transition. Use coarse full-video frames to find phase boundaries, then sample
at the video's actual cadence around entry, drag, reversal and settlement. Track
one stable photo or control and measure x/y, width/height and opacity separately.
Fit a bounded easing/spring approximation to the measured samples; distinguish
measured screen behavior from undocumented framework parameters. Held pinch
scale is input-driven, so do not fit it as a time-only easing curve. Inspect
focal identity and media pixels at intermediate frames, not only end labels.
Keep private recordings, frame sheets and measurement data in ignored evidence.

Use `scripts/sample-motion.swift` for local recording studies. It caps sampling
at the source track's fastest cadence, records requested and actual timestamps,
and skips duplicate actual timestamps. For example:

```sh
xcrun swift scripts/sample-motion.swift sample.mp4 build/motion-study 0 3 60
```

Generated JPEGs and `frames.csv` support phase-by-phase comparison without adding
personal recordings to source control. For variable-frame-rate recordings, a low average nominal rate must not discard
short intervals of dense animation frames. Sampling more often than available
source frames cannot recover missing motion data. Keep parameter estimates separate from
pixel measurements and state uncertain or clipped portions of a fitted curve.

Period exit starts on the native compact button's touch-down. Inspect the
presentation-layer overlap interval at source-frame cadence, not just the
settled full bar. Finish the period fade before full native controls become
visible in its region; their model opacity alone is insufficient.

Scaled-down faces extend their visible rows with chronological neighbors rather
than exposing empty horizontal canvas. Destination row phases align around the
focal photo, survive reversal, and are retained by the adopted collection.
Ordinary-grid media and selection/status badges share the native cell component
throughout the transition; a handoff must not introduce a second decoration pass.

Cell decorations scale with the complete photo node in native cell coordinates.
Gapless/ordinary transitions use one shared animated cell clip and gap across
all faces. Native adoption transfers retained displayed pixels and geometry to
visible cells before removing a one-commit stage cover; cache eviction and late
small previews cannot create a placeholder regression. Compact tab expansion
only changes navigation/period visibility. Already expanded Library reselection
owns return-to-newest scrolling. Additional library edge shadows are disabled.

Dense handoff waits for published replacement bitmaps, rather than a single
run-loop turn. A renewed gesture reads the pixels actually on screen even when
thumbnail caches have evicted their source images. Gapless mosaics scale as a
group; their period captions remain unscaled. Ordinary-grid gap and decoration
behavior is unchanged. Exercise slow bitmap publication, immediate request
callbacks, strip recycling and repeated dense gestures with cache eviction.

Mac library calendar covers and All Photos use independent navigation. Trackpad
magnification updates All Photos size without crossing into date grouping. The
in-window viewer grows from its grid cell and returns to the current asset's
cell on a critically damped spring (about 0.2 s), preserving the native grid
beneath. Selecting a photo or laying out its viewer does not change the source's
scroll intent. Only actual browsing movement adopts an edge; an empty or loading
source does not acquire a newest-edge pin from an unrelated input event. The
viewer retains its source's native clip origin before entry; layout and visibility
requests cannot scroll it while the viewer is open. Return releases that ownership
before resolving the current photo's landing, without replaying deferred scrolls.
Removing or replacing the viewer also releases the source. Native viewport sizing
continues throughout, and normal scrolling resumes after return.
A cell that is not visible falls back to a fade. Reduce Motion adopts
immediately. The viewer uses the system window background; EXIF and maps remain
on demand. Years, Months and All Photos are live layers whose scale and opacity
follow the current level on one spring (stiffness 400, damping 40): a coarser
layer zooms past the viewer, a finer layer recedes, and no frame is blank.
Density changes use discrete column steps shared by the toolbar and pinch.

Mac density transitions use a bounded native tile stage on one shared lattice.
Thresholds, the density-stop rubber band, direction hysteresis, the critically
damped release, the content-boundary pivot and settle re-anchoring come from
`apps/apple/Shared/GridZoom.swift`, the same rules as the iPhone grid;
hosts must not re-derive them. Density faces crossfade at equal pitch and a new
magnification takes over a running settle in place; wrapped collection rows never
interpolate through each other. Complete cell decorations scale in their own
reference coordinates. Settlement aligns the stage's gap, pitch and focal point
with the destination collection before transferring retained pixels and removing
the stage. Native collections remain the settled browsing and selection owner.

On iPhone, a detail bitmap is prepared for display before publication. Keep the
best available full-aspect rendition while a larger request, decode, retry or
cancel completes; late cropped covers and smaller renditions cannot replace it.
The adjacent two items in each direction are prepared locally, with bounded
model retention and unchanged network ownership for the visible page.

Local rendition preparation, including Live Photo assembly, retains the photo
without a loading ring. Live Photos first resolve local resources; only a
confirmed need for cloud resources starts the allowed network request. Real
download progress, cloud actions and failures use the media-local indicator;
the opening flight suppresses it until the live page takes over. Appearance and
completion fade in place over 200 ms. Download byte progress and failure recovery
retain their existing meaning. The loading surface never
changes the image frame or contributes layout space. Filmstrip paging updates
focus and selection on retained cells; only collection membership changes reload
the strip. Offscreen request cancellation keeps an unchanged thumbnail's pixels.


Mac ordinary density faces crossfade photos only. Source notices and cause
headings retain their ordinary flow geometry and native reading size. Their
final poses use the settled collection's measured insets, width and height;
there is no folder/date pinning or date-style change at handoff.

A grid stage starts at the photo point that its focal fractions describe, even
when a toolbar anchor was requested in empty space. Overview entry uses the
settled density's gapless pitch. Neither entry may reposition or resize content
before tracking or settling begins.
