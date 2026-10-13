# iPhone calendar grid reference

This native workbench separates calendar hierarchy (Years / Months / All) from
All-grid thumbnail density. It uses generated illustrations and capture dates;
no private photo, sync status, account or transfer data is embedded.

Years use cover cards. Months group day covers into a mosaic. Tapping a cover
preserves the chosen asset as the destination anchor at the next level. The All
view remains a chronological, virtualized collection. Its held pinch can cross
one/three/five columns and dense month/year overviews, with a terminal year
overview. Cover-index pinch moves Years → Months → All separately. On iOS 26+, native TabBar minimization owns the
full-bar-to-compact-button motion. Its inline accessory holds Years/Months/All;
no second accessory row remains above full navigation. Native navigation items
provide the existing filter and Select/Close actions with native sizing and
transitions. A compact centered selection review retains the app action surface, with Select Items
at zero selection and check marks only on selected photos. Backup sits beside the
filter in the native header. Native accessory traits are checked after transition
settling, so temporary regular placement cannot remove inline controls. Pinch
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
- [Telegram GalleryUI](https://github.com/TelegramMessenger/Telegram-iOS/tree/master/submodules/GalleryUI/Sources):
  stable identities, gesture state and cancellation ownership.

The system Photos app is also operated directly on a simulator containing only
synthetic photos. Native state and motion are local evidence; static screenshots
and endpoint assertions do not establish proprietary animation parameters.

## Run

Use Xcode with the iOS SDK and XcodeGen. From the repository root, copy the four
workbench files to an ignored build directory, generate and build there:

```sh
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
pinch scales/crossfades bounded canonical viewport images around one stable photo;
it does not interpolate individual rows. Keep at most three scene images, stop
at the year overview, and avoid overlapping floating captions. Month compositions
support one through six covers including mirrored modules.

`--movie-cover` creates a small local synthetic movie and places it on calendar
covers for native muted playback checks. Year slides use actual metadata month
representatives. Playback/rotation pauses during scroll, reduced motion, low power
or background. This fixture does not verify real PhotoKit/iCloud video loading.
