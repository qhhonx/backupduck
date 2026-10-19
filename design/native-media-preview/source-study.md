# Media interaction source study

## Gallery pager mechanics

Studied from an open-source media gallery; the notes are kept with the local
design notes.

The pager keeps a small visible neighbourhood and preserves the central item's
relative horizontal offset when rearranging its nodes. Scroll progress is
reported separately from committed identity. Loading decisions account for
dragging and deceleration. This matters more than adding an easing constant to
an image swap: one owner must coordinate geometry, identity and loading.

The thumbnail container receives central item and fractional page progress.
During thumbnail dragging it owns the position, changes the current item as
the nearest thumbnail changes, and recentres after deceleration. An externally
driven recenter must not fight a user's drag.

The controller derives background/control opacity from vertical displacement,
then considers both velocity and distance on release. It resolves the current
media's destination rather than always returning to the originally opened item.
No source, dependency or fixed threshold is imported into BackupDuck. These are
reference mechanisms, not copied code.

## NYTPhotoViewer

Primary sources:

- [Dismissal interaction](https://github.com/nytimes/NYTPhotoViewer/blob/develop/NYTPhotoViewer/NYTPhotoDismissalInteractionController.m)
- [Transition animator](https://github.com/nytimes/NYTPhotoViewer/blob/develop/NYTPhotoViewer/NYTPhotoTransitionAnimator.m)

The dismissal implementation keeps a transition context, restores the underlying
presenting view when needed, updates position and background with the gesture,
and explicitly finishes or cancels. Release timing incorporates velocity. The
zoom animator hides original endpoints while temporary views animate and restores
them at completion. This avoids duplicate images and stale hidden thumbnails.
Its historical constants and old-platform assumptions are not a modern motion
specification. No source was incorporated into the reference.

## Apple platform guidance

- [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Interactive view-controller transitions](https://developer.apple.com/documentation/uikit/uiviewcontrollerinteractivetransitioning)
- [Spring timing parameters](https://developer.apple.com/documentation/uikit/uispringtimingparameters)

BackupDuck should distinguish a small decision from an expandable information
surface. Controls use platform symbols, target sizes and system navigation,
while content uses shared semantic colors. Gesture-driven progress is direct;
settling may use velocity-aware timing. A single global cubic curve is not a
substitute for an interruptible transition context.

## Visual references and evidence limits

Apple Photos and Google Photos are visual and interaction references for grid
hierarchy, restrained viewer chrome, media fitting and information presentation.
Their recordings do not expose private source, easing coefficients or gesture
state machines. Sparse samples lose momentum, brief stalls and reversal details.
Review a whole interaction at its original speed, then inspect densely spaced
frames around a specific event. Native replay and physical-device touch checks
are separate requirements; neither screenshots nor test labels establish feel.

## Changes required before the production revision is accepted

1. Replace the mixed SwiftUI/UIKit modal state with one transition coordinator.
   Lock an input direction only after intent is known; unlock on every cancel,
   failed gesture, interrupted presentation and settled page.
2. Resolve grid return by current asset ID and current layout. Use a single
   window coordinate space and the displayed image rectangle, not the full
   media container. Check portrait/landscape and offscreen destinations.
3. Coordinate native page progress and thumbnail scrubbing without feedback
   loops or controller replacement during a drag. Zoomed content owns panning.
4. Give consent the shared content-sized and expandable presentation with one owner; loading and
   retry states belong to the current asset. Remove overlapping central notices.
5. Rework grouped grid zoom as a distinct layout algorithm. Preserve focal
   asset geometry, not only final scroll offset; compare uninterrupted and
   reversed transitions on long libraries. The candidate now preserves a
   transient two-axis phone focus and settles the column edges; motion feel
   still requires physical-device acceptance.
6. Measure album fetch, image decode, requests/cancellations and list updates.
   More attractive cards alone do not prove smoother scrolling.
