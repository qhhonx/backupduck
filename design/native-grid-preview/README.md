# iPhone calendar grid reference

This native workbench separates calendar hierarchy (Years / Months / All) from
All-grid thumbnail density. It uses generated illustrations and capture dates;
no private photo, sync status, account or transfer data is embedded.

Years use cover cards. Months sample at most six day covers into one mosaic per month, preserving every member for navigation. Tapping a cover
preserves the chosen asset as the destination anchor at the next level. The All
view remains a chronological, virtualized collection. Its held pinch can cross
one/three/five columns and dense month/year overviews, with a terminal year
overview. Cover-index pinch triggers Years → Months → All changes without following the fingers. On iOS 26+, native TabBar minimization owns the
full-bar-to-compact-button motion. A centered material surface holds Years/Months/All alongside the compact button;
no accessory row is installed above full navigation. Native navigation items
provide the existing filter and Select/Close actions with native sizing and
transitions. A compact centered selection review retains the app action surface, with Select Items
at zero selection and check marks only on selected photos. Backup sits beside the
filter in the native header. Actual compact-button visibility owns the period surface; it is not detached
by timers or temporary accessory traits. Pinch
retains its initial focal point and suspends panning; loaded pixels survive reflow. Older systems retain a
readable material-based navigation/browsing/selection fallback.

A scroll-dependent subtitle shows the visible capture range away from the recent
edge, and the actual total at that edge. Selection has a separate review surface
that shows only selected items and shares the main selection state. Transfer
submission remains a distinct confirmed action; no Photos delete action is added.

Record original-speed native interactions. Inspect held drags, reverse/cancel,
interrupted hierarchy changes, long-library anchors, reduction in motion and
legacy system fallbacks before adapting the reference into the production app.

## Sources and evidence

- [Apple UIKit new design](https://developer.apple.com/videos/play/wwdc2025/284/):
  native tab minimization/accessories, scroll-edge element registration and
  interruptible transitions.
- [Apple SwiftUI new design](https://developer.apple.com/videos/play/wwdc2025/323/):
  tab minimization, accessory placement and system glass controls.
- [TLLayoutTransitioning](https://github.com/SwiftKickMobile/TLLayoutTransitioning):
  content-offset interpolation, anchored placement and reverse-state poses.
  This is a historical implementation reference, not an imported dependency;
  do not copy its all-items-per-frame iteration into a large photo library.
- An open-source media gallery (notes kept locally): stable identities,
  gesture state and cancellation ownership.

The system Photos app is also operated directly on a simulator containing only
synthetic photos. Native state and motion are local evidence; static screenshots
and endpoint assertions do not establish proprietary animation parameters.

## Run

Use Xcode with the iOS SDK and XcodeGen. From the repository root, copy the four
workbench files to an ignored build directory, generate and build there:

```sh
python3 design/native-grid-preview/sync-controller.py --check
mkdir -p build/grid-preview
cp design/native-grid-preview/*.swift design/native-grid-preview/project.yml build/grid-preview/
xcodegen generate --spec build/grid-preview/project.yml
xcodebuild -project build/grid-preview/CalendarGridPreview.xcodeproj -scheme CalendarGridPreview -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath build/grid-preview/DerivedData CODE_SIGNING_ALLOWED=NO test
```

Choose an available iPhone simulator name. `--long-library` launches 55,000 dated
metadata items with a bounded generated-image cache; it is not a PhotoKit download
or a physical-device performance claim. Keep recordings and test results under
ignored local build storage. The production adapter uses the same interaction
implementation with real PhotoKit IDs, cancellation and shared semantic colors.


## Scene motion

Period controls animate matching photo IDs and fade unmatched content. Dense
pinch scales/crossfades live tile faces around one stable photo; it does not
reflow the native collection per frame. Stop at the thirty-one-column year
overview and avoid overlapping floating captions. Month compositions
support one through six covers including mirrored modules.

`--movie-cover` creates a small local synthetic movie and places it on calendar
covers for native muted playback checks. Year slides use actual metadata month
representatives. Playback/rotation pauses during scroll, reduced motion, low power
or background. This fixture does not verify real PhotoKit/iCloud video loading.

## Compact controls and scale release

Public native control visibility owns calendar-control visibility. Contraction
reveals the period surface from below; expansion fades it without creating a
regular accessory row. No timeout detaches a compact control. The title/subtitle use white media contrast
over a translucent black edge, with a 6 pt trailing gap beyond the native safe
area. Selection preserves hierarchy and density; overview taps enlarge before
selection, and two-finger scaling remains available. Phone options omit original
aspect. Pinch drives a live tile stage on a shared lattice: densities crossfade in
place around one photo. Direction changes retarget the current mixture after
small reversal travel, independently of date-range changes at geometric density
midpoints. Held fades keep running while the fingers rest; the newest boundary
constrains shrinking content during the gesture. Release preserves the preview
and settles on a critically damped spring before the native collection is adopted.

After changing production Grid behavior, run `sync-controller.py` to update the
standalone controller, then `--check` before building. This only writes the
reference controller; it never resets production source. The reference preserves
its generated images, system-color mapping and English accessibility identifiers.
Each generated image contains its own asset number so wrong viewport membership
is visible during intermediate-frame inspection. Pixel rendering resolves the
UIImage directly, independently of hidden view-layer display commits.

Generated thumbnail dimensions are pixels, with renderer scale one and cache
costs calculated from actual image bytes. Applying the screen multiplier again
would invalidate the bounded-cache fixture and can hide or invent eviction bugs.

`--pinch-regression` drives a repeatable generated-library sequence through the
same native stage: a three-column face held at five-column size, reversed
five/three faces with selection, and a newest-edge overview. Inspect the complete
recording, including both side edges and the final collection handoff. Ordinary
faces retain native duration, Live Photo and selection/status badges. Destination
row phases remain anchored through reversal and adoption. Extra horizontal slots
are chronological neighbors, materialized only for the current viewport.

The newest-edge overview fixture permits space below the incoming layout during
a held crossfade. Blending alone must not move the vertical focus to fill it;
retain the source layout's scale constraint until release.

The stage transforms whole native-size cell decorations. Gapless/ordinary faces
share an animated gap and clip, so outgoing photos cannot fill target separators.
Adoption seeds visible native cells with the stage's retained displayed images
before replacement requests, rejects smaller fallback callbacks, and retains a
cover through the first native commit. Compact native Library taps expand only;
reselection of the expanded tab returns to newest. Generated-image motion checks
must be supplemented by cache-eviction/late-delivery checks and physical-library
acceptance; immediate synthetic loaders do not establish PhotoKit continuity.

## Dense pixel ownership

The mirrored controller hands dense canvas pixels directly to a renewed gesture
and retains its cover until replacement strips publish. Layer groups track
gapless scaling, while captions remain at reading size. Source tests also delay
the bitmap queue, evict thumbnail caches, recycle strips and deliver request
callbacks synchronously. Generated media can check these ownership paths, but
does not establish real-library PhotoKit latency or physical frame pacing.
