# Upgrade compatibility

0.3.0 uses build 47, 0.4.0 uses build 87, 0.4.1 uses build 88 and 0.5.0 uses build 89,
with the same application identities, signing certificates, update keys and feeds. Discovering a release
and installing it are separate compatibility questions. Automatic checking is not unattended installation.

## Release discovery

| Installed official version | macOS Check for updates | Android receiver Check for updates | iOS |
| --- | --- | --- | --- |
| BackupDuck 0.4.1 | Supports discovering 0.5.0 through the same signed feed on macOS 15 or later | Supports the stable 0.5.0 tag and BackupDuck metadata | No built-in updater; TestFlight controls availability |
| BackupDuck 0.4.0 | Supports discovering 0.4.1 through the same signed feed | Supports the stable 0.4.1 tag and BackupDuck metadata | No built-in updater; TestFlight controls availability |
| BackupDuck 0.3.0 | Supports discovering 0.4.0 through the same signed feed | Supports the stable 0.4.0 tag and BackupDuck metadata | No built-in updater; TestFlight controls availability |
| BackupDuck 0.2.0-rc.1 / rc.2 / rc.3 | Supports discovering 0.3.0 through the retained signed feed | Supports the stable 0.3.0 tag and BackupDuck metadata; RC.1's certificate difference affects installation, not discovery | No built-in updater; TestFlight controls availability |
| PhotoBridge 0.1.x | Supports discovery through the retained PhotoBridge feed and public key | The old updater requires PhotoBridge repository URLs and APK names; ordinary BackupDuck metadata is rejected | No built-in updater; the application identity changed |

The macOS 0.1.x and 0.2.x release tags retain compatible feed keys. A valid
signed feed and complete release metadata must advertise the higher build
number for discovery to succeed. From 0.5.0 the Mac app requires macOS 15 and the
iPhone app iOS 18; Sparkle reads the minimum from the app, so Macs on macOS 14
are not offered 0.5.0 and keep 0.4.1. An informational update check verifies
availability; it does not prove a successful installation or an in-place
migration across application identities.

The Android 0.1.x updater also rejects RC tags. Although it accepts a stable
0.3.0 tag, it requires `qhhonx/photobridge` download URLs and
`PhotoBridge-<version>-arm64.apk`. Repository redirects do not change those
hard-coded comparisons. Legacy Android discovery needs a separately designed
compatibility path; retaining the website address alone does not fix it.

## Installation compatibility

| Installed official version | macOS | Android receiver | iOS |
| --- | --- | --- | --- |
| BackupDuck 0.4.1 | Eligible for a signed Sparkle update on macOS 15 or later | Eligible for the built-in update; Android asks for installation confirmation | Update through TestFlight on iOS 18 or later when the new build is available |
| BackupDuck 0.4.0 | Eligible for a signed Sparkle update | Eligible for the built-in update; Android asks for installation confirmation | Update through TestFlight when the new build is available |
| BackupDuck 0.3.0 | Eligible for a signed Sparkle update | Eligible for the built-in update; Android asks for installation confirmation | Update through TestFlight when the new build is available |
| BackupDuck 0.2.0-rc.2 / rc.3 | Eligible for a signed Sparkle update | Eligible for the built-in update; Android asks for installation confirmation | Update through TestFlight when the new build is available |
| BackupDuck 0.2.0-rc.1 | Eligible for a signed Sparkle update | Different signing certificate; cannot update in place | Update through the same TestFlight application |
| PhotoBridge 0.1.x | Different application identity; no ordinary in-place update to BackupDuck | Different package identity; no in-place update to BackupDuck | Different application identity; install the new application |
| Self-built or validation application | Depends on its embedded identity and trust keys | Must retain its package and signing certificate; validation packages are separate | Rebuild and install with the same compatible signing identity |

Eligible means the application identity and trust configuration are compatible;
it is not evidence that a published upgrade has been installed successfully.
Mac builds must increase their Sparkle build number. Android builds must increase
versionCode and retain the official certificate introduced in RC.2.

PhotoBridge used `app.photobridge.mac`, `app.photobridge.ios` and
`app.photobridge`; BackupDuck uses `app.backupduck`. This was an application and
protocol transition, not just a display-name change. Old databases are not
automatically migrated. Preserve the old application, retained originals and
records until their contents have been reviewed. Do not advise uninstalling an
old application as a routine upgrade step. A different Android certificate cannot
be bypassed by downloading the APK manually.

## Keep installed clients connected

BackupDuck 0.2.x embeds `https://backupduck.vercel.app/appcast.xml` on Mac and
`https://backupduck.vercel.app/api/releases` on Android. Keep these working when
the primary site moves to GitHub Pages. The new site uses
`https://backupduck.app/appcast.xml` and `/releases.json`. Preserve signed appcast
bytes exactly; do not rewrite XML during proxying or static generation.

PhotoBridge 0.1.x embeds `https://photobridge-app.vercel.app/appcast.xml` and
old repository/package/download identities. Its Mac feed currently advertises
BackupDuck, which can be discovered. Do not describe that discovery as evidence
of a supported in-place installation across application identities.

Before publication, check the ordinary old and new URLs, increasing build,
archive/feed signatures and APK certificate. Exercise an isolated update with
the real old identity and new signed artifact before claiming end-to-end upgrade
success. Keep detection, download verification, installation and preserved-data
verification as separate observations.

See [installation](installation.md), [releasing](releasing.md) and
[website hosting](website-hosting.md).
