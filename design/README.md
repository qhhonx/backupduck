# Design system and interface contracts

BackupDuck uses a shared visual language with native platform controls. This
folder holds the redesign's principles, contracts and design tokens. The native
apps and their design catalogs are the reference for how a page looks and
behaves; there are no HTML references to maintain.

## Principles and standards

- [Constitution](constitution.md): who BackupDuck is for and the rules every
  page follows; redesign before refinement.
- [Platform expression](platform-expression.md): which native container and
  control expresses each recurring task on iPhone, Mac and Pixel. Chrome is the
  system's; BackupDuck's character lives in content.
- [Visual standard](visual-language.md) and [interaction standard](interaction.md).
- [Component and content rules](ui-content-rules.md): layout ownership,
  preference density, feedback, parallel supporting text and durable submission.
- [Motion](backupduck-v1/motion.md): timing, stable progress geometry and
  accessibility fallbacks.
- [Apple motion APIs](apple-motion-apis.md): which system animation API
  builds each motion; app code never draws animation frames.
- [Tokens](backupduck-v1/tokens.json): source for generated platform colors, text
  styles, spacing, radius and motion; see [foundations](backupduck-v1/README.md).
- [Iteration checks](iteration-checklist.md): checks required for UI changes.

## Product and page contracts

- [Product brief](product-brief.md), [feature triage](feature-triage.md),
  [navigation](navigation.md) and [main flows](flows.md).
- [Library and backup history](library.md), [records and photo detail](records.md),
  [Apple media interactions](apple-media-interactions.md) and the
  [iPhone calendar grid](iphone-calendar-grid.md).
- [Settings](settings.md), [Mac Folders](mac-folders.md),
  [Mac: connect a Pixel](mac-connect.md), [Pixel: connect a device](pixel-connect.md).
- [Apple notifications](apple-notifications.md) and
  [Live Activity](apple-live-activity.md).
- [Copy glossary (zh-Hans)](copy-glossary.zh.md).

Progress and status: [redesign roadmap](redesign-roadmap.md) (current step and
open decisions) and [page register](page-register.md) (redesigned or legacy, per
page). Check a page's status in the register before touching it.

## Platforms

| Platform | Implementation | Design catalog |
| --- | --- | --- |
| iPhone / iPad | `apps/ios/BackupDuck`, `apps/apple/Shared` | `apps/ios/Catalog`, scenarios in `apps/apple/Catalog` |
| macOS | `apps/macos/BackupDuck`, `apps/apple/Shared` | `apps/macos/Catalog`, scenarios in `apps/apple/Catalog` |
| Android receiver | `apps/android/app/src/main` | `apps/android/app/src/catalog` |
| Receiver browser | `crates/native/src/dashboard` | — |

Each catalog renders production components with synthetic scenarios; its
README lists the scenarios and how to launch them. Android and Windows senders
are separate, unfinished work and must not be presented as shipped platforms.

## Keeping design and implementation aligned

New screens or changed navigation start from the contract documents and are
verified in the native app. A component refinement updates the component and its
contract in one change. Compare native windows with the contract, and with the
system app for anything the system also does, using the same synthetic data and
state. Generated screenshots are evidence for their scope only, not a substitute
for physical-device behavior; see [validation](../docs/native-validation.md).

The `*-v1.2` folders and every HTML prototype in this folder are frozen history
from before the redesign. Do not take design direction from them; where a
current contract still links into one (the Mac library section of
`macos-v1.2/specification.md`), that section is the contract until it moves.

Public documentation explains reproducible behavior and contribution requirements.
Personal acceptance notes, device-installation logs and development handoffs do
not belong in the source release. See [public-source policy](../docs/public-source-policy.md).
