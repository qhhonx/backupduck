# Native media interaction reference

This is a separate, runnable UIKit design reference, **not a replacement app or
an accepted implementation**. Its bundle identity is
`app.backupduck.design.media`. It uses generated illustrations, fictional photo
information and a public example map location. It never reads PhotoKit,
credentials, backup queues or production preferences.

Generate the project outside the source tree with XcodeGen, then build/run the
`MediaInteractionPreview` scheme in an iOS simulator:

```sh
mkdir -p build/media-reference
cp design/native-media-preview/Preview.swift design/native-media-preview/InteractionTests.swift build/media-reference/
xcodegen generate --spec design/native-media-preview/project.yml --project build/media-reference
```

## Decisions to evaluate by operating the reference

- System navigation for Library and settings. One media-filter icon with a named
  menu; the All/Day/Month choice remains named rather than an ambiguous calendar
  icon. Dates belong to pinned grid section headings. A filter-active badge and
  accessibility value are required in production.
- Dark media canvas with a system back symbol, capture date and swipe-up information. No phone
  previous/next arrows. Desktop arrow-key navigation remains appropriate.
- A native horizontal pager and independently draggable thumbnail strip. Both
  describe the same current item; strip movement is not a row of five buttons.
- A compact, content-sized cloud confirmation, one explanation, two equal-width
  actions with the primary action trailing. Use the shared grabber and expandable large detent. Loading belongs to the current item's header.
- Information moves into the photo context. A map is visible when information is
  opened and location exists; there is no extra reveal-map action. Only actual
  metadata may populate the production information view.
- Settings secondary screens keep the root tab bar. No hide/show transition on
  push/pop. Album choices use three-column covers, names, counts, selected marks
  and search. Selected cover marks share the gallery bottom-trailing position. Accessibility sizes must fall back to a denser readable list.

## Deliberate limitations

The calendar menu currently replaces grouping without a motion claim. The pinch
reference uses `UICollectionViewTransitionLayout` for continuous geometry. It
does **not** solve the final grouped calendar transition, 2D pinch anchoring,
production paging, album PhotoKit performance, media playback, network loading
or permissions. Cloud progress is a clearly synthetic timed scenario.

Do not turn this reference into a release merely because it builds. Before
porting any interaction, operate rapid/reversed drags, interruptions, edges,
zoom-to-paging handoff, info scrolling, thumbnail scrubbing, changed-item return
to grid, reduced motion and larger type. Record native motion at original speed;
selected frames supplement but cannot replace continuous playback and actual
touch testing. Keep private recordings and acceptance evidence in ignored build
storage. See [source study](source-study.md).

## Production implementation boundary

The sender implementation uses a UIKit-owned three-slot paging scroll view,
separate virtualized scrubbing strip with a compact dragging state and expanded settled current item, interruptible information drawer and a
current-asset return destination. It retains PhotoKit media and existing backup
state; the standalone reference remains synthetic. Consent uses the shared fitted and large detents with a system grabber. Actual asset location opens a map with
information. Album covers have cancellable local requests and a 24 MiB cache.
The production calendar uses anchored collection attributes and a critically
damped release response documented in the media interaction contract. None of
these source changes constitutes physical-device or user acceptance.

## Selected review

The leading Show Selected action opens a three-column review of three synthetic
items. Its leading browse icon reuses the same viewer and photo-flight animator
with a bounded batch. Back and downward drag return to that review. Production
adds the shared selection model, current-item toggle, Deselect All and Done;
this reference does not access PhotoKit or backup data.
