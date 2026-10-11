# Apple test distribution and Xcode Cloud

The Apple hosts share the Rust engine and UI sources. App Store Connect builds
use the production `app.backupduck` identity; signing assets and account details
are never committed. The website and GitHub release channels remain independent.

## Projects and signing

- iOS: `apps/ios/BackupDuck.xcodeproj`, shared scheme `BackupDuck`.
- Mac direct download: `apps/macos/BackupDuck.xcodeproj`, scheme `BackupDuck`,
  with the signed Sparkle update feed.
- Mac TestFlight/App Store: the same project, scheme `BackupDuckStore`. This
  target enables App Sandbox, read-only user-selected folder bookmarks, Photos
  and local network access. It does not link or embed Sparkle; updates are
  managed by TestFlight or the App Store.

Both Apple projects include `apps/apple/Signing.xcconfig`. For local automatic
signing, create the ignored `build/AppleSigning.xcconfig` with
`DEVELOPMENT_TEAM = YOUR_TEAM_ID`, sign into Xcode and select your own paid team.
Do not commit provisioning profiles, credentials, signing identities or this
local configuration. Regenerate projects from the corresponding `project.yml`
with XcodeGen when their source lists or build settings change.

The Mac icon sizes derive from `assets/AppIcon.png`; system menu artwork retains
its original-artwork-derived template. The store target has its own Info.plist
without direct-download updater keys. Keep its product version aligned with
`release.json`; increment actual uploaded build numbers when submitting again.

## Cloud workflows

Configure the first workflow through Xcode with the public distribution
repository. Grant access only to that repository. Each project's
`ci_scripts/ci_post_clone.sh` invokes `scripts/xcode-cloud-setup.sh`, which installs
the pinned Rust toolchain/Apple targets and writes its selected `CI_TEAM_ID` into
the ignored signing configuration. It isolates the TOML parser dependency in a
build-local Python environment, supporting Xcode images with Python 3.9 as well
as newer images. Xcode's build phase compiles the native
library; Xcode Cloud manages distribution signing and TestFlight delivery.
The Cloud checkout uses a directory override for the installed Rust version so
archive phases do not install development-only formatter/linter components.

Use separate iOS and Mac workflows with manual start and a tag-change condition
matching `testflight/*`, one Release archive action and TestFlight delivery to the
existing test groups. Keep Cloud test actions, scheduled builds and
branch/pull-request triggers disabled to limit compute use.
Run the existing tests locally or in GitHub Actions before starting a release;
Cloud is reserved for distribution signing, archive and upload.
The Mac workflow must select `BackupDuckStore`, not the direct-download scheme.

The `Start TestFlight release` GitHub workflow runs only after successful `Checks`
on the current public `main` commit. It creates `testflight/v<version>` once per
version from `release.json`; existing markers are never moved. Ordinary commits
and failed or superseded checks do not trigger another Cloud build. PR code never
runs with the release workflow's write token. Set an initial marker for a version
already uploaded before enabling Cloud tag triggers, to avoid a duplicate upload.
For a new version, update all version metadata and testing notes, then push to
`main`. To retry checks from a terminal, use `gh workflow run ci.yml --ref main`.
Retry an already marked Cloud version manually after fixing a distribution error;
do not delete and recreate its marker. External TestFlight review and App Store
submission remain separate from a successful upload.

Xcode Cloud assigns its own monotonically increasing build counter. Set the next
number above existing uploaded Mac builds before starting distribution. When a
local release shares the same version, inspect the actual TestFlight counter
before selecting its next build number. A GitHub artifact version does not prove
that an Apple test build has been uploaded or made available to testers.

## Encryption and metadata

The current Apple test-distribution plan excludes France. Both store hosts use
standard cryptography for secure local transfer; they do not implement a
proprietary encryption algorithm. The App Store Connect questionnaire was
completed with standard algorithms outside the Apple OS and no French
distribution. Its result requires no encryption document for this scope.
`ITSAppUsesNonExemptEncryption` is false in both store Info.plists to retain that
result for subsequent builds. This does not mean the apps contain no encryption.
Revisit the declaration before changing cryptography or distribution geography.

Keep the English and Chinese Beta descriptions, marketing/privacy links, review
instructions and per-build testing notes current together. Use the custom-domain
website and privacy page; do not retain old RC pairing/migration instructions.
Each Apple project keeps English testing notes in
`TestFlight/WhatToTest.en-US.txt`; Cloud attaches these to uploaded builds.
Update these files with the release instead of relying on manual console edits.

## Acceptance

Confirm uploaded version, build, platform, processing status and tester-group
availability separately. External beta review is an Apple-controlled step.
Check a real TestFlight installation, data preservation, Photos access, pairing,
transfer and recovery. Mac sandboxed and direct-download installations use
different Application Support locations; do not assume existing direct-download
state migrates into the container. Do not overwrite or clear an installed app's
state to validate the store build.

## Automated checks

The `Checks` GitHub Actions workflow runs on standard hosted runners. Standard
macOS runners are free for public repositories; do not select paid larger runners
for this workflow. Superseded checks on the same branch are cancelled.

- iOS: `scripts/test-ios-ci.sh` builds the shared `BackupDuck` scheme and runs
  portable XCTest checks on a fresh simulator. It removes only the simulator it
  created, including on failure. These cover presentation, discovery boundaries,
  task state, diagnostics, local state events and preparation-loop control.
  `LibraryTests`, `BackgroundTests`, the video-original transfer acceptance test
  and `BackupDuckUITests` remain separate integration/visual acceptance suites;
  they require maintained Photos, receiver and OS background-session fixtures.
  CI does not claim to cover those suites or their physical-device behavior.
- macOS: cross-platform Rust tests, native folder tests, the direct-download build
  and an unsigned compilation of `BackupDuckStore`. GitHub receives no Apple
  distribution certificates or account credentials.
- Android, website and other Rust hosts retain their existing checks.

Run `scripts/test-ios-ci.sh` locally with an installed iOS simulator runtime to
reproduce the iOS job. Results remain in the ignored `build/ios-tests` directory.
Automated tests complement physical-device acceptance. They do not prove real
Google Photos cleanup, background execution duration or slow iCloud preparation.

References: [Xcode Cloud setup](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow),
[custom scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts),
[build counters](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds),
[cloud signing](https://developer.apple.com/help/account/certificates/cloud-managed-certificates),
[standard GitHub runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
