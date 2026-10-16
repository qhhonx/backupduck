# iPhone behaviour reused by the Mac library

The iPhone calendar grid ([contract](../iphone-calendar-grid.md)) was validated
against real gestures and recordings. The Mac library must reuse that work, not
rediscover it. This list is the checklist: each row is a behaviour the iPhone
already settled, where it lives, and where the Mac stands. Update it in the same
change that moves a row.

Status: **shared** = one implementation in `apps/apple/Shared`; **mac** = a Mac
host implementation of the same rule; **open** = not done.

## Density and levels

| Behaviour | Where | Mac |
| --- | --- | --- |
| Years / Months / All are levels, not column counts | contract | mac |
| Density stops, log-size interpolation, rubber band | `GridZoom.Stops` | shared |
| Dead zone before a pinch tracks | `GridZoom.Pinch` | shared (zero on Mac: magnification is already relative) |
| Direction hysteresis, reversal after ~1.5% travel | `GridZoom.Direction` | shared |
| Release commits the previewed stop; short pinch steps once | `GridZoom.releaseIndex` | shared |
| Critically damped release (ω 12.5), velocity bounded | `GridZoom.Settle` | shared |
| Newest-edge and top boundary pivot while shrinking | `GridZoom.Boundary` | shared |
| New pinch takes over a running settle in place | `GridZoom.reanchored` | shared |
| Final offset clamped to adopted geometry | `GridZoom.offset` | shared |
| Six stops: four grids, month and year overview mosaics | `CalendarGridController` | mac (`MacLibraryDensity`: 3, 4, 6, 9, then width-derived month and year overviews) |
| Overview mosaics are gapless, no badges, small tiers | `CalendarDenseCanvas` | mac (`MacDenseCanvas`: pooled layers, no cells) |
| Overview period pills (bright month / quiet year) | `CalendarGlassHeading` | mac (`MacDenseCanvas.renderPills`: month pills in the month overview, year pills in the year overview, at the row where a period begins, the current one pinned under the toolbar and pushed by the next, never overlapping; also drawn on zoom-stage faces) |
| Month heading floats on a material pill while its module scrolls under it | `CalendarGlassHeading` | mac (`MacCalendarCover.pin`) |
| Overview loads the whole library with one bulk read | `PhotoLibraryModel` | shared (`loadAllRows`) |
| Tap on an overview tile drills down one stop | `density(columns:at:)` | mac (`drillDown`) |
| Years/Months: one pinch past a threshold changes level once | `triggerCoverPinch` | **open** (toolbar only) |
| Cover pinch anchors on the card under the fingers | contract | **open** |
| Level change moves and fades layers on one curve | contract | mac (scale 1.12 / 0.92 about the centre; matched-photo flights **open**) |
| Every level change keeps one focus photo (selection, else nearest the centre) and flies it | contract | mac (display-link flight clipped to the content area under the toolbar, re-aiming at the live destination each frame; cross-fades when the destination period shows another photo. the source is captured at the click, before All Photos loads or a year card rotates. All six directions checked in slow motion: five fly the same photo; All→Years cross-fades because the centred photo is not one of the year's month photos) |

## Stage and motion

| Behaviour | Where | Mac |
| --- | --- | --- |
| Faces share one lattice pitch, aligned on the focal photo | `CalendarZoomStage` | mac (`MacGridZoomStage`) |
| Edges snap to device pixels, gaps keep one width | `CalendarZoomStage.layout` | mac |
| Incoming face waits for pixels (bounded) | `CalendarZoomStage.advanceBlend` | mac |
| Tiles never cross-fade `contents` implicitly | `tileActions` | mac |
| Stage stays until native cells have committed | `adoptionCover` | mac |
| Settles driven by the display, not a timer | `CADisplayLink` | mac |
| Reduce Motion adopts immediately | contract | mac |
| Decorations scale with the cell | `CalendarTileDecorations` | mac (reference-size trick) |
| Leading row phase kept so no column slides on release | `faceLeadingSlots` | mac (`leading` slots per face; button zoom 4→6→4 columns re-recorded at 60 fps on Release: one decaying burst of about 35 frames per step, no rise after the peak, no column slide in sampled frames) |

## Position and chrome

| Behaviour | Where | Mac |
| --- | --- | --- |
| Newest edge is the resting position, bottom aligned | contract | mac |
| Newest-edge footer with totals | contract | mac (no sync state) |
| Older pages appear above without moving the viewport | `LibraryTimeline` | mac |
| Visible capture range as subtitle | contract | mac |
| Selection: range gestures, review, shared set | contract | mac (AppKit owned) |
| Selection is an outline, not a check mark or dimming | Photos | mac (accent outline on the photo layer) |
| Left and Right continue across rows; Shift extends from the anchor | Photos | mac (`LibraryCollectionView.arrowStep`) |
| Cover single click selects (outline), double click / Return opens | contract | mac |
| Month module composition follows sampled cover count, mirrored on alternate months | contract | mac |
| Month day cover opens All centred on that photo | contract | mac |
| Cover video / rotating year covers | contract | mac (idle, muted, one player, local media only, stops on scroll; playback itself unverified because this library's video covers are iCloud-only) |
| Original aspect toggles with a morph; outline hugs the photo rectangle | Photos | mac (`PhotoCell` frame animation) |
| Selection has no Clear or Show buttons; Esc, empty click and marquee are native | Photos | mac (a marquee also starts in the visible gaps of original aspect) |
| Filter is one flat menu (All, divider, each media type, checkmark), icon only; aspect toggle uses Photos' rectangle-with-arrows glyph | Photos | mac |
| Backing up a selection without a receiver opens pairing and keeps the selection | contract | mac |
| Viewer uses the window toolbar (back; centred date with time and n / total; Info; Live stays on the photo's badge) and grows from / returns to its cell | Photos | mac (immersive fades the title bar and background over 0.2 s without moving the photo; the library toolbar returns as the closing flight starts; keys and arrow buttons change the photo at once while swipes slide (0.2 s, 40 pt or a quick flick); videos keep sideways swipes outside their control bar; closing after long paging loads that photo's rows and lands on its cell; black never reaches behind the sidebar; the opening flight lands on the fitted photo with no resize after landing; mouse drag, wheel and trackpad page sideways and reveal information, and scrolling back only hides it; the loading badge sits on the photo's bottom-right) |

## Cache and loading

| Behaviour | Where | Mac |
| --- | --- | --- |
| 64-pixel buckets, 352-px rendition edge | `ThumbnailPipeline.size` | shared |
| Cross-tier fallback so a tier change never blanks | `posters`, `smallPosters` | shared (macOS fallback added) |
| Rebuildable disk cache with budget | `ThumbnailDiskCache` | **open** (iOS only) |
| Decoded memory-mapped thumbnail tables | `ThumbnailTable` | mac (`MacThumbnailTables` for the overview mosaics only: 48 px fills at once, 96 px is still requested for month overviews; grid stops use the memory pipeline) |
| Small-tier requests skip the disk layer and use wide admission | pipeline | **open** |
| Bulk PhotoKit fetch for dense strips | `PhotoLibraryModel` | shared (`loadAllRows`) |
| Launch snapshot of the newest edge | `LaunchSnapshot` | **open** |
| Library changes during iCloud sync keep pixels and position | contract | partial |

## Verification

Motion is judged on a **Release** build, from 60 fps recordings of the app window
(frame-to-frame change, blank or bright frames, movement after the settle), against
the same interaction in the system app. See `scripts/build-mac-local.sh`.
