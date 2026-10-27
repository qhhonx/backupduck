# Apple motion: system APIs and how BackupDuck uses them

This is the implementation contract for motion on iPhone, iPad and Mac.
[Motion](backupduck-v1/motion.md) owns timings and choreography; this document
owns *how* those motions are built. Deployment targets are iOS 18 and macOS 15,
so the SwiftUI-animation bridges below are available everywhere; newer APIs
need an availability check and a fallback that looks the same.

## 1. Frameworks: UIKit and AppKit first

BackupDuck is a photo library. Its main surfaces depend on motion,
performance and direct manipulation, so they are built with UIKit and AppKit
end to end: library and folder grids, the photo viewer, the transitions
between them, their gestures, and the bars and toolbars inside those flows.
These frameworks offer the complete, long-optimised animation and
interaction APIs: collection views, interactive and interruptible
transitions, property animators and Core Animation.

SwiftUI is for supporting pages: settings, forms, onboarding text, sheets of
facts and other content without frame-level motion. A SwiftUI page may sit
inside a UIKit or AppKit container. The reverse must not happen: SwiftUI
state must never drive a main-surface motion. A tap that starts a transition
presents directly from the UIKit or AppKit controller that owns the source
view, never through a SwiftUI state change and a later run-loop turn.

Existing SwiftUI shells on main surfaces are migration debt. Move them when
the surface is next touched:
- the iPhone root tab view;
- the remaining viewer presentations that are not yet `MediaViewerTransition`:
  the iPad library's hidden SwiftUI host, recorded History photos and selection
  review. The iPhone library and the album browser present directly.
- the Mac viewer toolbar.

## 2. The rule for animation

Animation pixels come from the system's animation engines: UIKit and AppKit
view animation, Core Animation, and SwiftUI. These run on the render server,
retarget smoothly, carry velocity and respect accessibility settings.

- Never compute animation frames in app code on `CADisplayLink`, `Timer`,
  `UIUpdateLink` or a dispatch loop. Do not interpolate frames, positions,
  opacities or spring physics by hand.
- Never poll presentation layers to find out what a system animation is
  doing. Use the system's events instead: layout callbacks, transition
  coordinators, delegate methods, trait changes, or KVO on a property that
  supports it.
- Gesture tracking is the only per-event work: each gesture callback sets or
  retargets the tracked value. Release always hands off to a system spring
  carrying the gesture velocity.
- A frame loop is allowed only where no animation API can express the
  behaviour and the owner has agreed to it. Today that means edge autoscroll
  while drag-selecting, and benchmarks that never ship. Each one names its
  reason in a comment.

## 3. How to study a reference interaction

Frame-by-frame recordings of a system app are for *learning*, not copying.
For each interaction, write down:

- the order and overlap of every element's change (which starts first and
  which finishes last);
- the curve family: spring (no bounce, or a little), ease, or linear;
- the duration;
- whether the change follows a finger or a release velocity;
- what happens on reversal, interruption and Reduce Motion.

Then choose the system mechanism below that produces that behaviour, and
implement it with that mechanism. Matching a curve frame by frame in our own
loop is not acceptable, even when it looks the same in a recording.

## 4. iOS and iPadOS

### View animation

- `UIView.animate(springDuration:bounce:initialSpringVelocity:delay:options:)`
  (iOS 17) is the default spring. Choose the duration for pacing and the
  bounce for character. Use 0 bounce for UI chrome; about 0.15 is a subtle
  bounce, and about 0.3 is clearly bouncy.
- Springs keep position and velocity continuous. An interrupted spring
  retargets from its current velocity. Never wait on settling time; use the
  completion of the perceptual duration.
- `UIView.animate(_ animation: Animation)` (iOS 18) accepts SwiftUI
  animations. Use `.interactiveSpring` on each gesture change and `.spring`
  on release, and velocity is carried automatically. This is the default
  pattern for every gesture handoff. `UIViewPropertyAnimator` with
  `UISpringTimingParameters(dampingRatio:initialVelocity:)` remains for
  scrubbable motion, with the release velocity divided by the remaining
  distance.
- `UIView.transition(with:duration:options: .transitionCrossDissolve)`
  crossfades a content swap in place. Use it for image resolution changes,
  icon state changes and label text changes.
- `UIView.performWithoutAnimation` sets start states. Set the start without
  animation, then animate to the end in a separate block.

### Property animators: interactive and staggered

`UIViewPropertyAnimator` is the interactive engine:

- `fractionComplete` scrubs a paused animation from a gesture. Set
  `scrubsLinearly` and `pausesOnCompletion` as needed.
- `continueAnimation(withTimingParameters:durationFactor:)` hands a scrub
  back to the system with a new curve. `isReversed` plays it back to the start.
- `addAnimations(_:delayFactor:)` staggers elements inside one animator: each
  block starts after its share of the duration.
- `UIView.animateKeyframes` and `addKeyframe(withRelativeStartTime:relativeDuration:)`
  inside the animator block give per-element windows (start, length) on the
  animator's single timeline. Scrubbing and reversal still work.
- Keep one animator per motion. Stop it with `stopAnimation(false)` followed
  by `finishAnimation(at: .current)`. Then start the next motion from the
  current values.

### View controller transitions

- `preferredTransition = .zoom { context in sourceView }` (iOS 18) morphs a
  cell into the pushed or presented controller. It is continuously
  interactive and its dismissal can be dragged.
  - The closure runs again when zooming out. Look up the source view from a
    stable identifier, not a captured cell.
- Custom transitions use `UIViewControllerAnimatedTransitioning`.
  `interruptibleAnimator(using:)` returns one `UIViewPropertyAnimator` for the
  whole transition. `UIPercentDrivenInteractiveTransition` (or a custom
  `UIViewControllerInteractiveTransitioning`) drives it from a gesture.
- `transitionCoordinator?.animate(alongsideTransition:completion:)` runs our
  chrome changes on the transition's own timeline, including when the user
  drives it interactively and when it is cancelled. Check
  `context.isCancelled` in the completion. For views outside the container,
  use `animateAlongsideTransition(in:)`.

### Collections and scrolling

- `performBatchUpdates` and diffable snapshots animate membership changes.
- `setCollectionViewLayout(_:animated:)` animates a layout change.
  `startInteractiveTransition(to:completion:)` returns a
  `UICollectionViewTransitionLayout`.
  - During a pinch, set `transitionProgress` and invalidate the layout.
  - On release, call `finishInteractiveTransition()` or
    `cancelInteractiveTransition()`.
  - A custom transition layout (from the delegate) can interpolate anchors
    and opacity.
- `UIScrollView` owns deceleration, bounce and its own zoom (`zoomScale`,
  `setZoomScale(_:animated:)`). Do not reimplement them.

### Liquid Glass (iOS 26 and later)

- Glass appears and disappears by animating `UIVisualEffectView.effect`.
  `UIGlassEffect` materializes and `nil` dematerializes; never fade glass
  with `alpha`. Animate tint, content colour and corner configuration in the
  same block.
- `UIGlassContainerEffect` (with its `spacing`) merges and splits nearby
  glass shapes when their frames animate.
- The system bars own their morphs: `tabBarMinimizeBehavior`, the tab
  accessory, and the scroll edge effect. Hide or show bar items and bars with
  their own APIs so their glass animates correctly. Do not set `alpha` on
  bar hosts.
- `traitCollection.tabAccessoryEnvironment` and `updateProperties()` report
  bar state changes as events.

### Core Animation

- `CABasicAnimation`, `CASpringAnimation(perceptualDuration:bounce:)` and
  `CAKeyframeAnimation` animate layer properties on the render server.
  Grouped animations share one timeline.
- `isAdditive` animations retarget without jumps.
- `contentsRect` and `contentsGravity` animate a crop, for example from a
  square thumbnail to a fitted photo.
- `speed = 0` with `timeOffset` pauses or scrubs a layer timeline
  (`CAMediaTiming`). Restore `beginTime` on resume.
- Implicit layer actions are disabled only while setting start states.

### SwiftUI

- `withAnimation(.spring(duration:bounce:))`, `.smooth`, `.snappy` and
  `.bouncy` are springs. Use `.transition` for insertion and removal, and
  `matchedGeometryEffect` for shared elements.
- `phaseAnimator` handles chained steps and `keyframeAnimator` handles
  per-property tracks. Keyframes do not retarget, so avoid them for
  interactive motion.
- `navigationTransition(.zoom(sourceID:in:))` with
  `matchedTransitionSource` (iOS 18) is the SwiftUI zoom transition.
- `UIViewRepresentable.updateUIView` applies the transaction's animation to
  UIKit views with `context.animate { }` (iOS 18), so SwiftUI and UIKit move
  together.

## 5. macOS

- `NSAnimationContext.runAnimationGroup { context in ... }` with
  `view.animator()` animates frames, alpha and layer-backed properties.
  - Set `context.duration`, `context.timingFunction` and
    `allowsImplicitAnimation`.
  - Nested groups keep their own duration.
- `NSAnimationContext.animate(_ animation: Animation, changes:)` (macOS 15)
  accepts SwiftUI springs, including gesture retargeting. It is the default
  for gesture handoffs on Mac; `CASpringAnimation` remains for layer-only
  motion.
- Layer-backed views animate through Core Animation exactly as on iOS; the
  Core Animation section above applies. Prefer `updateLayer` and
  `.onSetNeedsDisplay` redraw so animations do not redraw content.
- SwiftUI on Mac has the same animation APIs, except the navigation zoom
  transition.
- Magnification and scroll gestures arrive as events. Track them per event,
  then hand off to a spring.

## 6. Human Interface Guidelines: motion

- Motion must have a purpose: it conveys status, gives feedback or explains
  where something went. Never add it for decoration, and avoid extra motion
  on very frequent interactions; standard controls already animate.
- Feedback follows the gesture and the person's expectation: a view that
  slides down to appear is dismissed by sliding it down.
- Keep feedback brief and precise. People can always interrupt or cancel; no
  one waits for an animation to finish.
- Motion is optional:
  - Reduce Motion replaces spatial movement with a crossfade.
  - Reduce Transparency replaces glass with a solid material.
  - Information is never conveyed by motion alone.
- System components already adapt their motion to the input method and to
  accessibility settings. Custom motion must not fight them.

## 7. BackupDuck motions and their mechanisms

| Motion | Mechanism now | Target mechanism | Status |
|---|---|---|---|
| Photos-tab period capsule | KVO on the bar's morph target; `UIView.animate` spring materializes glass | — | Conforms |
| iPhone library viewer present, dismiss and drag to dismiss | Custom present transition (`UIViewControllerAnimatedTransitioning` and `UIViewControllerInteractiveTransitioning`): a grid snapshot crossfades above the opaque viewer page, and a media snapshot flies on one `UIViewPropertyAnimator` spring; the drag updates per gesture event | — | Conforms |
| iPhone grid pinch zoom (Photos tab) | Per-gesture-event tracking; crossfade as Core Animation keyframes scheduled at events; release settle as one `CASpringAnimation` per density layer over a layout made once at the target pose | — | Conforms |
| Mac grid zoom (Library, Folders, History) | Display-link settle and crossfade | Magnify events tracked per event; release goes to a Core Animation spring | Open |
| Mac level and viewer flights | One Core Animation group (bounds, position, cornerRadius, opacity keyframes); a moved destination is absorbed by an additive animation | — | Conforms |
| iPad timeline mode morph | Display-link `transitionProgress` | `setCollectionViewLayout(_:animated:)` or an interactive transition finished by the system | Open |
| Drag-select edge autoscroll | Display link while the finger is held | — | Allowed exception |
| Scroll benchmarks | Display link behind a launch argument | Test-only; must not ship | Test hook |
