# Apple test distribution and Xcode Cloud

The Apple hosts share the Rust engine and UI sources. App Store Connect builds
use the production `app.backupduck` identity; signing assets and account details
are never committed. The website and GitHub release channels remain independent.

## Projects and signing

- iOS: `apps/ios/BackupDuck.xcodeproj`. Use the channel schemes below for
  device development, external testing and App Store review.
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

## iPhone packages and Pro availability

| Package | Xcode scheme | Identity | Pro access |
| --- | --- | --- | --- |
| InHouse | `BackupDuckInHouse`, run with `InHouse` | `app.backupduck.inhouse` | Included for development testing |
| TestFlight | `BackupDuckTestFlight`, archive with `TestFlight` | `app.backupduck` | Included for external testing |
| App Store | `BackupDuckAppStoreSubmission`, archive with `AppStoreSubmission` | `app.backupduck` | Welcome access and verified subscriptions |

InHouse uses Apple Development signing on registered devices. It installs next
to the production app with its own sandbox, pairing credential, background jobs
and Live Activity route. The iPhone TestFlight package shares the production
identity so an in-place channel change can keep the person's data. Its Settings
page shows that Pro is included. Both test packages run backup without a trial,
purchase, renewal check or access deadline.

Only the App Store package enables purchase. The signed `AppTransaction` must
match the app bundle. Production installations accept production purchases.
Unresolved checks retry on foreground entry without blocking backup. Mac
TestFlight and direct downloads retain the existing unrestricted backup behavior.

The `BackupDuckAppStoreSubmission` scheme on each platform archives the ordinary
store target with the `AppStoreSubmission` configuration. This configuration
also accepts a verified matching sandbox app transaction and sandbox purchases
for App Review. Apple reviews the same archive that goes to customers.
Upload the submission archive to App Store Connect for App Review only. Keep it
out of TestFlight groups, including automatic internal groups. Select the iOS
TestFlight scheme for beta archives and never attach a TestFlight archive to
an App Store version. Use `BackupDuckStore` for Mac external testing.

Distribution detection uses `AppTransaction.shared` without an explicit receipt
refresh or account-authentication fallback and requires no application server.
The direct Mac target skips the check. Physical acceptance covers real account
and offline conditions; fixture tests alone do not establish system-prompt
behavior.

Catalog uses explicit preview injection to exercise the production-only UI and
non-production bypass. Those fixtures do not establish installed-channel or
real-purchase acceptance. Verify store, TestFlight and direct-download behavior
separately before distribution, including preserved data across channel changes.

### Pro submission and metadata

Keep feature merges separate from a release manifest bump. A new version on
`main` also triggers the direct-download release and the ordinary TestFlight
pipeline. Select the App Store build number deliberately and verify both
archives before attaching them to their App Store versions.

- In App Store Connect, verify the Paid Apps Agreement is active. Create
  `app.backupduck.pro.monthly` (one month) and
  `app.backupduck.pro.annual` (one year) in the same group at the same service
  level. Set availability and actual storefront prices. Confirm both Apple hosts
  resolve the same products and restore access for the purchasing Apple Account.
  Leave introductory offers unset because the app provides the welcome week.
- Publish and verify the [privacy policy](https://backupduck.app/privacy.html)
  and [Pro subscription terms](https://backupduck.app/subscription-terms.html).
  Set the Privacy Policy URL to the policy. When using the Apple Standard EULA,
  include its URL in each localized App Store description. Use the billing
  summary below and its equivalent from the localized Pro terms.
- Verify the iPhone archive contains `PrivacyInfo.xcprivacy`. Its required-reason
  entries cover app-owned preferences and file metadata, plus local space checks
  that protect writes. Diagnostic exports omit device free-space measurements
  and the write allowance derived from them.
- Submit the first subscriptions alongside the app version. In review notes,
  give the Settings → BackupDuck Pro path, the two billing periods, and
  explain that the app grants welcome access before any purchase. Include
  the pairing and receiver instructions needed to exercise backup.
- Before submission, verify that App Review can see, buy and restore both
  plans in Apple's sandbox using the dedicated submission configuration.
  Verify iPhone TestFlight and InHouse include Pro and omit purchase controls.
  Verify Mac direct-download builds still allow backup without a subscription.

**English App Store description**

> BackupDuck Pro offers monthly and annual subscriptions. Apple charges the full
> price for the selected billing period. Your plan renews automatically unless
> cancelled in your Apple Account settings. The complimentary seven-day welcome
> period ends without a charge or automatic subscription.
>
> Privacy Policy: https://backupduck.app/privacy.html
>
> Pro Subscription Terms: https://backupduck.app/subscription-terms.html
>
> Terms of Use (Apple Standard EULA):
> https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

References: [subscription disclosures](https://developer.apple.com/app-store/subscriptions/),
[review in the sandbox](https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases),
[first in-app purchase submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase).

### Local purchase development

`BackupDuckStoreKitTest` is an independently installed development host with
bundle identifier `app.backupduck.storekittest`. It reuses the native application
and Rust sender with separate storage. Build it in Release for device review;
it does not replace the production application or establish release acceptance.
Its explicit `BACKUPDUCK_SUBSCRIPTION_TESTING` condition is absent from ordinary
store, TestFlight and direct-download targets. Never archive or distribute this
host.

Run its scheme from Xcode with `apps/apple/StoreKit/BackupDuck.storekit` selected
as the StoreKit configuration. A command-line installation or ordinary launch
alone does not establish that purchase testing is active. The host refuses
purchase when the expected local environment is unavailable. Confirm that a
successful transaction is verified and has the Xcode environment before treating
it as a test result. The configuration contains monthly and annual subscriptions with
no introductory offer; complimentary welcome access is maintained by the app.

Local welcome controls exist only in this development host. Apple's transaction
manager and StoreKitTest under XCTest control transaction renewal, cancellation,
expiry and refund cases. Do not initialize `SKTestSession` inside the ordinary
application process. Record native UI, automated store tests and physical-device
observations separately; simulated purchase is not a production charge or App
Store availability check.

References: [App transaction verification](https://developer.apple.com/documentation/storekit/verificationresult),
[Store environments](https://developer.apple.com/documentation/storekit/appstore/environment),
[TestFlight sandbox behavior](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox).

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
matching `testflight/*`, one clean archive action and TestFlight internal
and external testing post-actions for the existing test groups. External testing
requires a clean archive; enable no-cache mode for these release-only workflows.
Keep Cloud test actions, scheduled builds and
branch/pull-request triggers disabled to limit compute use.
Run the existing tests locally or in GitHub Actions before starting a release;
Cloud is reserved for distribution signing, archive and upload.
The iOS external workflow can use its existing `BackupDuck` scheme, whose
archive action selects the same configuration as `BackupDuckTestFlight`.
It also matches `testflight-ios/*` for iPhone-only releases. The Mac external
workflow selects `BackupDuckStore` and uses the shared tag prefix.

The iOS App Store Review workflow runs on manual selection of `main` with the
`BackupDuckAppStoreSubmission` scheme. Its only action is the App Store-eligible
archive. Submitting the resulting build to App Review is a separate step in
App Store Connect.

The `Start TestFlight release` GitHub workflow runs only after successful `Checks`
on the current public `main` commit. It creates a tag once per version from
`release.json`. The `all` scope defaults to `testflight/v<version>` for both
Apple platforms and enables direct distribution. The `ios` scope creates
`testflight-ios/v<version>` and skips Mac and Android direct publishing.
Existing markers are never moved. Ordinary commits
and failed or superseded checks do not trigger another Cloud build. PR code never
runs with the release workflow's write token. Set an initial marker for a version
already uploaded before enabling Cloud tag triggers, to avoid a duplicate upload.
For a new version, update all version metadata and testing notes, then push to
`main`. To retry checks from a terminal, use `gh workflow run ci.yml --ref main`.
Retry an already marked Cloud version manually after fixing a distribution error;
do not delete and recreate its marker. The external testing post-action submits
that workflow's archive to the configured external group and Beta App Review
when required. It must use the new archive rather than select an older uploaded
build by marketing version alone. Apple approval and App Store submission remain
separate from a successful upload.

### Automatic tester notification

Automatic notification belongs to each build's beta details, not a global app or
external-group preference. Enable it for every new iOS and macOS external-test
build. In a manual submission, select **Automatically notify testers**. An API
distribution flow must verify the exact build's `autoNotifyEnabled` is true.
Keep the Cloud external-testing post-action tied to its archive and intended
group, but do not infer the notification flag merely from that workflow action.

After Beta App Review, **Approved** with **Notify Testers** still available means
distribution is pending. Verify **Testing** in the intended external group before
reporting tester availability. If notification was left off, complete distribution
unless the user explicitly reserved that build's manual notification for themselves.
Do not upload another build or start Cloud merely to verify this setting.

References: [notify external testers after approval](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/),
[per-build beta details](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-buildbetadetails).

If a previous build of the same platform/version is still under beta review,
Apple may block a replacement. Release acceptance includes checking the exact
build number in the external group and its review state. Withdraw the superseded
submission and submit the intended successful build; do not mark the release
complete merely because Cloud uploaded it. Report a review conflict or failed
post-action as a release failure instead of leaving testers on an older build.

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
Each Apple project keeps testing notes in English and Simplified Chinese, in
`TestFlight/WhatToTest.en-US.txt` and `TestFlight/WhatToTest.zh-Hans.txt`; Cloud
attaches each file to the matching TestFlight language of uploaded builds. Keep
both files current together and each well under 2 KB.
Update these files with the release instead of relying on manual console edits.
The attachment is automatic; writing release-specific testing instructions is
part of the source change, not an automatically generated summary of commits.

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
Mac checks and direct-download publishing use the same explicit `macos-26`
runner family so release builds do not silently use an older SDK than checks.
Both Mac jobs print the selected Xcode, Swift and SDK versions. Runtime
availability checks retain macOS 15 support; APIs introduced with the
macOS 26 SDK also need a compiler guard when supporting Xcode 16 builds.

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
