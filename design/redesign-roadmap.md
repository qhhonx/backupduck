# Redesign roadmap

The single place that says where the BackupDuck redesign stands and what comes
next. Start with "Current step" and update this file with each milestone,
decision or page status. Page detail lives in `page-register.md`; rules live in
`constitution.md`, `visual-language.md` and `interaction.md`.

Last updated: October 22, 2026.

## Goal

Rebuild BackupDuck for ordinary people, from the long-term target rather than
the earlier apps (`product-brief.md`, constitution P9), and replace the
production iPhone, Mac and Pixel apps with it. Every page follows the visual
standard (V1–V7) and the interaction standard (I1–I9), is built from the shared
components, and is verified in the native design catalogs before it becomes the
default.

Scope: iPhone and Mac senders, Pixel receiver. Android and Windows senders and
the browser page come later. Publishing (TestFlight, store, website) needs the
owner's explicit authorization and is not part of this plan.

## Done so far

- Constitution draft 2, product brief, feature triage, flows, navigation (D3
  closed), page register.
- Tokens for every platform with the literal check (`d65dfb4`); catalogs on all
  three platforms (`b183ce7`).
- Structure redesigned and built behind the catalog design switch: settings,
  first run, hubs, first-photo flight, navigation skeleton, connect on all three
  platforms, records and photo detail, library backup views and marks.
- October 19: the owner approved the overall visual and interaction direction
  from a canvas covering standards and every flow. Standards recorded in
  `visual-language.md` and `interaction.md`; tokens extended (card radius,
  motion insert and moment, preference-row density).

## Plan

Each step ends with its checks green and one local commit. Steps 3a–3d can run
in parallel sessions because they touch separate folders; shared Apple code
(`apps/apple/Shared`) has one owner at a time.

| Step | Work | Done when | State |
| --- | --- | --- | --- |
| 1 | Standards in the repository: `visual-language.md`, `interaction.md`, tokens, AGENTS.md pointers | Export `--check`, literal check and public audit pass | Done |
| 2 | Shared components. Apple (`DuckLook.swift`): card, status card, problem card, primary and tinted capsule buttons, status pill, identity header, empty state, guided-flow scaffold, media marks; Mac metrics. Pixel (`DuckLook.kt`): the same in Material 3. Fold the `proposedLook` probes (`IOSHubLook`, `ReceiverHubLook`) into the components and remove the `proposedLook` switch | Components exist on both stacks, use only tokens, have catalog scenarios in light, dark and large text | Done on both stacks |
| 3a | iPhone pages on the components, by flow: hub, photos views and photo info, first run, problems, settings (including the newly designed Devices, album chooser, Help) | Each flow's catalog scenarios pass review criteria in `iteration-checklist.md`; iOS tests pass | Hub, Devices, Help and A8 viewer implemented; notifications and Live Activity implemented with system acceptance remaining. Scope editors rebuilt; selected review, scope-contract reconciliation and first-run continuation remain |
| 3b | Pixel pages: receive hub, received photos and detail, first run, connect, devices, settings, the newly designed Storage page | Android unit tests, catalog and debug builds pass; native catalog checked | Pages implemented, received-original previews and problem thumbnails added; native acceptance and register blockers remain |
| 3c | Mac pages: overview, library views and marks, history, settings list and detail, connect, viewer/inspector, menu bar | Mac catalog checked in light and dark | Overview, Settings with Devices and Help, connect, library marks, A8 viewer, Folders and menu bar implemented; native acceptance and register blockers remain |
| 3d | Core data for new pages: a "saving to Photos" tile state, Pixel storage breakdown, device page counts | `cargo test` and `cargo fmt --check` pass; hosts read the new fields | `source_job`, saving marks, storage/folder facts, confirmed history publication and bounded received-original previews implemented (`c8f4af3`, `c9363d6`, `e87c8f8`, `524c626`) |
| 4 | Remaining pages from the standards: Mac first run and Folders, notifications, Live Activity, Pixel cleanup recovery, help articles | Catalog scenarios for each | Folders, notifications, Live Activity and Apple help implemented; no dedicated Mac first-run wizard. Pixel D2/Storage entry done; cleanup recovery, help and other register blockers remain |
| 5 | Verification pass: light, dark, large text (one step above default), long localized copy, failure and recovery on every flow; Release-build motion recordings on iPhone and Pixel XL | Findings fixed or recorded under Known gaps | Not started |
| 6 | Make the redesign the default: the design switch defaults on, legacy pages and remnants removed, `page-register.md` all redesigned, HTML prototypes retired | All checks pass on all three platforms | Default on in all three apps (0252a3f, fa9c23f); legacy removal remains |

## Current step

Step 6 is in effect on all three apps (the redesigned pages are the default).

October 21, 2026: the owner approved `platform-expression.md` (which native
container and control expresses each task; chrome is the system's, content is
BackupDuck's) and the Mac Folders structure (`mac-folders.md`).

Implementation status:

1. **Platform audit — implemented.** Native chrome/navigation corrections
   (`82a460f`, `f47e726`, `524c626`) remain the baseline; structural and
   acceptance gaps are recorded in `page-register.md`.
2. **D1 — decided and adopted on iPhone, Mac and Pixel (October 22).** iPhone
   keeps tile flight and full-aspect system long-press preview; its viewer uses
   system composition with state on Info (`4517cd5`). Mac shares the in-window
   viewer and facts inspector across Library, History and Folders (`caf910e`),
   with system browsing toolbars (`96748d3`). Pixel uses tile flight, contextual
   selection and the system-composed viewer (`0c2c0ea`), recorded metadata
   (`f266d9b`) and inset-safe details (`36a10d1`). Comparison switches are removed;
   this closes adoption, not Release/device acceptance.
3. **D2 — done.** Automatic cleanup belongs to Storage; Experiments is retired
   and probes belong to Diagnostics (`895f8e5`, `6ccdda8`). Legacy account/setup
   and cleanup recovery descendants still need redesign.
4. **Settings bottom, About and feedback — done on all three platforms.**
   Version/update status and Diagnostics · Advanced routing are rebuilt;
   reserved author/email/rating items stay hidden while absent (`d9f2323`,
   `544f1ed`, `895f8e5`). Apple scope editors and direct selected-backup
   registration are implemented (`49efc3e`, `2f00d25`); review/contract gaps remain.
5. **Notifications, Live Activity and Mac menu bar — implemented.** System
   delivery, activity lifecycle and menu-action acceptance remain; Mac permission
   entry/tap integration and iPhone onboarding routing are still incomplete.
6. **Iteration checks.** Redesign iterations check light and dark only
   (`f21b6ba`); large text and broader layout/recovery checks belong to release
   verification under `iteration-checklist.md`. Pixel shared balanced wrapping
   and the single short cloud footer are implemented (`c88e354`).

## Next

Follow the source audit's priority order, with completed work removed:

1. **iPhone onboarding — done (`e325845`).** Was: retain the flow until durable completion; add an exit
   and recovery from first-photo waiting.
2. **Mac notifications — done (`e325845`); system delivery and taps still need device acceptance.** Was: add explicit permission entry and receiver-scoped route
   consumption; verify cold/warm taps.
3. **Mac Overview and History — Needs you and mosaic done (`e325845`); History toolbar built, Mac capture pending (`3ee7b96`).** Was: route Needs you to the requested records, settle
   the one-grid direction and connect recent mosaic photos to the shared viewer.
4. **Pixel cleanup recovery — in progress (`18bc59b`): row states done; switch-on journey, pending page and one line break open.** Was: finish the Storage journey and separate retained
   technical probes from old account-binding, setup and progress/result UI.
5. **Apple remaining review/contracts:** redesign selected-photo review and
   remove its radius override; reconcile A6 with the stale album-column rule and
   review the now-inventoried context, History and sharing routes.
6. **Pixel Help — contract written (`settings.md` Help Center), not built.** Redesign around tasks/problems and their recovery destinations.
7. **Pixel Advanced/compatibility:** redesign Format Conversion and browser
   access; decide supported retention/archive routes and ordinary recovery UI.
8. **Pixel records ordering:** make latest-change ordering global across core
   paging; viewer adoption, metadata, chrome and the repeated footer are resolved.
9. **Technical pages — Apple Diagnostics built (`3ee7b96`), Pixel not started.** Was: redesign diagnostics (log, entry detail, exports) on all
   three platforms and the Pixel compatibility/archive routes for their
   technical audience: the same components and standards, exact detail kept.
10. **Release/native/device acceptance:** real pairing, notifications/Live
   Activity, gesture reversal/anchors, settings persistence, update handoffs and
   failure recovery. Check light/dark, narrow layouts, large text and long copy;
   measure Release motion from recordings. Catalog/build checks do not replace
   physical-device observations.
11. **Legacy removal:** after production review and acceptance, remove remaining
    superseded pages and resolve compatibility routes explicitly.

## Later (after the roadmap)

- **Pixel grid and viewer as shared components (light):** pass the data source,
  state marks, actions and detail facts in from the page so nothing
  receiver-specific lives inside the grid or viewer, sized for large libraries,
  ready for a future Android sender. No new module and no sender features.

Publishing waits for the owner.

## Product decisions made

Recorded in `product-brief.md`, `feature-triage.md` and `flows.md`: positioning
(bold benefit, conditions in small print), the feature triage, defaults (format
conversion off, freeing space after saving on), the welcome headline, step
marks, how the Pixel keeps space free (Smart Storage plus recommended auto
cleanup), photo state wording ("in the Pixel's Photos"), Pixel navigation in
Material 3, settings at most eight rows, the hub rules, and (October 19) no duck
on problem states, Mac settings rows at 41 pt, rounded numerals only on hub
counts as a trial.

## Open decisions (owner)

- Adopt the constitution formally.
- D1 free promise and Pro scope; D4 animation format.
- Per-photo "Convert and save" for Live Photos needs a receiver capability.
- The Pixel download page address (first run step 2).

## Known gaps

- Smart Storage's age rule (capture or backup time) is unverified on device.
- Motion has been checked in the Simulator only; device recordings are pending.
- Pixel large text is untested on the device.
- Real pairing between a Pixel and the Mac connect sheet is untested.
