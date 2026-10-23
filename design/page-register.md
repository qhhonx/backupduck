# Page register

The overall plan and phase status are in `redesign-roadmap.md`.

Which pages are redesigned for ordinary users and which are still legacy
(`constitution.md` § Redesign before refinement). Update this file in the same
change that redesigns a page, removes a remnant or adds a page.

- **Redesigned**: went through the four steps and its structure, flow and copy
  were approved in review. Its look is approved separately through the visual
  language (`visual-language.md`); until then no page is final. A retired surface
  replaced by the approved contract also counts as Redesigned.
- **Partially redesigned**: the approved structure is implemented in part, with
  a concrete flow, routing or content gap still open.
- **Legacy**: the earlier app's page. Defect fixes only; anything else starts
  with a redesign.
- **Remnant**: a legacy page or component that a redesigned page opens or
  embeds. It blocks migration of that page until it is redesigned.

Current inventory: October 23, 2026, through the legacy removal (`2413496`,
`894ccd5`). Redesigned pages are the only pages on all three platforms: the
superseded pages, the separate Mac Settings window and the catalog design
switch are removed, and old links and restored pages open the current pages.
Rebuilt pages that follow an approved contract count as Redesigned; system chrome corrections
alone do not establish a page redesign. This status does not establish native
or physical-device acceptance. The last column notes changes and remaining
implementation, contract and acceptance blockers; “—” means no additional structural blocker was
identified, not that every verification check passed.

Technical pages (diagnostics logs, entry details, exports, compatibility and
archive routes) are redesigned too, for their audience: someone troubleshooting
or helping a person troubleshoot. They keep exact technical detail, but get the
same structure, components, copy rules and visual standard as every other page.
"Technical" names the audience, not an exemption. Unused files and catalog-only
legacy comparisons are not production pages.

## iPhone sender

| Page | Platform | State | Contract | Change / remaining blocker |
| --- | --- | --- | --- | --- |
| Root navigation | iPhone | Redesigned | `navigation.md`; `platform-expression.md` A3 | Old roots and the Receiver tab removed (`894ccd5`); the iPad fallback page is kept. |
| Opening / initialization failure | iPhone | Redesigned | `platform-expression.md` A10 | — |
| First run: Welcome; Install on Pixel | iPhone | Redesigned | `flows.md` First run | The flow is retained until durable completion (`e325845`). Native permission and real-pairing acceptance remain. |
| First run: Connected; Photos permission; What to back up; first photo and notification invitation | iPhone | Redesigned | `flows.md` First run | Continuation after pairing, and exit/recovery from the first-photo wait (`e325845`). Physical first-photo and notification acceptance remain. |
| Connect / reconnect, including camera and scan failures | iPhone | Redesigned | `flows.md`; `platform-expression.md` A4 | Onboarding continuation above; standalone connect remains reachable. Native pairing/recovery acceptance remains. |
| Photos: Years / Months / All, backup views and empty/access/error states | iPhone | Redesigned | `library.md`; `iphone-calendar-grid.md`; `interaction.md` I6 | D1 adopted: tile flight and full-aspect system long-press preview (`4517cd5`); ordinary selected backup registers directly (`2f00d25`). Release gesture, anchor and selection continuity remain. |
| Selected-photo review sheet and selected-photo viewer | iPhone | Redesigned | `library.md`; `platform-expression.md` A0 | System sheet with live count, frozen membership, browse-selected button and system toolbar (`e3a6400`). Physical and motion acceptance remain. |
| Photo viewer and in-view information panel | iPhone | Redesigned | `platform-expression.md` A8 (`4517cd5`) | System-composed date/time, More, Share and Info; state mark on Info, Back Up/Retry and conditional History in the panel. Release paging, panel reversal, zoom and return-anchor acceptance remain. |
| Recorded photo-information fallback | iPhone | Redesigned | `platform-expression.md` A8 (`4517cd5`) | Shares the adopted viewer/information layout; native unavailable-source and Retry acceptance remain. |
| Backup hub, problems and earlier-photo summary | iPhone | Redesigned | `flows.md`; `interaction.md` I2 | Shared connect/viewer acceptance. This path needs no separate production History grid. |
| Connection-help sheet | iPhone | Redesigned | `flows.md`; `platform-expression.md` A7 | — |
| Back Up Selected confirmation | iPhone | Redesigned | `ui-content-rules.md` Submission (`2f00d25`) | General confirmation retired; direct registration with repeat-only confirmation and registration-failed alert. Native repeat/cancel/failure and selection preservation remain. |
| Settings root | iPhone | Redesigned | `settings.md`; `interaction.md` I2 | Help/feedback, version-valued About and Diagnostics · Advanced bottom rebuilt; reserved content stays hidden (`d9f2323`, `544f1ed`). Album-contract reconciliation and native scope continuity remain. |
| Auto Backup, including notification permission entry | iPhone | Redesigned | `settings.md`; `apple-notifications.md` | Scope editors rebuilt (`49efc3e`, `2f00d25`); album-contract reconciliation and permission/system acceptance remain. |
| Media Types editor | iPhone | Redesigned | `platform-expression.md` A6; `ui-content-rules.md` Photo backup scope | Fixed aligned checklist with immediate saves under revised A6 (`49efc3e`, `2f00d25`); native persistence/accessibility acceptance remains. |
| Specified Albums chooser | iPhone | Redesigned | `platform-expression.md` A6; `ui-content-rules.md` Photo backup scope | Searched system list with covers, summary and immediate choices (`49efc3e`, `2f00d25`); reconcile stale three-column content rule and verify continuity. |
| Read-only album browser | iPhone | Redesigned | `ui-content-rules.md` Photo backup scope | Reachable from the rebuilt chooser context menu (`49efc3e`); native return/search/selection continuity remains. |
| Appearance picker/detail | iPhone | Redesigned | `settings.md`; `platform-expression.md` A0 | — |
| Language entry | iPhone | Redesigned | `settings.md` | — |
| About | iPhone | Redesigned | `settings.md` | Version, privacy, licenses and website rebuilt; author content hidden while absent (`d9f2323`, `544f1ed`). Native reading/external-return acceptance remains. |
| Advanced: temporary files and thumbnails | iPhone | Redesigned | `settings.md`; `feature-triage.md` | — |
| Devices / current Pixel | iPhone | Redesigned | `navigation.md` D3; `interaction.md` I2 | — |
| Rename device sheet and discard confirmation | iPhone | Redesigned | `platform-expression.md` A4/A5 (`82a460f`) | Native fitted-height, dirty-dismissal and save-failure acceptance. |
| Help Center | iPhone | Redesigned | `interaction.md` I2/I8; `platform-expression.md` A7 | — |
| Help articles by task and problem | iPhone | Redesigned | `interaction.md` I2/I8 | Native long-content/localization acceptance. |
| Diagnostics: export and recent activity | iPhone | Redesigned | `settings.md` Diagnostics (`a70cf0b`, `222c950`) | The log/detail/retention pages are retired. Native share-sheet acceptance remains. |
| Backup notifications | iPhone | Redesigned | `apple-notifications.md`; `flows.md` Every day (`27765f7`, `c9363d6`, `e325845`) | The first-run invitation follows durable onboarding completion. System delivery, cold-start and tap acceptance remain. |
| Lock Screen / Dynamic Island Live Activity, pause/resume/Open | iPhone | Redesigned | `apple-live-activity.md`; `flows.md` Every day (`27765f7`) | Ring glyph rules updated (`2f00d25`); system creation, intents, stale content, dismissal/restart and physical-device acceptance remain. |
| Open source & licenses, bundled-license reader | iPhone | Redesigned | `settings.md` (`d9f2323`, `544f1ed`) | Native long-content/localization and external-link acceptance remain. |
| Send Feedback → external user group | iPhone | Redesigned | `settings.md` (`d9f2323`, `544f1ed`) | Group handoff is available; absent email and rating stay hidden. Native external-return acceptance remains. |
| Photo context menu, single-photo Back Up and History sheets | iPhone | Partially redesigned | `platform-expression.md` A8/A11 (`4517cd5`) | System menu adopted; standalone History facts sheet still needs one-information-layout review and native flow acceptance. |
| Photo sharing / system activity sheet | iPhone | Redesigned | `ui-content-rules.md` Sender media browsing (`4517cd5`) | Native original-preparation, failure, cancellation and share-popover acceptance remain. |
| Viewer → History modal grid | iPhone | Partially redesigned | `library.md`; `platform-expression.md` A8 (`4517cd5`) | Conditional History targets the recorded item; reconcile separate modal grid with one-grid direction and verify return continuity. |

## Mac sender

| Page | Platform | State | Contract | Change / remaining blocker |
| --- | --- | --- | --- | --- |
| Root navigation | Mac | Redesigned | `navigation.md`; `platform-expression.md` A3 | Reachable remnants below still block migration completion. |
| Overview, including unpaired launch | Mac | Redesigned | `flows.md`; `interaction.md` I2 | Needs you routes to the requested records and the recent mosaic opens the shared viewer (`e325845`, `c49dc06`); the old overview is removed (`894ccd5`). Native acceptance remains. |
| Connection-help sheet | Mac | Redesigned | `flows.md`; `platform-expression.md` A7 | — |
| Photo Library: periods, filters, backup views, selection and placeholders | Mac | Redesigned | `library.md`; `macos-v1.2/specification.md` Photos Library | D1 adopted with system title/subtitle and trailing zoom, period, aspect/filter capsules (`caf910e`, `96748d3`); Release continuity and separate-History contract gap remain. |
| Backup History grid and grouped problems | Mac | Redesigned | `records.md`; `platform-expression.md` A8 (`786f879`, `c49dc06`) | Shared in-window viewer; Needs you filter passed from Overview; the old transfer list is removed (`894ccd5`). Native acceptance remains. |
| Connect Pixel: code, preparing, failure and success | Mac | Redesigned | `mac-connect.md` | Real pairing/native acceptance. Production uses the redesigned connect sheet. |
| Photo viewer, inspector and missing-local fallback | Mac | Redesigned | `platform-expression.md` A8 (`caf910e`) | D1 adopted: in-window date/time/position, Share and Info state mark; ⌘I opens shared facts and Back Up/Retry. Native keyboard, inspector, fallback and collection continuity remain. |
| Folders browser: By Folder / All Photos, filters, search and selection | Mac | Redesigned | `mac-folders.md` (`96748d3`) | System title/subtitle, adaptive view/action capsules and expandable search; eligible-only backup (`2f00d25`). Native search/viewer-return and device acceptance remain. |
| Unsupported-files explanation popover | Mac | Redesigned | `mac-folders.md`; `platform-expression.md` A7 (`27765f7`) | Native unsupported-kind content and Finder-action acceptance. |
| Add Folder: system chooser and existing/new-photo decision | Mac | Redesigned | `mac-folders.md` Adding a folder (`27765f7`) | Durable registration returns before execution (`2f00d25`); external-drive, cancellation, counting and submission-failure acceptance remain. |
| Settings → Folders list and individual folder settings | Mac | Redesigned | `mac-folders.md` Settings › Folders (`27765f7`) | Native navigation/recovery acceptance. |
| File Rules sheet | Mac | Redesigned | `mac-folders.md` File Rules (`27765f7`) | Native token-field editing, validation and cancellation acceptance. |
| Stop Backing Up Folder alert | Mac | Redesigned | `mac-folders.md`; `platform-expression.md` A5 (`27765f7`) | Native stop/failure/recovery acceptance. |
| Folder photo viewer and inspector | Mac | Redesigned | `mac-folders.md`; `platform-expression.md` A8 (`caf910e`) | Shared in-window viewer and receipt/publication layout replace the single state sentence; native facts, actions, keyboard and return continuity remain. |
| Back Up Selected confirmation (Photo Library) | Mac | Redesigned | `ui-content-rules.md` Submission (`2f00d25`) | General confirmation and persistent checkbox retired; repeat-only confirmation and failure alert remain. Native repeat/cancel/failure acceptance remains. |
| Settings root | Mac | Redesigned | `settings.md`; `interaction.md` I2 | Settings lives only in the main window: the separate Settings window is removed and the menu item and ⌘, open it from an open, minimized or closed window (`894ccd5`). Native descendant acceptance remains. |
| Auto Backup | Mac | Redesigned | `settings.md`; `apple-notifications.md` | Scope editors (`49efc3e`, `2f00d25`) and explicit notification permission entry (`e325845`). System permission/tap acceptance remains. |
| Media Types editor | Mac | Redesigned | `platform-expression.md` A6; `ui-content-rules.md` Photo backup scope | Fixed aligned checklist with immediate saves under revised A6 (`49efc3e`, `2f00d25`); native editing acceptance remains. |
| Specified Albums chooser | Mac | Redesigned | `platform-expression.md` A6; `ui-content-rules.md` Photo backup scope | Searched list with covers, immediate saves and bound read-only browsing (`49efc3e`, `2f00d25`); native search/return/selection continuity remains. |
| Appearance detail | Mac | Redesigned | `settings.md`; `platform-expression.md` A0 | — |
| Language entry | Mac | Redesigned | `settings.md` | — |
| About | Mac | Redesigned | `settings.md` | Application-menu routing fixed (`49efc3e`); version/update status, privacy, licenses and website rebuilt, absent author content hidden (`d9f2323`, `544f1ed`). Native menu-route acceptance remains. |
| Update controls and updater windows | Mac | Redesigned | `settings.md` | About Version opens status/check/automatic-switch detail; store build shows version only (`d9f2323`, `544f1ed`). Native download/relaunch and failure/recovery acceptance remain. |
| Advanced: temporary files and thumbnails | Mac | Redesigned | `settings.md`; `feature-triage.md` | The old cache editors are removed (`894ccd5`). A failed clear must show in place with Retry (in progress). |
| Devices / current Pixel | Mac | Redesigned | `navigation.md` D3; `interaction.md` I2 | — |
| Rename device sheet and discard confirmation | Mac | Redesigned | `platform-expression.md` A4/A5 (`82a460f`) | Native fitted-height, dirty-dismissal and save-failure acceptance. |
| Help Center | Mac | Redesigned | `interaction.md` I2/I8; `platform-expression.md` A7 | — |
| Help articles by task and problem | Mac | Redesigned | `interaction.md` I2/I8 | Native long-content/localization acceptance. |
| Diagnostics: export and recent activity | Mac | Redesigned | `settings.md` Diagnostics (`b954262`, `222c950`) | Secondary page from the Settings footer; Back restores the category. Native save-panel acceptance remains. |
| Menu-bar icon and status menu | Mac | Redesigned | `interaction.md` I1/I3; `platform-expression.md` A0 (`bec2e13`) | Implementation is committed; native menu, state and action acceptance remains. |
| Backup notifications | Mac | Redesigned | `apple-notifications.md` (`27765f7`, `e325845`) | Receiver-scoped route consumer and permission entry. System delivery and cold/warm tap acceptance remain. |
| Read-only album browser | Mac | Redesigned | `platform-expression.md` A6 (`49efc3e`) | Reachable through the shared chooser context menu; native grid/search/return/selection continuity remains. |
| Open source & licenses, bundled-license reader | Mac | Redesigned | `settings.md` (`d9f2323`, `544f1ed`) | Native long-content and external-link acceptance remain. |
| Send Feedback → external user group | Mac | Redesigned | `settings.md` (`d9f2323`, `544f1ed`) | Group handoff is available; absent email and rating stay hidden. Native external-return acceptance remains. |

## Pixel receiver

Shared body, supporting, footnote, empty-state and confirmation text use balanced
line breaks without hyphenation (`c88e354`); transfer scope wording is corrected
(`cc1fa7b`).

| Page | Platform | State | Contract | Change / remaining blocker |
| --- | --- | --- | --- | --- |
| Root navigation | Pixel | Redesigned | `navigation.md`; `platform-expression.md` A3 | Old Home, History, Storage and settings objects are removed; old restored pages and saved tab 3 open the current pages (`2413496`). |
| First run: Welcome, Keep Running, photo-service setup and Free Space | Pixel | Redesigned | `flows.md` First run | Free Space opens Storage/cleanup (`895f8e5`); permission, external-app return and first-run continuation acceptance remain. |
| Receive hub and recent-photo mosaic | Pixel | Redesigned | `flows.md`; `interaction.md` I2 | Cleanup opens Storage (`895f8e5`); photos use the adopted viewer (`0c2c0ea`). Native viewer acceptance remains. |
| Received Photos timeline and problem cards | Pixel | Redesigned | `records.md` (`58e31f2`, `47ff0d2`) | D1 adopted (`0c2c0ea`); global latest-change ordering across core pages (`f9b08f4`). Native preview/selection acceptance remains. |
| Live Photo cause / affected-photos sheet | Pixel | Redesigned | `records.md`; `platform-expression.md` A7 | Uses adopted viewer and contextual selection (`0c2c0ea`); native large-group scrolling, selection and detail-return acceptance remain. |
| Photo viewer and bottom information panel | Pixel | Redesigned | `records.md`; `platform-expression.md` A8 (`0c2c0ea`, `f266d9b`, `36a10d1`) | System-composed black viewer, failure-only Retry, coordinated details with recorded camera/file/video/location metadata and safe navigation inset; old close button/per-photo disclaimer removed. Native loading, drag/zoom, return and metadata-failure acceptance remain. |
| Connect: iPhone code, Mac direction, failure and success | Pixel | Redesigned | `pixel-connect.md` (`f47e726`) | Native back, recreation, scanner-return and real-pairing acceptance. Uses a pushed production destination. |
| Mac-code camera scanner | Pixel | Redesigned | `pixel-connect.md` | Native camera denial, cancellation and return acceptance. |
| Connected Devices list | Pixel | Redesigned | `pixel-connect.md` (`f47e726`) | Empty-device routing and theme recreation fixed (`cc1fa7b`); native restore/back and stopped-device acceptance remain. |
| Individual device sheet | Pixel | Redesigned | `pixel-connect.md`; `platform-expression.md` A7/A11 | Native stop/resume failure acceptance. |
| Stop receiving from device confirmation and Undo snackbar | Pixel | Redesigned | `platform-expression.md` A5/A9 (`82a460f`) | Native confirmation, failure and Undo acceptance. |
| Settings root | Pixel | Redesigned | `settings.md` | Bottom/About/feedback rebuilt (`895f8e5`); Help, Advanced and Diagnostics descendants redesigned (`ef3a8fd`, `222c950`). Footer names are being unified with Apple (in progress). |
| Appearance and Language dialogs | Pixel | Redesigned | `settings.md`; `platform-expression.md` A0 (`82a460f`) | Native theme/locale recreation acceptance. These are dialogs, not standalone pages. |
| Rename Pixel dialog | Pixel | Redesigned | `platform-expression.md` A4 (`82a460f`) | Native validation, keyboard and failed-save acceptance. |
| Storage | Pixel | Redesigned | `flows.md` How the Pixel keeps space free; `settings.md` (`895f8e5`, `6ccdda8`) | Inline automatic cleanup with shared consent; grouped options, parallel copy and hidden zero-size rows. Native unknown/read-failure/control/accessibility-return acceptance and legacy account-failure recovery remain. |
| Advanced | Pixel | Redesigned | `settings.md`; `feature-triage.md` (`ef3a8fd`) | Owns the global Live Photo conversion switch, Browser access and Stop receiving. |
| Stop Receiving confirmation | Pixel | Redesigned | `platform-expression.md` A5 (`82a460f`) | Native stop/failure/result acceptance. |
| Browser access | Pixel | Redesigned | `settings.md` (`ef3a8fd`) | Masked code with hold-to-reveal, Copy, code editing, reset/sign-out confirmations and startup retry. Native FLAG_SECURE and real-browser acceptance remain. |
| Check for Updates: checking, available, download, failure and installation handoff | Pixel | Redesigned | `settings.md` | About owns version/status; detail owns check/download/install and automatic switch (`895f8e5`). Native failure/retry, cancellation and installation handoff acceptance remain. |
| Help Center: tasks, problems and articles | Pixel | Redesigned | `settings.md` Help Center; `interaction.md` I2/I8 (`ef3a8fd`) | Old topic links still resolve. Native long-content acceptance remains. |
| Automatic cleanup: setup, account confirmation, progress and result | Pixel | Redesigned | `flows.md` Free space automatically (`ef3a8fd`) | One journey under Storage; the technical probe tool is removed (`2413496`). Physical Google Photos and external-app return acceptance remain. |
| Cleanup consent dialog | Pixel | Redesigned | `ui-content-rules.md` Application consent; `platform-expression.md` A5 | Shared consent from Storage; probe consent and Reviewed confirmation are removed (`2413496`). |
| Waking/unlocking transient screen | Pixel | Legacy | Target: `flows.md`; `ui-content-rules.md` External operations | Standalone text with literal typography/padding lacks a page contract and review. |
| Diagnostics: export and recent activity | Pixel | Redesigned | `settings.md` Diagnostics (`222c950`) | One JSON export (receiver log, Photos-saving receipts, automatic cleanup observations without the account name, `2413496`) and the newest events by day. Old log, report, archive and retention routes open it or Storage. |
| Operation-failed / Retry sheet | Pixel | Legacy | Target: `platform-expression.md` A7/A9/A10 | Generic modal error wrapper needs task-specific in-place or explanatory recovery review. |
| Ongoing receiver notification and stopped/restart reminder | Pixel | Redesigned | `ui-content-rules.md` System notifications (`c8f4af3`) | Actual system rendering and Receive/Needs you/Storage cold/warm tap acceptance. |
| About BackupDuck | Pixel | Redesigned | `settings.md` (`895f8e5`) | Version/update status, privacy, source/licenses and website rebuilt; absent author content hidden. Native update/external-return acceptance remains. |
| Send Feedback → external user group | Pixel | Redesigned | `settings.md` (`895f8e5`) | Direct group handoff while email is absent; reserved email UI hidden. Native external-return/failure acceptance remains. |
| Storage cleanup enable-consent / accessibility-settings handoff | Pixel | Redesigned | `settings.md`; `ui-content-rules.md` Application consent (`895f8e5`, `6ccdda8`) | Native settings failure/return and enable persistence remain; consent proves neither account binding nor cloud backup. |

## Retired

Removed pages whose old links or restored state now open a current page:
Pixel Experiments overview, technical Photos probe and its export, Format
Conversion page (now a switch in Advanced), old browser sheets, storage limits
and retention editors, original archive export/result/reclaim pages, old
Diagnostics index/log/report pages; iPhone and Mac Diagnostics log/detail and
retention pages; the Mac Settings window, old overview, transfer list,
Receiver page and pairing sheet; iPhone old Backup, Receiver and Settings
roots (`ef3a8fd`, `222c950`, `2413496`, `894ccd5`).
