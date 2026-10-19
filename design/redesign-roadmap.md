# Redesign roadmap

The single place that says where the BackupDuck redesign stands and what comes
next. Any agent resuming the work starts here: read "Current step", do it, mark
it, commit, continue. Update this file in the same change as any milestone,
decision or page status. Page detail lives in `page-register.md`; rules live in
`constitution.md`, `visual-language.md` and `interaction.md`.

Last updated: October 19, 2026.

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
| 3a | iPhone pages on the components, by flow: hub, photos views and photo info, first run, problems, settings (including the newly designed Devices, album chooser, Help) | Each flow's catalog scenarios pass review criteria in `iteration-checklist.md`; iOS tests pass | Hub, Devices, Help and the viewer's backup facts done; album chooser restyle, Live Activity and notifications remain |
| 3b | Pixel pages: receive hub, received photos and detail, first run, connect, devices, settings, the newly designed Storage page | Android unit tests, catalog and debug builds pass; Pixel XL screenshots checked | Done (catalog on the Pixel XL in light, dark, large text, Chinese); filter chips on received photos deferred |
| 3c | Mac pages: overview, library views and marks, history, settings list and detail, connect, viewer window, menu bar | Mac catalog checked in light and dark | Overview, Settings with Devices and Help, connect and the viewer's facts done; history snapshot in the catalog does not render (investigate) |
| 3d | Core data for new pages: a "saving to Photos" tile state, Pixel storage breakdown, device page counts | `cargo test` and `cargo fmt --check` pass; hosts read the new fields | `source_job` done; saving state on tiles and Pixel storage breakdown remain |
| 4 | Remaining pages from the standards: Mac first run and Folders, notifications, Live Activity, Pixel experiments, help articles | Catalog scenarios for each | Not started |
| 5 | Verification pass: light, dark, largest text, long localized copy, failure and recovery on every flow; Release-build motion recordings on iPhone and Pixel XL | Findings fixed or recorded under Known gaps | Not started |
| 6 | Make the redesign the default: the design switch defaults on, legacy pages and remnants removed, `page-register.md` all redesigned, HTML prototypes retired | All checks pass on all three platforms | Default on in all three apps (0252a3f, fa9c23f); legacy removal remains |

## Current step

Step 6 is in effect on all three apps (the redesigned pages are the default).
Remaining: remove the earlier pages and the catalog's comparison switch, then
steps 4 and 5 (remaining pages from the standards; verification pass with
Release motion recordings on device). Publishing waits for the owner.

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
