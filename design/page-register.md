# Page register

The overall plan and phase status are in `redesign-roadmap.md`.

Which pages are redesigned for ordinary users and which are still legacy
(`constitution.md` § Redesign before refinement). Update this file in the same
change that redesigns a page, removes a remnant or adds a page.

- **Redesigned**: went through the four steps and its structure, flow and copy
  were approved in review. Its look is approved separately through the visual
  language (`visual-language.md`); until then no page is final.
- **Legacy**: the earlier app's page. Defect fixes only; anything else starts
  with a redesign.
- **Remnant**: a legacy page or component that a redesigned page opens or
  embeds. It blocks migration of that page until it is redesigned.

Current inventory: October 22, 2026, covering production entry points at
`786f879` plus the Mac menu-bar update in `bec2e13`. Redesigned pages are the
production default on all three platforms, but still open reachable remnants. Rebuilt pages that
follow an approved contract count as Redesigned; system chrome corrections
alone do not establish a page redesign. This status does not establish native
or physical-device acceptance. The last column records remaining implementation,
contract and acceptance blockers; “—” means no additional structural blocker was
identified, not that every verification check passed.

Diagnostics remain intentionally technical. Their log, detail and export
surfaces do not require an ordinary-user redesign under the diagnostics
exemption. Compatibility routes and technical exports are listed explicitly;
unused files and catalog-only legacy comparisons are not production pages.

## iPhone sender

| Page | Platform | State | Contract | Remaining blocker |
| --- | --- | --- | --- | --- |
| Root navigation | iPhone | Redesigned | `navigation.md`; `platform-expression.md` A3 | Reachable remnants below still block migration completion. |
| Opening / initialization failure | iPhone | Redesigned | `platform-expression.md` A10 | — |
| First run: Welcome; Install on Pixel | iPhone | Redesigned | `flows.md` First run | Post-pairing continuation is bypassed by the root gate. |
| First run: Connected; Photos permission; What to back up; first photo and notification invitation | iPhone | Redesigned | `flows.md` First run | Pairing makes the root leave onboarding before these steps finish. The first-photo wait also lacks an exit/recovery action. This is a source routing finding, not a device observation. |
| Connect / reconnect, including camera and scan failures | iPhone | Redesigned | `flows.md`; `platform-expression.md` A4 | Onboarding continuation above; standalone connect remains reachable. Native pairing/recovery acceptance remains. |
| Photos: Years / Months / All, backup views and empty/access/error states | iPhone | Redesigned | `library.md`; `iphone-calendar-grid.md`; `interaction.md` I6 | Release gesture/continuity acceptance; selection-review and confirmation remnants below. Saving marks use the current shared projection (`524c626`). |
| Selected-photo review sheet and selected-photo viewer | iPhone | Legacy | `ui-content-rules.md` Media selection cells; target: A0 | Fresh structure approval is missing; the review sheet still sets its own corner radius. |
| Photo viewer and in-view information panel | iPhone | Redesigned | `platform-expression.md` A8 (`786f879`) | Native paging, information gestures, zoom ownership and return-anchor acceptance. |
| Recorded photo-information fallback | iPhone | Redesigned | `platform-expression.md` A8 (`786f879`) | Native unavailable-source and retry acceptance. The contract permits this fallback. |
| Backup hub, problems and earlier-photo summary | iPhone | Redesigned | `flows.md`; `interaction.md` I2 | Shared connect/viewer acceptance. This path needs no separate production History grid. |
| Connection-help sheet | iPhone | Redesigned | `flows.md`; `platform-expression.md` A7 | — |
| Back Up Selected confirmation | iPhone | Remnant | `ui-content-rules.md` Submission; A4 | Native chrome is corrected; fresh structure approval remains missing. |
| Settings root | iPhone | Redesigned | `settings.md`; `interaction.md` I2 | Scope-editor remnants remain reachable. |
| Auto Backup, including notification permission entry | iPhone | Redesigned | `settings.md`; `apple-notifications.md` | Scope-editor remnants; permission/system acceptance. |
| Media Types editor | iPhone | Remnant | `platform-expression.md` A6; `ui-content-rules.md` Photo backup scope | Chrome/token work does not establish a new structure review. |
| Specified Albums chooser | iPhone | Remnant | `platform-expression.md` A6; `ui-content-rules.md` Photo backup scope | Still thumbnail list rows rather than the documented three-column cover chooser; structure and continuity review remain. |
| Read-only album browser | iPhone | Remnant | `ui-content-rules.md` Photo backup scope | Parent chooser migration and native return/search/selection continuity acceptance. |
| Appearance picker/detail | iPhone | Redesigned | `settings.md`; `platform-expression.md` A0 | — |
| Language entry | iPhone | Redesigned | `settings.md` | — |
| About | iPhone | Redesigned | `settings.md` | — |
| Advanced: temporary files and thumbnails | iPhone | Redesigned | `settings.md`; `feature-triage.md` | — |
| Devices / current Pixel | iPhone | Redesigned | `navigation.md` D3; `interaction.md` I2 | — |
| Rename device sheet and discard confirmation | iPhone | Redesigned | `platform-expression.md` A4/A5 (`82a460f`) | Native fitted-height, dirty-dismissal and save-failure acceptance. |
| Help Center | iPhone | Redesigned | `interaction.md` I2/I8; `platform-expression.md` A7 | — |
| Help articles by task and problem | iPhone | Redesigned | `interaction.md` I2/I8 | Native long-content/localization acceptance. |
| Diagnostics log and immutable entry detail | iPhone | Legacy (intentionally technical) | Diagnostics exemption; `ui-content-rules.md` | No ordinary-page redesign required. |
| Diagnostics export / system share sheet | iPhone | Legacy (intentionally technical) | Diagnostics exemption; `ui-content-rules.md` Submission | Native export/error/share acceptance. |
| Backup notifications | iPhone | Redesigned | `apple-notifications.md`; `flows.md` Every day (`27765f7`, `c9363d6`) | System delivery, cold-start and tap acceptance; first-run invitation has the onboarding gate blocker above. |
| Lock Screen / Dynamic Island Live Activity, pause/resume/Open | iPhone | Redesigned | `apple-live-activity.md`; `flows.md` Every day (`27765f7`) | Widget implementation exists; system creation, intents, stale content, dismissal/restart and physical-device acceptance remain. |

## Mac sender

| Page | Platform | State | Contract | Remaining blocker |
| --- | --- | --- | --- | --- |
| Root navigation | Mac | Redesigned | `navigation.md`; `platform-expression.md` A3 | Reachable remnants below still block migration completion. |
| Overview, including unpaired launch | Mac | Redesigned | `flows.md`; `interaction.md` I2 | History remains a separate grid; recent mosaic is not wired to a viewer. There is no dedicated Mac first-run wizard. |
| Connection-help sheet | Mac | Redesigned | `flows.md`; `platform-expression.md` A7 | — |
| Photo Library: periods, filters, backup views, selection and placeholders | Mac | Redesigned | `library.md`; `macos-v1.2/specification.md` Photos Library | Release/native library acceptance; separate History grid conflicts with the one-grid direction. Saving marks use the current shared projection (`524c626`). |
| Backup History grid and grouped problems | Mac | Redesigned | `records.md`; `platform-expression.md` A8 (`786f879`) | Resolve the conflict with `library.md`'s one-grid direction. The requested attention filter is stored but not passed to the History view. |
| Connect Pixel: code, preparing, failure and success | Mac | Redesigned | `mac-connect.md` | Real pairing/native acceptance. Production uses the redesigned connect sheet. |
| Photo viewer window, inspector and missing-local fallback | Mac | Redesigned | `platform-expression.md` A8 (`786f879`) | Native window, inspector, keyboard and collection-continuity acceptance. |
| Folders browser: By Folder / All Photos, filters, search and selection | Mac | Redesigned | `mac-folders.md` (`27765f7`) | Native/device acceptance. Back Up Selected appears for any selection rather than only eligible unsaved photos. |
| Unsupported-files explanation popover | Mac | Redesigned | `mac-folders.md`; `platform-expression.md` A7 (`27765f7`) | Native unsupported-kind content and Finder-action acceptance. |
| Add Folder: system chooser and existing/new-photo decision | Mac | Redesigned | `mac-folders.md` Adding a folder (`27765f7`) | External-drive, cancellation, counting and submission-failure acceptance. |
| Settings → Folders list and individual folder settings | Mac | Redesigned | `mac-folders.md` Settings › Folders (`27765f7`) | Native navigation/recovery acceptance. |
| File Rules sheet | Mac | Redesigned | `mac-folders.md` File Rules (`27765f7`) | Native token-field editing, validation and cancellation acceptance. |
| Stop Backing Up Folder alert | Mac | Redesigned | `mac-folders.md`; `platform-expression.md` A5 (`27765f7`) | Native stop/failure/recovery acceptance. |
| Folder photo viewer and inspector | Mac | Redesigned | `mac-folders.md`; `platform-expression.md` A8 (`27765f7`) | Still a separate information implementation with one backup-state sentence and optional saved time. It must adopt the shared receipt/publication layout; A8 is not complete across all Mac viewers. |
| Back Up Selected confirmation (Photo Library) | Mac | Remnant | `ui-content-rules.md` Submission; A4 | Fresh structure approval remains missing; the persistent repeat-send choice is a checkbox rather than a switch row. |
| Settings root | Mac | Redesigned | `settings.md`; `interaction.md` I2 | Scope editors and update controls remain reachable remnants. |
| Auto Backup | Mac | Redesigned | `settings.md`; `apple-notifications.md` | Scope-editor remnants; notification permission entry is absent. |
| Media Types editor | Mac | Remnant | `platform-expression.md` A6; `ui-content-rules.md` Photo backup scope | Existing editor received chrome/token work; fresh structure review remains. |
| Specified Albums chooser | Mac | Remnant | `platform-expression.md` A6; `ui-content-rules.md` Photo backup scope | Fresh structure review; read-only album browsing is not wired because the current sheet omits the mutable opened-album binding. |
| Appearance detail | Mac | Redesigned | `settings.md`; `platform-expression.md` A0 | — |
| Language entry | Mac | Redesigned | `settings.md` | — |
| About | Mac | Redesigned | `settings.md` | Application-menu About changes workspace destination/title without selecting the About detail; it can show another settings detail. Update controls remain a remnant. |
| Update controls and updater windows | Mac | Remnant | `settings.md` | Nested form/preference-group composition lacks fresh redesign approval. Store builds show the store-update note instead. |
| Advanced: temporary files and thumbnails | Mac | Redesigned | `settings.md`; `feature-triage.md` | — |
| Devices / current Pixel | Mac | Redesigned | `navigation.md` D3; `interaction.md` I2 | — |
| Rename device sheet and discard confirmation | Mac | Redesigned | `platform-expression.md` A4/A5 (`82a460f`) | Native fitted-height, dirty-dismissal and save-failure acceptance. |
| Help Center | Mac | Redesigned | `interaction.md` I2/I8; `platform-expression.md` A7 | — |
| Help articles by task and problem | Mac | Redesigned | `interaction.md` I2/I8 | Native long-content/localization acceptance. |
| Diagnostics log and immutable entry detail | Mac | Legacy (intentionally technical) | Diagnostics exemption; `ui-content-rules.md` | No ordinary-page redesign required. |
| Diagnostics export / system share sheet | Mac | Legacy (intentionally technical) | Diagnostics exemption; `ui-content-rules.md` Submission | Native export/error/share acceptance. |
| Menu-bar icon and status menu | Mac | Redesigned | `interaction.md` I1/I3; `platform-expression.md` A0 (`bec2e13`) | Implementation is committed; native menu, state and action acceptance remains. |
| Backup notifications | Mac | Redesigned | `apple-notifications.md` (`27765f7`) | Shared notifier is implemented, but Mac has no notification-route consumer or explicit permission entry. Destination integration and system acceptance remain. |

## Pixel receiver

| Page | Platform | State | Contract | Remaining blocker |
| --- | --- | --- | --- | --- |
| Root navigation | Pixel | Redesigned | `navigation.md`; `platform-expression.md` A3 | Reachable remnants below still block migration completion. |
| First run: Welcome, Keep Running, photo-service setup and Free Space | Pixel | Redesigned | `flows.md` First run | Free Space opens legacy Experiments; permission/external-app return acceptance remains. |
| Receive hub and recent-photo mosaic | Pixel | Redesigned | `flows.md`; `interaction.md` I2 | Auto-cleanup and problem-help remnants remain. Recent photos use a mosaic and open the viewer. |
| Received Photos timeline and problem cards | Pixel | Redesigned | `records.md` (`58e31f2`, `47ff0d2`) | Native preview loading/unavailability acceptance; latest-change ordering across pages remains a contract gap. Problem thumbnails now have bounded core preview support. |
| Live Photo cause / affected-photos sheet | Pixel | Redesigned | `records.md`; `platform-expression.md` A7 | Native large-group, scroll and detail-return acceptance. |
| Photo viewer and bottom information panel | Pixel | Redesigned | `records.md`; `platform-expression.md` A8 | Drawn close button still violates A0; the per-photo cloud disclaimer contradicts the single-footer decision. Native preview acceptance remains. |
| Connect: iPhone code, Mac direction, failure and success | Pixel | Redesigned | `pixel-connect.md` (`f47e726`) | Native back, recreation, scanner-return and real-pairing acceptance. Uses a pushed production destination. |
| Mac-code camera scanner | Pixel | Redesigned | `pixel-connect.md` | Native camera denial, cancellation and return acceptance. |
| Connected Devices list | Pixel | Redesigned | `pixel-connect.md` (`f47e726`) | Native restore/back and stopped-device acceptance. |
| Individual device sheet | Pixel | Redesigned | `pixel-connect.md`; `platform-expression.md` A7/A11 | Native stop/resume failure acceptance. |
| Stop receiving from device confirmation and Undo snackbar | Pixel | Redesigned | `platform-expression.md` A5/A9 (`82a460f`) | Native confirmation, failure and Undo acceptance. |
| Settings root | Pixel | Redesigned | `settings.md` | Experiments, Help, Updates and Advanced descendants contain legacy structures. |
| Appearance and Language dialogs | Pixel | Redesigned | `settings.md`; `platform-expression.md` A0 (`82a460f`) | Native theme/locale recreation acceptance. These are dialogs, not standalone pages. |
| Rename Pixel dialog | Pixel | Redesigned | `platform-expression.md` A4 (`82a460f`) | Native validation, keyboard and failed-save acceptance. |
| Storage | Pixel | Redesigned | `flows.md` How the Pixel keeps space free (`c8f4af3`, `0f22b9b`, `f47e726`) | Enabling cleanup opens legacy Experiments; native unknown/read-failure/control acceptance remains. This is separate from the compatibility storage routes below. |
| Advanced | Pixel | Redesigned | `settings.md`; `feature-triage.md` (`f47e726`) | Format Conversion and Browser Management remain remnants. |
| Format Conversion sheet | Pixel | Remnant | `feature-triage.md` | Old explanation/switch structure lacks fresh redesign review. |
| Stop Receiving confirmation | Pixel | Redesigned | `platform-expression.md` A5 (`82a460f`) | Native stop/failure/result acceptance. |
| Browser Management | Pixel | Remnant | `android-v1.2/specification.md` | Existing enable/access/code/revoke/startup structure needs redesign; system chrome corrections alone do not establish approval. |
| Browser address/access-code sheet | Pixel | Remnant | `android-v1.2/specification.md`; target: A7 | Old access/startup/copy structure needs ordinary-user review. |
| Browser code editor, random-reset and revoke-logins confirmations | Pixel | Remnant | `platform-expression.md` A4/A5 | Native dialog chrome is rebuilt; parent browser-flow redesign remains. |
| Check for Updates: checking, available, download, failure and installation handoff | Pixel | Remnant | `settings.md` | Existing version/switch/actions structure lacks fresh redesign approval. |
| Help index and Connection, Background, Results, Storage, Recovery articles | Pixel | Remnant | Target: `settings.md`; `interaction.md` I2/I8 | Existing five-topic help structure remains reachable from Settings and hub recovery. Presentation changes did not redesign its information architecture. |
| Experiments overview | Pixel | Remnant | Target: `settings.md`; `flows.md` | Dedicated redesign contract and owner decision pending. Reachable from Settings, Storage and first run. |
| Automatic Cleanup setup/overview | Pixel | Remnant | `flows.md` Free space automatically | Existing permission/account/automation/troubleshooting structure needs redesign. |
| Account-binding and Cleanup progress/result pages | Pixel | Legacy | `ui-content-rules.md` External operations | Fresh structure review and native external-app return/recovery acceptance. |
| Photo-service diagnostics/probe page | Pixel | Legacy (intentionally technical) | Diagnostics exemption | Keep technical purpose explicit; this does not establish ordinary cleanup-page redesign. |
| Photo-service diagnostics export | Pixel | Legacy (intentionally technical) | Diagnostics exemption; `ui-content-rules.md` Submission | Native interrupted-export/retry acceptance; navigation is rebuilt (`f47e726`). |
| Cleanup/probe consent dialogs and Reviewed confirmation | Pixel | Legacy | `ui-content-rules.md` Application consent; `platform-expression.md` A5 | Material chrome is rebuilt; consent remains embedded in the legacy cleanup workflow. |
| Waking/unlocking transient screen | Pixel | Legacy | Target: `flows.md`; `ui-content-rules.md` External operations | Standalone text with literal typography/padding lacks a page contract and review. |
| Diagnostics log-report and gallery-receipts report exports | Pixel | Legacy (intentionally technical) | Diagnostics exemption; `ui-content-rules.md` Submission | Settings footer opens the log report directly. Gallery report also has a supported Intent route; native export acceptance remains. |
| Diagnostics index / Records and Exports | Pixel | Legacy (intentionally technical) | Diagnostics exemption | Supported `surface=diagnostics` Intent only; no current Settings/footer entry. Decide whether to retain or retire the route. |
| Storage limits, log retention and legacy retention/scope sheet | Pixel | Legacy (technical compatibility routes) | `feature-triage.md`; diagnostics exemption for log retention | Supported storage-limits/retention Intents and diagnostics routes remain. Retain or retire the old settings/scope structure explicitly; this is not redesigned Storage. |
| Original archive explanation and export/verification task page | Pixel | Legacy (technical export) | `ui-content-rules.md` Submission | Reachable through diagnostics and `surface=archive`. Explicitly retain as technical export or redesign; native confirmation/task/return acceptance remains. |
| Verified archive result and reclaim-originals confirmation/result | Pixel | Legacy (technical export) | `platform-expression.md` A5; `ui-content-rules.md` Submission | Old result/second-confirmation flow lacks fresh structure approval. |
| Operation-failed / Retry sheet | Pixel | Legacy | Target: `platform-expression.md` A7/A9/A10 | Generic modal error wrapper needs task-specific in-place or explanatory recovery review. |
| Ongoing receiver notification and stopped/restart reminder | Pixel | Redesigned | `ui-content-rules.md` System notifications (`c8f4af3`) | Actual system rendering and Receive/Needs you/Storage cold/warm tap acceptance. |
