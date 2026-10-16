# macOS interface reference

This interactive reference uses synthetic media, metadata, devices and outcomes.
It does not connect to a receiver or establish native implementation coverage.

The maintained contracts are [visual foundations](../backupduck-v1/specification.md),
[component rules](../ui-content-rules.md), [motion](../backupduck-v1/motion.md) and
[UI checks](../iteration-checklist.md). Use these current rules when historical
preview styling differs. Catalog entries reference implementation sources and
list design states, not counts of successful physical-device tests.

Keep platform controls native. Compare the same data and state in the prototype
and actual host; inspect action order, density, visible alignment, cancellation,
error/retry and parent-state preservation. Device observations and limitations
belong in contributor-facing [validation](../../docs/native-validation.md).

## Media interaction reference

The [focused Apple media reference](../apple-media-interactions.html) supersedes
older inline album switches and simple preview examples for these flows. Its
[contract](../apple-media-interactions.md) defines separate searchable scope
editors, shared consent sheets, dark media browsing, an information drawer/sidebar
and anchored continuous density changes. Check the native host independently.

## Photos library

The Photos app's native Years/Months/All Photos toolbar,
single-click selection, double-click entry, arrow navigation and Escape return
are desktop reference behaviours. See Apple's [shortcut guide](https://support.apple.com/guide/photos/pht9b4411b24/mac).

All Photos, Years and Months run oldest to newest and rest at the newest edge,
at the bottom, as in Photos. Older pages appear above the oldest loaded row
without moving the viewport; a viewport resting at the newest edge stays there.
Arrow keys follow the visual order: Left is older, Right is newer. A level
change or a return from the viewer centres the retained item.

Years and Months are a cover hierarchy over the filtered PhotoKit fetch, separate
from All Photos thumbnail size. A year is a portrait card with its year at top
left. A month is a heading above a four-by-two lattice: a hero two cells square
with up to four smaller covers, each labelled with its day number. All Photos
ends at the newest edge with the actual photo and video totals; no sync state is
shown because none is reported. Covers use actual assets and existing chronology,
without claiming Apple's private curation. Missing capture dates remain unknown.
Calendar cover membership is indexed off the main actor and does not request
full-library thumbnails. Native reusable collections virtualize both the covers
and the complete media grid. Clicking a year opens its months; a month opens its
matching All Photos anchor. A toolbar level change retains the visible asset.

The window toolbar owns the segmented level control, All Photos size slider,
original-aspect control and media-type filter. A compact content header shows the
visible date and library count, yielding to one selection count and review, clear,
and selected-backup actions. Command/Shift, rubber-band and keyboard selection
remain AppKit owned. Disabled actions do not forward clicks to media below.

A double-click or Space/Return opens the current photo inside the same window,
growing from its cell. The viewer is immersive: the media fills the window and
the controls fade after the pointer rests, returning on any movement. A mouse or
trackpad drag pages sideways; dragging up shows information and dragging down
hides it, then returns to the grid. The grid remains alive beneath the viewer, which uses the
system window background rather than a black stage. Escape or Back returns to the
currently viewed asset, retaining filter and selection. The viewer uses native
horizontal page tracking, fit/magnification, video/Live Photo playback and an
information sidebar with complete wrapping values. There is no permanent
filmstrip; Left and Right move through the library.
Selected review freezes its browsing batch; deselection does not shift the page,
and information is unavailable in that review. Backup still registers durable
intent through the existing confirmation and shared queue, never through browsing.

All Photos has six stops: four grids (3, 4, 6 and 9 columns) and two gapless
overview mosaics whose column counts follow the window width. Overviews draw
pooled image layers with no cells or badges and load the whole library; a click
steps toward the grid around that photo. Selected photos carry an accent outline,
never a check mark.

Density input begins at the tile under the pointer, tracks magnification linearly,
retains the focal position on reversal, resists beyond the smallest and largest
sizes, and settles to the previewed column count using `GridZoom`. Shrinking into
the last row moves the pivot to that edge, and a new gesture interrupts a settle
in place. A bounded
native tile stage draws both densities on one coherent lattice, including scaled
media decorations; per-item interpolation between wrapped rows is not allowed.
The native collection adopts the exact final pitch and retained displayed pixels.
It never
implicitly changes calendar level. Window resizing keeps the nearby visible asset.
Entry/return use an interruptible fade; Reduce Motion adopts state immediately.
Do not claim this reproduces Apple's proprietary transition curves. Verify native
intermediate frames independently from synthetic fixture and real-library loading.
