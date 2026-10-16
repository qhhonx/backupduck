# Design system and interface contracts

BackupDuck uses a shared visual language with native platform controls. This
folder contains design tokens, interactive prototypes and implementation
contracts. Prototypes use synthetic data; they do not perform media transfers,
request system permissions or prove native feature completion.

## Maintained reference

- [Visual foundations](backupduck-v1/specification.md): semantic colors,
  typography, platform surfaces and state semantics.
- [Component and content rules](ui-content-rules.md): layout ownership,
  preference density, feedback, icons and durable task submission.
- [Motion](backupduck-v1/motion.md): timing, stable progress geometry and
  accessibility fallbacks.
- [Iteration checks](iteration-checklist.md): checks required for UI changes.
- [Tokens](backupduck-v1/tokens.json): source for generated platform colors.

HTML prototypes are frozen historical references and are no longer maintained.
Use the current component contracts and native implementation when one differs;
an old screen is not a reason to revert the current implementation.

## Platform references

| Platform | Interactive reference | Implementation |
| --- | --- | --- |
| iPhone / iPad | [Prototype](ios-v1.2/index.html) | `apps/ios/BackupDuck`, `apps/apple/Shared` |
| macOS | [Prototype](macos-v1.2/index.html) | `apps/macos/BackupDuck`, `apps/apple/Shared` |
| Android receiver | [Prototype](android-v1.2/index.html) | `apps/android/app/src/main` |
| Receiver browser | [Prototype](web-v1.2/index.html) | `crates/native/src/dashboard` |

Android and Windows senders are separate, unfinished work. Their prototype or
experimental implementation must not be presented as a shipped platform.

## Keeping design and implementation aligned

For new screens or changed navigation, update the contract documents and verify
in the native app; do not add HTML references. For component refinements, update
the component and its contract in one change.

Compare native windows with the reference using the same synthetic data and
state. Check light/dark appearance, narrow layouts, large text, keyboard or
system back navigation, cancellation, failure and recovery. Generated screenshots
and prototype checks are evidence for their specific scope, not a substitute for
physical-device behavior. See [validation](../docs/native-validation.md).

Public documentation explains reproducible behavior and contribution requirements.
Personal acceptance notes, device-installation logs and development handoffs do
not belong in the source release. See [public-source policy](../docs/public-source-policy.md).

## Apple library extension

Apple senders share PhotoKit-managed high-quality media loading, an information
panel, source-level type/album backup scope and calendar grid geometry. Native
collections retain stable asset IDs through all/day/month view changes. See
[component rules](ui-content-rules.md#sender-media-browsing) for ownership and
[time-view motion](backupduck-v1/motion.md) for native transitions. These changes
do not extend the unfinished Android/Windows senders or imply cloud backup.

The [Apple media interaction contract](apple-media-interactions.md) and its
[focused interactive reference](apple-media-interactions.html) cover cloud loading,
searchable album scope, continuous media paging and anchored density changes.
Use this reference for those flows instead of older inline scope/preview examples.

HTML references do not establish native media gesture quality. The
[native media reference](native-media-preview/README.md) provides an independently
runnable UIKit interaction study and
[source-backed revision requirements](native-media-preview/source-study.md).
Keep workbench evidence separate from production verification and physical-device
acceptance. Native calendar behavior follows the focused phone contract below;
media detail behavior remains a separate iteration.

The [iPhone calendar Grid contract](iphone-calendar-grid.md) and
[native Grid workbench](native-grid-preview/README.md) separate Years/Months/All
browsing from All-grid density. They supersede the phone All/Days/Months coupling
in older references; desktop behavior remains separate.

Mac calendar and in-window media browsing follow the
[contract](macos-v1.2/specification.md#photos-library). This supersedes the
historical desktop All/Days/Months grouping described in older references.
