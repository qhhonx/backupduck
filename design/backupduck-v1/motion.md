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
Prototype transitions are references, not proof of native execution or old-device
frame-rate performance.

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

The focused [iPhone calendar Grid contract](../iphone-calendar-grid.md) supersedes
the older phone coupling of calendar grouping/density and per-item interpolation.
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
(omega 12.5, fitted to Photos release recordings), finishing any remaining blend
within the settle, and adopts the native collection only when it ends.
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
sizing. Legacy chrome uses an interruptible 300 ms transition. Media detail stays
separate. Calendar cover videos are muted and only one is active; reduce motion,
low power, scrolling and background pause cover motion.

Phone media dismissal moves the fitted media node, not its letterboxed page.
The player stays attached through drag and return flight. A deliberate downward
drag commits above 12 pt unless reversed; a failed/cancelled gesture restores
the node. Paging updates the settled controller and centre offset atomically.
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
beneath. A cell that is not visible falls back to a fade. Reduce Motion adopts
immediately. The viewer uses the system window background; EXIF and maps remain
on demand. Years, Months and All Photos are live layers whose scale and opacity
follow the current level on one spring (stiffness 400, damping 40): a coarser
layer zooms past the viewer, a finer layer recedes, and no frame is blank.
Density changes use discrete column steps shared by the toolbar and pinch.

Mac density transitions use a bounded native tile stage on one shared lattice.
Thresholds, the density-stop rubber band, direction hysteresis, the critically
damped release, the content-boundary pivot and settle re-anchoring come from
`apps/apple/Shared/GridZoom.swift`, the same rules the iPhone grid validated;
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

Ordinary detail loading feedback waits until the current page has settled for
600 ms, then fades in place over 200 ms; completion fades it out over 200 ms.
Paging or changing asset cancels the pending reveal. Download byte progress and
failure recovery retain their existing meaning. The loading surface never
changes the image frame or contributes layout space. Filmstrip paging updates
focus and selection on retained cells; only collection membership changes reload
the strip. Offscreen request cancellation keeps an unchanged thumbnail's pixels.


Mac grouped-grid density faces crossfade photos only. One stage-owned section
caption follows the section's first-row position continuously, retaining its
native text and summary geometry. The final caption pose uses the settled
collection's header insets, width, height and sticky bounds.

A grid stage starts at the photo point that its focal fractions describe, even
when a toolbar anchor was requested in empty space. Overview entry uses the
settled density's gapless pitch. Neither entry may reposition or resize content
before tracking or settling begins.
