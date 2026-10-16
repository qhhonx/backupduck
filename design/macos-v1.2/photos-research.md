# macOS Photos reference observations

These notes record what the system Photos app does on macOS, observed by
operating it directly. They exist because the Mac library contract was first
written without any observation of the system app. They are visual and
interaction references only: Photos exposes no source, curves or state machine,
and nothing here claims to reproduce its private parameters.

Observed on macOS 27, a 1152 × 720 pt window in light appearance, with a large
library (tens of thousands of items) synchronised through iCloud. Frames
were sampled with window screenshots at about 10 frames per second, so durations
are coarse (± 100 ms) and spring shape is not recoverable. A trackpad pinch could
not be driven from the harness; pinch behaviour below is inferred from the iPhone
contract and must be checked by hand.

## Window and toolbar

- The sidebar stays visible in every level and in the viewer. The detail column
  is a plain window-background canvas; photos sit on it with hairline gaps.
- The title area shows "Library" with a subtitle that is the visible capture
  range (for example one date, or a start and end date). At the newest edge of
  All Photos a footer centred under the last row reports the actual totals
  ("N photos, M videos") and the iCloud sync state.
- Toolbar, left to right: sidebar toggle; grid style pop-up; zoom out / zoom in
  segment; a three-segment control **Years | Months | All Photos** (there is no
  Days level in this release); then aspect-ratio toggle, filter, action menu,
  information, share and search. Zoom and aspect controls appear only in All
  Photos; Years and Months show the segmented control, information and search.
- The View menu repeats Years / Months / All Photos, Zoom In / Zoom Out and
  "Original aspect grid".

## Levels

- **Years**: one large cover per year, three per row at this width, about 4:5
  portrait, corner radius about 8 pt, 10–12 pt gaps. The year label ("2024")
  sits top-left in bold white with a soft shadow. The list rests at the newest
  edge (the current year is at the bottom).
- **Months**: month heading ("October 2022") above a mosaic of day covers. A
  five-cover module is one hero two columns wide and two rows tall plus a 2 × 2
  block of smaller covers; each cover carries its day number top-left. Corner
  radius about 8 pt, gaps about 8 pt, a faint shadow.
- **All Photos**: a gap-hairline (about 1–2 pt) chronological grid of square
  cells at three columns by default in this window; zoom steps reach roughly
  five and nine columns within three menu steps. Cells carry duration (bottom
  right), favourite heart (bottom left) and shared-library mark (top right).
- A level change keeps the item under the pointer or the visible centre. Opening
  a year from Years zooms that card into its Months view (the cover grows from
  the clicked card while the rest crossfades). The visible asset is retained
  across levels.

## Level transition

Years ⇄ All and Years ⇄ Months complete in about 0.3–0.4 s: the outgoing level
recedes or scales while soft, partly faded tiles remain for two or three frames,
then the destination is settled by the fifth sampled frame. No blank canvas is
shown at any frame. This agrees with the iPhone contract's roughly 0.3 s
critically damped switch.

## Viewer

- Double-click (or Space/Return on a selection) opens the item in the same
  window. The photo grows from its tile to its aspect-fit rectangle while the
  rest fades to the window background; the open completes in about 0.2 s.
- The viewer keeps the sidebar and toolbar and uses the **system window
  background** (white in light appearance), not a black stage. Media is centred
  and aspect-fit; Live Photo and text-recognition badges sit on the media.
- Toolbar: circular back button, a small zoom slider, a centred title (caption,
  or the capture date) with a subtitle of full date, time and position within the
  library ("n / total"), then information, share, favourite, rotate, enhance and
  an Edit button.
- No always-visible filmstrip was seen in the default state.
- Left and Right arrows move through the library, Escape or the back button
  returns to the grid at the currently viewed item.

## Gaps against the BackupDuck Mac library

Addressed in the current Mac library (checked with sampled frames, about 10 fps):

1. Levels are live layers on one spring instead of an opacity swap.
2. The viewer uses the system background, grows from its cell, returns to it, and
   has no permanent filmstrip.
3. Zoom uses discrete column steps shared by the toolbar and pinch.

4. Years are portrait cards with the year at top left; a month is a heading
   above a hero plus up to four smaller covers, each with its day number.
5. The newest edge of All Photos shows the actual photo and video totals. No sync
   state is shown: the library reports none and none is invented.

6. All Photos, Years and Months run oldest to newest and rest at the newest
   edge; Left in the viewer is older, as in Photos.

Still open:

7. The two overview stops (month-like and year-like gapless mosaics) are not
   implemented: the Mac library stops at 15 columns with gaps and badges.
8. The newest-edge footer shows totals only; the system sync state is not
   available to the app.
9. Thumbnails still take a moment to sharpen after a large density step.

## Zoom stops and transition timing (60 fps capture)

Recorded at 60 fps by cropping the Photos window from a screen capture; only the
window region was kept and the recording is not stored. Findings:

- All Photos has **six** zoom stops: four grid densities (about 3, 5, 6 and 9
  columns at a 1152 pt window), then two gapless overview mosaics, month-like
  and year-like, with no per-photo decoration. Zoom In is disabled at the
  largest stop and Zoom Out at the densest.
- The newest edge shows the actual totals and the system sync state ("Just
  synced with iCloud") under the last row, at every stop including the mosaics.
- A stop change takes about 0.2 s: the lattice scales while the two densities
  cross-fade in the first third; no tile is ever blank and nothing moves after
  the motion ends.
- The viewer opens in about 0.2 s (see above).

Measured on the BackupDuck Mac library with the same method (Release build): a
stop change is 11–26 changing frames at 60 fps with a monotone decay and no
rise after the peak, level changes 12 frames, and no frame brighter than the
content (blank-tile flashes seen in the first revision are gone).

## Lessons that were missed in the first revision

- Core Animation cross-fades `contents` by default. Every reused or refreshed
  cell ghosted over the previous photo until the photo layer's actions were
  disabled. Any tile layer must disable implicit `contents`, `position` and
  `bounds` actions.
- A Debug build is not a basis for judging motion: Swift without optimisation
  is several times slower. Judge feel and measure frames on Release only.
- A free-running timer beats against the display refresh; drive settles from the
  display link.
- Tile edges must snap to device pixels from the lattice so gaps keep one width
  while the pitch animates.
- Do not remove the transition stage until the native cells have committed.
- Cross-tier thumbnail fallbacks must exist on macOS as on iPhone; without them
  every density change shows blank tiles until the new tier loads.
- A level layer must be mounted and loaded before its first switch, or the first
  switch shows a blank page.
- Transition tiles must be layers. Resizing a cell view every frame made AppKit
  re-rasterize its SF Symbol and text badges each frame; a Time Profiler trace of
  one zoom step showed the main thread saturated for about 750 ms and the 60 fps
  recording advanced only every other frame. Layer-only tiles scaled through
  `sublayerTransform` removed it.
- All Photos geometry needs only the item count. Reading every creation date in
  the layout's `prepare()` faulted every `PHAsset` on each reload (about 260 ms).
- Animate level opacity in Core Animation. An AppKit `animator()` with implicit
  animation re-ran view layout on every frame of the switch.
- Keep toolbar items in place and disable them; inserting and removing items
  relaid the toolbar during each level change.
- A zoom settle that outlives the whole-library load re-derives its offset:
  an offset chosen for the first few hundred rows put the overview at the
  oldest photos.
  The newest-edge state the zoom started from decides where it lands.
- Every level change has one focus photo: the selection, else the photo the
  last change landed on while it is still visible, else the one nearest the
  centre. The flight is clipped to the content area under the toolbar, aims at
  the live destination each frame, and identifies covers by the asset whose
  pixels they show, never by date: a late thumbnail callback or a rotating
  year card otherwise pairs one photo's pixels with another photo's identity.

## Scroll smoothness

Measured with the `-scroll-benchmark` launch argument (Release build): after each
density change the grid scrolls itself at 1500 pt/s for four seconds and logs
frame intervals and the hitch ratio (time beyond one refresh per second of
scrolling) to `/tmp/scroll-benchmark.log`. Main-thread costs were found with
Time Profiler and, for "which view redraws" and "who publishes", with debugger
breakpoints on `-[NSViewBackingLayer display]` and
`ObservableObjectPublisher.send()`. Hitch ratio in ms/s, first pass after launch
on a large library:

| Stop | Before | After |
| --- | --- | --- |
| 4 columns | 30 | 8–17 |
| 6 columns | 71 | 0 |
| 9 columns | 241 | 0–10 |
| Month overview | 17 | 0 |
| Year overview | 54 | 0 |

What mattered, roughly in order:

- Any published change re-evaluates every view observing that object; on the
  Mac that is the whole window, and the toolbar relays out and resolves every
  symbol again (30–45 ms). Periodic model refreshes must publish only changes;
  the visible date range lives in its own object and reaches the window
  subtitle through AppKit; and All Photos reads the remaining rows once after
  the newest page instead of publishing a page every few hundred photos.
- Overview tiles store pixels in the display's colour space. Core Animation
  colour-matched each sRGB tile on every commit.
- Overview tiles never fault a `PHAsset` while scrolling: the background prefill
  records each table key and capture date by fetch index.
- Table images use a direct data provider. A copying provider checked each
  entry's pages for readability as each image was created.
- Grid badges and text are layers from cached bitmaps, so a cell is one view.
  Image views and labels re-rasterized symbols and re-typeset text for each
  cell that scrolled in, and each subview added layer-tree and tracking-area
  work; tooltips exist only for visible badges.

## Not verified

Pinch and scroll-wheel zoom feel, rubber-band limits, the interruption of a
transition, the exact column counts for each zoom step, dark appearance, large
text, and behaviour with a cold iCloud cache. Re-observe these by hand before
treating them as settled.
