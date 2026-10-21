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
| 3a | iPhone pages on the components, by flow: hub, photos views and photo info, first run, problems, settings (including the newly designed Devices, album chooser, Help) | Each flow's catalog scenarios pass review criteria in `iteration-checklist.md`; iOS tests pass | Hub, Devices, Help and A8 viewer implemented; notifications and Live Activity implemented with system acceptance remaining. Chooser remnants and first-run continuation remain |
| 3b | Pixel pages: receive hub, received photos and detail, first run, connect, devices, settings, the newly designed Storage page | Android unit tests, catalog and debug builds pass; native catalog checked | Pages implemented, received-original previews and problem thumbnails added; native acceptance and register blockers remain |
| 3c | Mac pages: overview, library views and marks, history, settings list and detail, connect, viewer window, menu bar | Mac catalog checked in light and dark | Overview, Settings with Devices and Help, connect, library marks, A8 viewer, Folders and menu bar implemented; native acceptance and register blockers remain |
| 3d | Core data for new pages: a "saving to Photos" tile state, Pixel storage breakdown, device page counts | `cargo test` and `cargo fmt --check` pass; hosts read the new fields | `source_job`, saving marks, storage/folder facts, confirmed history publication and bounded received-original previews implemented (`c8f4af3`, `c9363d6`, `e87c8f8`, `524c626`) |
| 4 | Remaining pages from the standards: Mac first run and Folders, notifications, Live Activity, Pixel experiments, help articles | Catalog scenarios for each | Folders, notifications, Live Activity and Apple help implemented; no dedicated Mac first-run wizard. Pixel experiments, help and other register remnants remain |
| 5 | Verification pass: light, dark, largest text, long localized copy, failure and recovery on every flow; Release-build motion recordings on iPhone and Pixel XL | Findings fixed or recorded under Known gaps | Not started |
| 6 | Make the redesign the default: the design switch defaults on, legacy pages and remnants removed, `page-register.md` all redesigned, HTML prototypes retired | All checks pass on all three platforms | Default on in all three apps (0252a3f, fa9c23f); legacy removal remains |

## Current step

Step 6 is in effect on all three apps (the redesigned pages are the default).

October 21, 2026: the owner approved `platform-expression.md` (which native
container and control expresses each task; chrome is the system's, content is
BackupDuck's) and the Mac Folders structure (`mac-folders.md`).

Implementation status:

1. **Platform audit — done.** System chrome/component corrections landed in
   `82a460f`; Pixel secondary destinations use native navigation (`f47e726`),
   and Apple library controls use public API (`524c626`). Remaining contract
   deviations and native acceptance blockers are recorded in `page-register.md`;
   this milestone does not claim that every reachable surface passes A0–A11.
2. **Mac Folders and Apple photo information (A8) — done.** The native Folders
   browser, core facts, Settings, sheets, alert and synthetic catalog landed in
   `27765f7`. Apple library/history viewer routing, shared information layout,
   Mac inspector and missing-local fallback landed in `786f879`. Native visual
   and device acceptance remain open. The Folders inspector still needs the
   shared receipt/publication layout, as recorded in `page-register.md`.
3. **Notifications and Live Activity — implemented; system acceptance remains.**
   iPhone notifications, the widget target, system Live Activity presentations
   and pause/resume intents landed in `27765f7`; confirmed historical publication
   landed in `c9363d6`. Pixel notification routing landed in `c8f4af3`. Verify
   system delivery, cold/warm taps, activity creation, intents, stale content,
   dismissal and restart. The register also records the iPhone first-run gate
   and Mac notification permission/tap integration gaps.
4. **Mac menu bar — done (`bec2e13`).** Native status menu, shared status
   projection and synthetic catalog scenarios are implemented. Native system
   menu and action acceptance remains part of Release verification.

Next, in order:

5. **Remaining remnants.** Redesign album/media choosers and selected-photo
   review/confirmation surfaces, Pixel help, Pixel Advanced remnants (format
   conversion and browser management), and Mac update controls. Include Pixel
   update controls and the reachable cleanup, recovery and compatibility routes
   listed in `page-register.md`; preserve intentionally technical diagnostics.
   Resolve the register's routing and contract blockers alongside these flows.
6. **Photo-library chrome comparison — owner decision pending.** Compare the
   current native compositions and record the decision before changing chrome.
7. **Pixel experiments page redesign — owner decision pending.** Define and
   approve the ordinary-user structure before rebuilding the overview and
   automatic-cleanup descendants.
8. **Release verification.** Check light/dark, narrow layouts, largest text,
   long localized content, failure and recovery. Complete system notification
   and Live Activity acceptance, real pairing and Release gesture/motion
   recordings under `iteration-checklist.md`. Builds and catalog scenarios do
   not replace native or physical-device observations.
9. **Legacy removal.** After review of the production redesign and acceptance,
   remove superseded pages and the catalog comparison switch. Resolve supported
   compatibility routes explicitly; file presence alone is not reachability.

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
