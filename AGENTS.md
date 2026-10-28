# BackupDuck contributor and agent conventions

## Scope and ownership

The current UI covers the iPhone/iPad sender, macOS sender and Android
receiver. Android and Windows sender hosts remain separate, unfinished work.
Do not expand a focused change into those platforms without an explicit scope.

Rust owns asset/request identity, receiver ownership, durable preparation and
transfer queues, concurrency, retry, receipt and processing observations. Hosts
provide media access, permissions, native UI, credentials and OS execution.
Do not create a second business queue or infer cloud backup from receipt.
See `docs/architecture.md` and `docs/sender-host-contract.md`.

## Design changes

Read `design/README.md`, `design/platform-expression.md`,
`design/visual-language.md`, `design/interaction.md`, `design/ui-content-rules.md`
`design/foundations/motion.md` and `design/apple-motion-apis.md` before UI work.
Motion uses system animation APIs only; app code never draws animation frames.
BackupDuck is UIKit/AppKit first: grids, the viewer, transitions and their gestures
and bars are native UIKit/AppKit; SwiftUI is for supporting pages only.
The contracts in `design/` and the native apps are the reference; do not
create HTML prototypes.

- Follow `design/constitution.md`. A change to a page's structure starts from
  its contract and updates the contract in the same change; never port or
  reword an older page instead of designing for ordinary users.
- Reuse shared components. Components own inner padding and alignment; pages
  own section spacing. Store justified density differences in platform metrics.
- Apple preference rows use 52 pt on iPhone and 41 pt on Mac (visual standard
  V7), growing for wrapped or accessibility text. Check group edges and complete page compositions.
- Colors, semantic text styles, spacing, radius and motion come from
  `design/foundations/tokens.json`. Run `python3 scripts/export-design-tokens.py`
  after edits and `--check` to verify; do not edit generated files by hand. New
  code uses the role tokens (`DuckRole`, `duck_role_*`), not the legacy palette.
  `python3 scripts/check-design-literals.py` rejects new literal colors and text
  sizes; document real exceptions with a `design-exception:` comment.
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
- Application consent uses the shared sheet contract; system permissions remain
  system-owned. Passive thumbnail loading must not interrupt browsing with consent.
  Persistent Booleans use shared leading-label/trailing-switch preference rows.
- Large choice sets open a searchable, virtualized secondary editor. Never expand
  an unbounded album list into a preference group. Reuse library type vocabulary.
- Receipt, phone-gallery publication and cloud upload are independent facts.
  Never invent missing progress, dates, device readings or cloud confirmation.

New navigation or workflows are specified in the contract documents and checked
in the native app; do not add HTML references. Gesture and density behavior must
reuse the shared native core in `apps/apple/Shared` rather than a per-platform
rewrite. Component refinements update components and contracts in one change. Inspect similar uses before treating feedback as a single-screen fix.

## Local design notes

Reference research, design decisions, plans, review records, agent notes and
handoff state live in ignored local storage, `build/internal-docs/`. Public
`design/` states current rules, principles and contracts only: no status lines,
approvals, dates, decision history, process narratives or version labels. When
`build/internal-docs/codex-context.md` or `build/internal-docs/agent-notes.md`
exists, read it before starting work (local environment, test devices, issue
tracking and current state) and keep the notes current when you stop. Do not
name reference products in tracked files; state rules and reasons in
BackupDuck's own terms. `scripts/audit-public.py` also applies the local term
list when it exists.

## Verification

Before each commit, run the `Checks` commands (`.github/workflows/ci.yml`) for
the areas you changed and read each command's own exit status; never judge a
check through a truncated pipe:

- Rust: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets
  --locked -- -D warnings`, `cargo test --workspace --locked`, and the
  `folder-source` clippy and test commands for folder or native changes.
- Design and copy: `python3 scripts/export-design-tokens.py --check` and
  `python3 scripts/check-design-literals.py`.
- Every commit: `python3 scripts/audit-public.py --staged --documentation`.

Gradle does not rebuild the Rust core: after a Rust change, run
`scripts/build-android.sh` before building or installing the Android app, or the
APK keeps the previous `libbackupduck_native.so`. Test temporary directories are
unique per test (process ID plus a sequence), because tests run in parallel.

Copy changes update English and Simplified Chinese together and follow
`design/copy-glossary.zh.md` and `design/ui-content-rules.md`. TestFlight
testing notes exist in both `en-US` and `zh-Hans` for iOS and Mac.

Work on a branch with one fix or feature per commit. Commit messages state what
changed and why, never review or acceptance narratives. Do not push, merge, tag
or publish without explicit authorization.

Follow `design/iteration-checklist.md`. Run affected builds and existing checks,
then inspect active native windows for light/dark, narrow layouts, large text,
long localized content, failure and recovery. View rectangles or text existence
alone do not prove visible, correctly aligned feedback.

Physical release acceptance must use the production app identity, release build
and expected release signing certificate. Verify these before installation.
Validation packages supplement tests and do not replace production acceptance.

Use synthetic data for repeatable fixtures. Record native checks and physical-device
observations separately. State uncovered behavior
honestly. Preserve application data during updates; never uninstall or clear data
without explicit authorization. Re-identify the target device before installation.

Judge motion, feel and performance only on Release builds, and measure them from
60 fps recordings of the app window (frame-to-frame change, blank or bright
frames, motion after the settle), not from sparse screenshots. Observe the
system app for the same interaction first and record what it does.

For gesture changes, inspect complete reference interactions and define start,
drag, reversal and settled states before implementation. Record synthetic native
motion and inspect intermediate frames. Check a mid-library anchor and zoom/input
ownership, not only final labels. Endpoint assertions do not prove motion quality.

## Public source

Follow `docs/public-source-policy.md`. Contributor documents and code comments
use English. Keep product localization and explicitly labeled translated user
guides. Personal acceptance narratives, design decisions and process, chat
attachments, installation logs, private machine details and agent handoffs are
local-only.

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
