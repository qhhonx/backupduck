# BackupDuck contributor and agent conventions

## Scope and ownership

The 0.3.0 UI baseline covers the iPhone/iPad sender, macOS sender and Android
receiver. Android and Windows sender hosts remain separate, unfinished work.
Do not expand a focused change into those platforms without an explicit scope.

Rust owns asset/request identity, receiver ownership, durable preparation and
transfer queues, concurrency, retry, receipt and processing observations. Hosts
provide media access, permissions, native UI, credentials and OS execution.
Do not create a second business queue or infer cloud backup from receipt.
See `docs/architecture.md` and `docs/sender-host-contract.md`.

## Design changes

Read `design/README.md`, `design/backupduck-v1/specification.md`,
`design/ui-content-rules.md` and `design/backupduck-v1/motion.md` before UI work.
Use current component contracts when a historical prototype differs; update the
prototype in the same change rather than reverting the implementation.

- Reuse shared components. Components own inner padding and alignment; pages
  own section spacing. Store justified density differences in platform metrics.
- Apple preference rows use 52 pt on iPhone and 48 pt on Mac, growing for wrapped
  or accessibility text. Check group edges and complete page compositions.
- Semantic colors come from `design/backupduck-v1/tokens.json`. Run
  `python3 scripts/export-design-tokens.py` after edits and `--check` to verify.
  Do not edit generated platform colors by hand.
- Native grids and lists retain virtualization, cancellation/cache, stable IDs,
  paging, sorting, selection and scrolling. Do not replace them with WebViews.
- Keep progress geometry stable. Progress overlays do not add layout rows.
  Queue pause, automatic discovery and existing-library scope are distinct.
- Pending original preparation is part of the normal task feed: active while
  waiting, attention on failure. Scan records are not transfer jobs; show scan
  progress with its controls rather than adding ordinary navigation entries.
- Working pages show current state, next action and relevant consequences once.
  Internal terminology belongs in help or diagnostics. Errors stay actionable.
- Confirmations save durable intent. Downloads, export and transfer continue on
  task screens after registration; failure preserves input and selection.
- Derive system brand marks from `assets/AppIcon.png`; do not redraw a substitute.
- Respect reduced motion/transparency, contrast and platform fallbacks. Android
  and browser surfaces remain solid; old-device performance takes priority.
- Receipt, phone-gallery publication and cloud upload are independent facts.
  Never invent missing progress, dates, device readings or cloud confirmation.

New navigation or workflows require an interactive reference before implementation.
Component refinements update components, contracts and affected references in one
change. Inspect similar uses before treating feedback as a single-screen fix.

## Verification

Follow `design/iteration-checklist.md`; Android also uses
`design/android-v1.2/native-acceptance.md`. Run affected builds and existing checks,
then inspect active native windows for light/dark, narrow layouts, large text,
long localized content, failure and recovery. View rectangles or text existence
alone do not prove visible, correctly aligned feedback.

Physical release acceptance must use the production app identity, release build
and expected release signing certificate. Verify these before installation.
Validation packages supplement tests and do not replace production acceptance.

Use synthetic data for repeatable fixtures. Record prototype checks, native
checks and physical-device observations separately. State uncovered behavior
honestly. Preserve application data during updates; never uninstall or clear data
without explicit authorization. Re-identify the target device before installation.

## Public source

Follow `docs/public-source-policy.md`. Contributor documents and code comments
use English. Keep product localization and explicitly labeled translated user
guides. Personal acceptance narratives, chat attachments, installation logs,
private machine details and agent handoffs are local-only.

Run `python3 scripts/audit-public.py --documentation` before preparing source,
then `--staged --documentation` against the entire candidate index. Ignore rules
do not remove tracked files. Keep temporary evidence in ignored local storage.

`release.json` is the version/build authority. Update platform metadata and release
notes together. Builds increase monotonically.
Preserve installed-client trust anchors and legacy update endpoints; consult
`docs/upgrading.md` before changing app identities, certificates or feeds.
For Apple store/test distribution, follow `docs/apple-distribution.md`. Keep
the Mac store target sandboxed and free of Sparkle, inject the signing team via
local/Cloud configuration, and distinguish upload from tester availability.
GitHub `Checks` gates new `testflight/v<version>` markers on current `main`.
Cloud archives/uploads only; keep ordinary push, scheduled and test actions off.
Release workflows also attach source-controlled testing notes and deliver their
own archive through the external TestFlight post-action. Verify the intended
platform/build is awaiting beta review or available, not merely uploaded. Handle
superseded review submissions as part of release work without waiting for a user
to discover a stale build. Apple approval remains a separate external outcome.
Enable and verify automatic tester notification for each new iOS and macOS
external-test build. This is a per-build setting, not an app-wide switch. Manual
submission must select Automatically notify testers; API distribution must verify
that build's `autoNotifyEnabled` is true. A Cloud external-testing post-action alone
does not prove the flag or tester availability. Approved with Notify Testers still
visible is pending distribution; Testing in the intended external group is the
availability gate. Respect any user instruction to handle a current build manually.
Never move an existing release marker to force a retry; start Cloud manually.
A push to `main` may publish apps and deploy the website: do not merge, tag or
publish without explicit authorization.
Do not rewrite published history as part of routine source cleanup.
